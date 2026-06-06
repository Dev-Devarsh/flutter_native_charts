package com.example.flutter_native_charts

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.opengl.GLSurfaceView
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

private const val CHANNEL_PREFIX = "flutter_native_charts/view"

/**
 * PlatformView that owns the native chart engine plus the GL renderer AND
 * the native overlay (axes / legend / tooltip).
 *
 * Dart's only job is to push data + style into the engine via FFI. The
 * per-view MethodChannel exists ONLY for the one-time `getEngineHandle`
 * handshake — every subsequent update (data, style, hover, viewport)
 * flows through native code with zero Flutter main-thread involvement.
 */
class ChartPlatformView(
    private val appContext: Context,
    viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView {
    private val chartEngineHandle: Long = ChartEngineJni.nativeCreate()
    private val viewportHandle: Long =
        if (chartEngineHandle != 0L) ChartEngineJni.nativeGetViewport(chartEngineHandle) else 0L

    private val glSurfaceView: GLSurfaceView = GLSurfaceView(appContext)
    private val renderer = ChartRenderer(chartEngineHandle, viewportHandle)
    private val overlay = ChartOverlayView(appContext, chartEngineHandle, viewportHandle)
    private val root: FrameLayout = object : FrameLayout(appContext) {
        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            if (w > 0 && h > 0) {
                updatePlotLayout(w, h)
            }
        }
    }.apply {
        setBackgroundColor(Color.BLACK)
        clipChildren = false
    }

    /** Pinch locks on scale begin: span mostly horizontal ⇒ zoom X, else zoom Y (API ≥ 27). */
    private var pinchMapsToHorizontalAxis = true

    /** Plot area (px) matching GL view insets — used for pan/zoom NDC, same as overlay. */
    private var plotLeft = 0
    private var plotTop = 0
    private var plotWidthPx = 1
    private var plotHeightPx = 1

    private val gestureDetector: GestureDetector
    private val scaleDetector: ScaleGestureDetector
    private val methodChannel: MethodChannel =
        MethodChannel(messenger, "$CHANNEL_PREFIX/$viewId")

    private val styleScratchInts = IntArray(16)

    private var isResumed = false
    private var isDisposed = false
    private var isScrubbing = false

    private var isDrawingTradeLine = false
    private var drawStartX = 0.0
    private var drawStartY = 0.0
    private var lastTradeLineDrawCancelRevision = 0L
    private var longPressDownX = 0f
    private var longPressDownY = 0f
    private val longPressMs = 400L
    private val longPressRunnable = Runnable {
        if (isDrawingTradeLine) return@Runnable
        if (!plotRect().contains(longPressDownX.toInt(), longPressDownY.toInt())) return@Runnable
        beginTradeLineDraw(longPressDownX, longPressDownY)
    }

    init {
        glSurfaceView.setEGLContextClientVersion(3)
        glSurfaceView.setRenderer(renderer)
        glSurfaceView.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY

        root.addView(
            glSurfaceView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        root.addView(
            overlay,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        gestureDetector = GestureDetector(
            appContext,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onScroll(
                    e1: MotionEvent?,
                    e2: MotionEvent,
                    distanceX: Float,
                    distanceY: Float,
                ): Boolean {
                    if (isDrawingTradeLine) return true
                    ChartEngineJni.nativeGetStyleInts(chartEngineHandle, styleScratchInts)
                    val allowPanX = styleScratchInts[10] != 0
                    val allowPanY = styleScratchInts[11] != 0
                    val width = plotWidthPx.coerceAtLeast(1)
                    val height = plotHeightPx.coerceAtLeast(1)
                    val dxNDC = -2.0 * distanceX / width
                    val dyNDC = 2.0 * distanceY / height
                    val panXAmt = if (allowPanX) dxNDC else 0.0
                    val panYAmt = if (allowPanY) dyNDC else 0.0
                    if (panXAmt != 0.0 || panYAmt != 0.0) {
                        ViewportEngineJni.nativePan(viewportHandle, panXAmt, panYAmt)
                    }
                    val plotRect = android.graphics.Rect(
                        plotLeft,
                        plotTop,
                        plotLeft + plotWidthPx,
                        plotTop + plotHeightPx,
                    )
                    if (!allowPanX) {
                        isScrubbing = true
                        if (plotRect.contains(e2.x.toInt(), e2.y.toInt())) {
                            applyScrubAt(e2.x, e2.y)
                        } else {
                            ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                            overlay.clearScrubFinger()
                        }
                    } else if (ChartEngineJni.nativeGetHover(chartEngineHandle) >= 0) {
                        ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                    }
                    return true
                }

                override fun onSingleTapUp(e: MotionEvent): Boolean {
                    overlay.clearScrubFinger()
                    val x = e.x.toInt()
                    val y = e.y.toInt()
                    val r = android.graphics.Rect(
                        plotLeft,
                        plotTop,
                        plotLeft + plotWidthPx,
                        plotTop + plotHeightPx,
                    )
                    if (!r.contains(x, y)) {
                        ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                        return true
                    }
                    val xNDC = touchToNdcX(e.x)
                    val xDomain = DoubleArray(2)
                    ViewportEngineJni.nativeGetVisibleDomain(viewportHandle, xDomain)
                    val xData = xDomain[0] + (xNDC + 1.0) * 0.5 * (xDomain[1] - xDomain[0])
                    val idx = ChartEngineJni.nativeHitTest(chartEngineHandle, xData)
                    if (idx >= 0) {
                        val current = ChartEngineJni.nativeGetHover(chartEngineHandle)
                        ChartEngineJni.nativeSetHover(
                            chartEngineHandle,
                            if (current == idx) -1 else idx,
                        )
                    } else {
                        ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                    }
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    ChartEngineJni.nativeGetStyleInts(chartEngineHandle, styleScratchInts)
                    val allowDoubleTapReset = styleScratchInts[15] != 0
                    if (allowDoubleTapReset) {
                        ViewportEngineJni.nativeReset(viewportHandle)
                    }
                    ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                    return true
                }
            },
        )

        scaleDetector = ScaleGestureDetector(
            appContext,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                    pinchMapsToHorizontalAxis =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            detector.currentSpanX >= detector.currentSpanY
                        } else {
                            true
                        }
                    return super.onScaleBegin(detector)
                }

                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    ChartEngineJni.nativeGetStyleInts(chartEngineHandle, styleScratchInts)
                    val allowZoomX = styleScratchInts[12] != 0
                    val allowZoomY = styleScratchInts[13] != 0
                    val width = plotWidthPx.coerceAtLeast(1)
                    val height = plotHeightPx.coerceAtLeast(1)
                    val nx = ((detector.focusX - plotLeft) / width).toDouble().coerceIn(0.0, 1.0)
                    val ny = ((detector.focusY - plotTop) / height).toDouble().coerceIn(0.0, 1.0)
                    val focusXNDC = 2.0 * nx - 1.0
                    val focusYNDC = 1.0 - 2.0 * ny
                    val scale = detector.scaleFactor.toDouble()
                    if (pinchMapsToHorizontalAxis) {
                        if (!allowZoomX) return true
                        ViewportEngineJni.nativeZoom(viewportHandle, scale, 1.0, focusXNDC, 0.0)
                    } else {
                        if (!allowZoomY) return true
                        ViewportEngineJni.nativeZoom(viewportHandle, 1.0, scale, 0.0, focusYNDC)
                    }
                    if (ChartEngineJni.nativeGetHover(chartEngineHandle) >= 0) {
                        ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                    }
                    overlay.clearScrubFinger()
                    return true
                }
            },
        )

        attachTouchListener()
        registerMethodChannel()
        lastTradeLineDrawCancelRevision =
            ChartEngineJni.nativeTradeLineDrawCancelRevision(chartEngineHandle)
        resumeRendering()
    }

    private fun dp(px: Float): Int {
        val d = appContext.resources.displayMetrics.density
        return (px * d).toInt().coerceAtLeast(0)
    }

    private fun updatePlotLayout(w: Int, h: Int) {
        // Left gutter for right-aligned Y tick labels outside the plot; tight right edge.
        var mL = dp(54f)
        var mT = dp(36f)
        var mB = dp(26f)
        var mR = dp(4f)
        if (w < mL + mR + dp(48f) || h < mT + mB + dp(48f)) {
            mL = dp(46f)
            mT = dp(30f)
            mR = dp(4f)
            mB = dp(12f)
        }
        plotLeft = mL
        plotTop = mT
        plotWidthPx = (w - mL - mR).coerceAtLeast(1)
        plotHeightPx = (h - mT - mB).coerceAtLeast(1)
        val lp = glSurfaceView.layoutParams as FrameLayout.LayoutParams
        lp.setMargins(mL, mT, mR, mB)
        glSurfaceView.layoutParams = lp
        overlay.setPlotMargins(mL, mT, mR, mB)
    }

    private fun touchToNdcX(x: Float): Double {
        val w = plotWidthPx.coerceAtLeast(1)
        val nx = ((x - plotLeft) / w).toDouble().coerceIn(0.0, 1.0)
        return 2.0 * nx - 1.0
    }

    private fun touchToNdcY(y: Float): Double {
        val h = plotHeightPx.coerceAtLeast(1)
        val ny = ((y - plotTop) / h).toDouble().coerceIn(0.0, 1.0)
        return 1.0 - 2.0 * ny
    }

    private fun plotRect(): android.graphics.Rect =
        android.graphics.Rect(
            plotLeft,
            plotTop,
            plotLeft + plotWidthPx,
            plotTop + plotHeightPx,
        )

    private fun touchToData(x: Float, y: Float): Pair<Double, Double> {
        val dataX = ChartEngineJni.nativeUnprojectX(chartEngineHandle, touchToNdcX(x))
        val dataY = ChartEngineJni.nativeUnprojectY(chartEngineHandle, touchToNdcY(y))
        return dataX to dataY
    }

    private fun resetTradeLineDrawing() {
        root.removeCallbacks(longPressRunnable)
        ChartEngineJni.nativeSetTradeLineDraft(chartEngineHandle, 0, 0.0, 0.0, 0.0, 0.0)
        isDrawingTradeLine = false
    }

    private fun pollTradeLineDrawCancel() {
        if (chartEngineHandle == 0L) return
        val revision = ChartEngineJni.nativeTradeLineDrawCancelRevision(chartEngineHandle)
        if (revision != lastTradeLineDrawCancelRevision) {
            lastTradeLineDrawCancelRevision = revision
            if (isDrawingTradeLine) {
                resetTradeLineDrawing()
            }
        }
    }

    private fun beginTradeLineDraw(x: Float, y: Float) {
        val (dx, dy) = touchToData(x, y)
        drawStartX = dx
        drawStartY = dy
        isDrawingTradeLine = true
        ChartEngineJni.nativeSetTradeLineDraft(chartEngineHandle, 1, dx, dy, dx, dy)
    }

    private fun updateTradeLineDraw(x: Float, y: Float) {
        pollTradeLineDrawCancel()
        if (!isDrawingTradeLine) return
        val (ex, ey) = touchToData(x, y)
        ChartEngineJni.nativeSetTradeLineDraft(
            chartEngineHandle,
            1,
            drawStartX,
            drawStartY,
            ex,
            ey,
        )
    }

    private fun endTradeLineDraw(x: Float, y: Float) {
        pollTradeLineDrawCancel()
        if (!isDrawingTradeLine) return
        val (ex, ey) = touchToData(x, y)
        isDrawingTradeLine = false
        ChartEngineJni.nativeNotifyTradeLineDrawEnd(
            chartEngineHandle,
            drawStartX,
            drawStartY,
            ex,
            ey,
        )
    }

    private fun cancelTradeLineDraw() {
        resetTradeLineDrawing()
    }
    private fun applyScrubAt(rawX: Float, rawY: Float) {
        val xNDC = touchToNdcX(rawX)
        val xDomain = DoubleArray(2)
        ViewportEngineJni.nativeGetVisibleDomain(viewportHandle, xDomain)
        val span = xDomain[1] - xDomain[0]
        val xData = xDomain[0] + (xNDC + 1.0) * 0.5 * span
        val idx = ChartEngineJni.nativeHitTest(chartEngineHandle, xData)
        if (idx >= 0) {
            ChartEngineJni.nativeSetHover(chartEngineHandle, idx)
            overlay.setScrubFinger(rawX, rawY, true)
        } else {
            ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
            overlay.clearScrubFinger()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouchListener() {
        root.setOnTouchListener { _, event ->
            val masked = event.actionMasked
            when (masked) {
                MotionEvent.ACTION_DOWN -> {
                    pollTradeLineDrawCancel()
                    if (isDrawingTradeLine) {
                        cancelTradeLineDraw()
                    }
                    longPressDownX = event.x
                    longPressDownY = event.y
                    root.removeCallbacks(longPressRunnable)
                    root.postDelayed(longPressRunnable, longPressMs)
                }
                MotionEvent.ACTION_MOVE -> {
                    if (isDrawingTradeLine) {
                        updateTradeLineDraw(event.x, event.y)
                        return@setOnTouchListener true
                    }
                    val moved = kotlin.math.hypot(
                        (event.x - longPressDownX).toDouble(),
                        (event.y - longPressDownY).toDouble(),
                    )
                    if (moved > dp(10f)) {
                        root.removeCallbacks(longPressRunnable)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    root.removeCallbacks(longPressRunnable)
                    if (isDrawingTradeLine) {
                        if (masked == MotionEvent.ACTION_CANCEL) {
                            cancelTradeLineDraw()
                        } else {
                            endTradeLineDraw(event.x, event.y)
                        }
                        return@setOnTouchListener true
                    }
                    overlay.clearScrubFinger()
                    if (isScrubbing) {
                        ChartEngineJni.nativeSetHover(chartEngineHandle, -1)
                        isScrubbing = false
                    }
                }
            }
            scaleDetector.onTouchEvent(event)
            if (!scaleDetector.isInProgress && !isDrawingTradeLine) {
                gestureDetector.onTouchEvent(event)
            }
            true
        }
    }

    /**
     * Only one method is exposed: a one-time handshake that hands the
     * engine pointer to Dart so it can drive everything via direct FFI.
     * NO data, style, or per-frame call goes through this channel.
     */
    private fun registerMethodChannel() {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getEngineHandle" -> result.success(chartEngineHandle)
                else -> result.notImplemented()
            }
        }
    }

    override fun getView(): View = root

    override fun onFlutterViewAttached(flutterView: View) = resumeRendering()
    override fun onFlutterViewDetached() = pauseRendering()

    override fun dispose() {
        if (isDisposed) return
        isDisposed = true
        pauseRendering()
        methodChannel.setMethodCallHandler(null)
        if (chartEngineHandle != 0L) {
            ChartEngineJni.nativeDestroy(chartEngineHandle)
        }
    }

    private fun resumeRendering() {
        if (!isResumed && !isDisposed) {
            glSurfaceView.onResume()
            isResumed = true
        }
    }

    private fun pauseRendering() {
        if (isResumed) {
            glSurfaceView.onPause()
            isResumed = false
        }
    }
}

