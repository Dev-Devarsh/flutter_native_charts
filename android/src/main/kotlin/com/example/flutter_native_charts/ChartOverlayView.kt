package com.example.flutter_native_charts

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextPaint
import android.util.AttributeSet
import android.view.Choreographer
import android.view.View
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * Native overlay that draws axis tick labels, the tooltip, and the legend
 * directly onto a transparent View positioned above the GL surface.
 *
 * ALL sources of truth live in the C++ engine:
 *  - tick positions come from `nativeGetXTicks` / `nativeGetYTicks`,
 *  - the hovered candle's OHLCV from `nativeGetCandle(hover)`,
 *  - data <-> NDC projection from `nativeProjectX` / `nativeProjectY`,
 *  - styling (colors / toggles / decimals / label) from `nativeGetStyle*`.
 *
 * The overlay listens via [Choreographer] so it only re-lays-out when the
 * engine's `viewport_revision`, `style_revision`, `generation`, or `hover`
 * changes. No MethodChannel hop, no Flutter main-thread involvement.
 */
@SuppressLint("ViewConstructor")
internal class ChartOverlayView(
    context: Context,
    private val chartEngineHandle: Long,
    private val viewportHandle: Long,
) : View(context), Choreographer.FrameCallback {

    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
    }
    private val axisTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = sp(11f)
        color = 0xFF8D93A2.toInt()
    }
    private val tooltipBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0xEE13171F.toInt()
    }
    private val tooltipBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        color = 0x66FFFFFF.toInt()
    }
    private val tooltipTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = sp(12f)
        color = Color.WHITE
    }
    private val legendBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0xCC0B0E14.toInt()
    }
    private val legendTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = sp(11f)
        color = 0xFF7CFFB2.toInt()
    }
    private val markerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0xFFFFD466.toInt()
    }

    private val xTicks = DoubleArray(32)
    private val yTicks = DoubleArray(32)
    private val xTickNdc = DoubleArray(32)
    private val yTickNdc = DoubleArray(32)
    private var xTickCount = 0
    private var yTickCount = 0

    private val candle6 = DoubleArray(6)
    private var hoverIndex = -1
    private var hoverHasData = false

    private var lastViewportRevision = -1L
    private var lastStyleRevision = -1L
    private var lastGeneration = -1
    private var lastHover = -2

    /** Left, top, right, bottom margins (px) reserving space for legend + axis labels; mirrors iOS. */
    private var plotMarginLeft = 0
    private var plotMarginTop = 0
    private var plotMarginRight = 0
    private var plotMarginBottom = 0

    // Scratch buffers used to pull the engine's current style each time
    // style_revision changes. Sized to match the JNI nativeGetStyle* layout.
    private val styleFloats = FloatArray(54)
    private val styleInts = IntArray(14)

    /** When true, tooltip + marker anchor to finger while x-pan is locked (scrub). */
    private var scrubFingerActive = false
    private var scrubFingerX = 0f
    private var scrubFingerY = 0f

    // Style state mirrored from the engine.
    private var showGrid = true
    private var showXAxis = true
    private var showYAxis = true
    private var showCrosshair = true
    private var showTooltip = true
    private var showLegend = true
    private var yDecimals = 2
    private var xIsTimestampMs = true
    private var seriesLabel = "CANDLE"

    private val dateFmt = SimpleDateFormat("HH:mm:ss", Locale.US)
    private val df = StringBuilder()

    private var scheduled = false

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
        isClickable = false
        isFocusable = false
    }

    /** Called by [ChartPlatformView] so axis labels align with the inset GL surface. */
    fun setScrubFinger(x: Float, y: Float, active: Boolean) {
        scrubFingerActive = active
        scrubFingerX = x
        scrubFingerY = y
        invalidate()
    }

    fun clearScrubFinger() {
        setScrubFinger(0f, 0f, false)
    }

    fun setPlotMargins(left: Int, top: Int, right: Int, bottom: Int) {
        if (left == plotMarginLeft && top == plotMarginTop &&
            right == plotMarginRight && bottom == plotMarginBottom
        ) {
            return
        }
        plotMarginLeft = left
        plotMarginTop = top
        plotMarginRight = right
        plotMarginBottom = bottom
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (chartEngineHandle != 0L) {
            pullStyleFromEngine()
        }
        scheduleFrame()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Choreographer.getInstance().removeFrameCallback(this)
        scheduled = false
    }

    private fun scheduleFrame() {
        if (!scheduled && isAttachedToWindow) {
            Choreographer.getInstance().postFrameCallback(this)
            scheduled = true
        }
    }

    override fun doFrame(frameTimeNanos: Long) {
        scheduled = false
        if (chartEngineHandle == 0L) {
            scheduleFrame()
            return
        }
        val gen = ChartEngineJni.nativeGeneration(chartEngineHandle)
        val rev = ChartEngineJni.nativeViewportRevision(chartEngineHandle)
        val hover = ChartEngineJni.nativeGetHover(chartEngineHandle)
        val styleRev = ChartEngineJni.nativeStyleRevision(chartEngineHandle)
        if (styleRev != lastStyleRevision) {
            lastStyleRevision = styleRev
            pullStyleFromEngine()
            refreshTicks()
            invalidate()
        }
        if (gen != lastGeneration || rev != lastViewportRevision || hover != lastHover) {
            lastGeneration = gen
            lastViewportRevision = rev
            lastHover = hover
            hoverIndex = hover
            if (hover >= 0) {
                hoverHasData =
                    ChartEngineJni.nativeGetCandle(chartEngineHandle, hover, candle6) == 1
            } else {
                hoverHasData = false
            }
            refreshTicks()
            invalidate()
        }
        scheduleFrame()
    }

    /**
     * Pulls the engine's current ChartStyle and mirrors the fields we render
     * here. Called whenever `style_revision` changes — replaces the
     * `applyStyleSnapshot` MethodChannel handler.
     */
    private fun pullStyleFromEngine() {
        ChartEngineJni.nativeGetStyleFloats(chartEngineHandle, styleFloats)
        ChartEngineJni.nativeGetStyleInts(chartEngineHandle, styleInts)
        seriesLabel = ChartEngineJni.nativeGetSeriesLabel(chartEngineHandle)
            .takeIf { it.isNotEmpty() } ?: "SERIES"

        // ints layout: [grid, xAxis, yAxis, crosshair, tooltip, legend,
        //               xTicks, yTicks, yDecimals, xIsTimestampMs,
        //               allowPanX, allowPanY, allowZoomX, allowZoomY]
        showGrid = styleInts[0] != 0
        showXAxis = styleInts[1] != 0
        showYAxis = styleInts[2] != 0
        showCrosshair = styleInts[3] != 0
        showTooltip = styleInts[4] != 0
        showLegend = styleInts[5] != 0
        yDecimals = styleInts[8]
        xIsTimestampMs = styleInts[9] != 0

        // floats layout: 12 RGBA colors followed by 6 geometry floats.
        // We only render axis text, legend text, tooltip, and the marker
        // on the overlay; the rest go to the GPU renderer.
        gridPaint.color = rgbaToArgb(styleFloats, offset = 4)
        axisTextPaint.color = rgbaToArgb(styleFloats, offset = 8)
        markerPaint.color = rgbaToArgb(styleFloats, offset = 32)         // crosshair
        tooltipBgPaint.color = rgbaToArgb(styleFloats, offset = 36)
        tooltipTextPaint.color = rgbaToArgb(styleFloats, offset = 40)
        legendTextPaint.color = rgbaToArgb(styleFloats, offset = 44)
    }

    private fun refreshTicks() {
        xTickCount = ChartEngineJni.nativeGetXTicks(chartEngineHandle, xTicks, xTicks.size)
            .coerceAtMost(xTicks.size)
        yTickCount = ChartEngineJni.nativeGetYTicks(chartEngineHandle, yTicks, yTicks.size)
            .coerceAtMost(yTicks.size)
        if (xTickCount > 0) {
            ChartEngineJni.nativeProjectX(chartEngineHandle, xTicks, xTickCount, xTickNdc)
        }
        if (yTickCount > 0) {
            ChartEngineJni.nativeProjectY(chartEngineHandle, yTicks, yTickCount, yTickNdc)
        }
    }

    private fun ndcOk(v: Double): Boolean = v >= -1.0 - 1e-5 && v <= 1.0 + 1e-5

    override fun onDraw(canvas: Canvas) {
        if (chartEngineHandle == 0L) return
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val pl = plotMarginLeft.toFloat()
        val pt = plotMarginTop.toFloat()
        val pr = (width - plotMarginRight).toFloat()
        val pb = (height - plotMarginBottom).toFloat()
        val plotW = (pr - pl).coerceAtLeast(1f)
        val plotH = (pb - pt).coerceAtLeast(1f)
        val useMargins = plotMarginLeft + plotMarginRight + 8 < width &&
            plotMarginTop + plotMarginBottom + 8 < height

        val plotLeft = if (useMargins) pl else 0f
        val plotTop = if (useMargins) pt else 0f
        val plotRight = if (useMargins) pr else w
        val plotBottom = if (useMargins) pb else h

        if ((showXAxis || showYAxis) && useMargins) {
            if (showXAxis) {
                canvas.drawLine(plotLeft, plotBottom, plotRight, plotBottom, gridPaint)
            }
            if (showYAxis) {
                canvas.drawLine(plotLeft, plotTop, plotLeft, plotBottom, gridPaint)
            }
        }

        if (showXAxis && xTickCount > 0) {
            val fmX = axisTextPaint.fontMetrics
            val gutterPad = dp(4f)
            // Baseline in bottom margin so glyphs sit entirely below plotBottom (not atop series).
            var xBaseline =
                plotBottom + gutterPad - fmX.ascent
            xBaseline = min(xBaseline, h - gutterPad - fmX.descent)
            var lastLabelRight = Float.NEGATIVE_INFINITY
            val minXGapPx = dp(8f)
            for (i in 0 until xTickCount) {
                val ndcX = xTickNdc[i]
                if (!ndcOk(ndcX)) continue
                val px = plotLeft + ((ndcX + 1.0) * 0.5 * plotW).toFloat()
                val label = formatX(xTicks[i])
                val tw = axisTextPaint.measureText(label)
                val tx =
                    max(gutterPad, min(w - tw - gutterPad, px - tw / 2f))
                if (tx < lastLabelRight + minXGapPx) continue
                canvas.drawText(label, tx, xBaseline, axisTextPaint)
                lastLabelRight = tx + tw
            }
        }
        if (showYAxis && yTickCount > 0) {
            val gutterPad = dp(4f)
            val fm = axisTextPaint.fontMetrics
            val minYGapPx = dp(9f)

            data class YRow(val py: Float, val baselineY: Float, val label: String)

            val yRows = ArrayList<YRow>(yTickCount)
            for (i in 0 until yTickCount) {
                val ndcY = yTickNdc[i]
                if (!ndcOk(ndcY)) continue
                val py = plotTop + ((1.0 - (ndcY + 1.0) * 0.5) * plotH).toFloat()
                val baselineY = py - (fm.ascent + fm.descent) / 2f
                yRows.add(YRow(py, baselineY, formatY(yTicks[i])))
            }
            yRows.sortBy { it.py }
            var lastInkBottom = Float.NEGATIVE_INFINITY
            for (r in yRows) {
                val tw = axisTextPaint.measureText(r.label)
                val tx = (plotLeft - gutterPad - tw).coerceAtLeast(gutterPad)
                val textTop = r.baselineY + fm.top
                if (lastInkBottom != Float.NEGATIVE_INFINITY && textTop < lastInkBottom + minYGapPx) {
                    continue
                }
                canvas.drawText(r.label, tx, r.baselineY, axisTextPaint)
                lastInkBottom = r.baselineY + fm.bottom
            }
        }

        if (showLegend) {
            val text = "$seriesLabel  ·  ${ChartEngineJni.nativeCandleCount(chartEngineHandle)}"
            val tw = legendTextPaint.measureText(text)
            val padX = dp(10f)
            val padY = dp(6f)
            val rect = RectF(dp(10f), dp(10f), dp(10f) + tw + padX * 2f, dp(10f) + sp(11f) + padY * 2f)
            canvas.drawRoundRect(rect, dp(6f), dp(6f), legendBgPaint)
            canvas.drawText(text, rect.left + padX, rect.bottom - padY, legendTextPaint)
        }

        if (showTooltip && hoverHasData) {
            val ts = candle6[0]
            val o = candle6[1]
            val hi = candle6[2]
            val lo = candle6[3]
            val cl = candle6[4]
            val vol = candle6[5]
            val ndc = DoubleArray(1)
            ChartEngineJni.nativeProjectX(chartEngineHandle, doubleArrayOf(ts), 1, ndc)
            val pl = plotMarginLeft.toFloat()
            val pt = plotMarginTop.toFloat()
            val pr = (width - plotMarginRight).toFloat()
            val pb = (height - plotMarginBottom).toFloat()
            val plotW = (pr - pl).coerceAtLeast(1f)
            val plotH = (pb - pt).coerceAtLeast(1f)
            val snapMarkerX = pl + ((ndc[0] + 1.0) * 0.5 * plotW).toFloat()
            val ndcY = DoubleArray(1)
            ChartEngineJni.nativeProjectY(chartEngineHandle, doubleArrayOf(cl), 1, ndcY)
            val snapMarkerY = pt + ((1.0 - (ndcY[0] + 1.0) * 0.5) * plotH).toFloat()

            val markerX: Float
            val markerY: Float
            if (scrubFingerActive) {
                markerX = scrubFingerX.coerceIn(pl, pr)
                markerY = scrubFingerY.coerceIn(pt, pb)
            } else {
                markerX = snapMarkerX
                markerY = snapMarkerY
            }

            if (markerX in pl..pr && markerY in pt..pb) {
                canvas.drawCircle(markerX, markerY, dp(4f), markerPaint)
            }

            val lines = arrayOf(
                "TIME  ${formatX(ts)}",
                "O     ${formatY(o)}",
                "H     ${formatY(hi)}",
                "L     ${formatY(lo)}",
                "C     ${formatY(cl)}",
                "VOL   ${formatVol(vol)}",
            )
            var maxW = 0f
            for (s in lines) {
                val tw = tooltipTextPaint.measureText(s)
                if (tw > maxW) maxW = tw
            }
            val pad = dp(10f)
            val lineH = sp(15f)
            val boxW = maxW + pad * 2f
            val boxH = lineH * lines.size + pad * 2f
            val placeOnLeft = markerX > w * 0.5f
            val boxX = if (placeOnLeft) {
                (markerX - dp(16f) - boxW).coerceAtLeast(dp(6f))
            } else {
                (markerX + dp(16f)).coerceAtMost(w - boxW - dp(6f))
            }
            // Pin tooltip to plot top; only X tracks the bar (marker still shows true Y on the series).
            val topAnchor = pt + dp(6f)
            val boxY = topAnchor.coerceIn(dp(6f), h - boxH - dp(6f))
            val box = RectF(boxX, boxY, boxX + boxW, boxY + boxH)
            canvas.drawRoundRect(box, dp(8f), dp(8f), tooltipBgPaint)
            canvas.drawRoundRect(box, dp(8f), dp(8f), tooltipBorderPaint)
            var y = box.top + pad + sp(12f)
            for (s in lines) {
                canvas.drawText(s, box.left + pad, y, tooltipTextPaint)
                y += lineH
            }
        }
    }

    private fun formatX(v: Double): String {
        if (xIsTimestampMs) {
            return dateFmt.format(Date(v.toLong()))
        }
        return formatY(v)
    }

    private fun formatY(v: Double): String {
        df.setLength(0)
        if (yDecimals <= 0) {
            df.append(v.toLong().toString())
        } else {
            val multiplier = pow10(yDecimals)
            val rounded = kotlin.math.round(v * multiplier) / multiplier
            df.append(String.format(Locale.US, "%.${yDecimals}f", rounded))
        }
        return df.toString()
    }

    private fun formatVol(v: Double): String {
        if (v >= 1_000_000.0) return String.format(Locale.US, "%.2fM", v / 1_000_000.0)
        if (v >= 1_000.0) return String.format(Locale.US, "%.1fK", v / 1_000.0)
        return v.toLong().toString()
    }

    private fun pow10(n: Int): Double {
        var v = 1.0
        repeat(n) { v *= 10.0 }
        return v
    }

    private fun dp(v: Float): Float = v * resources.displayMetrics.density
    private fun sp(v: Float): Float = v * resources.displayMetrics.scaledDensity

    /** Pack RGBA floats (each 0..1) starting at [offset] into an ARGB int. */
    private fun rgbaToArgb(src: FloatArray, offset: Int): Int {
        val r = (src[offset] * 255f).toInt().coerceIn(0, 255)
        val g = (src[offset + 1] * 255f).toInt().coerceIn(0, 255)
        val b = (src[offset + 2] * 255f).toInt().coerceIn(0, 255)
        val a = (src[offset + 3] * 255f).toInt().coerceIn(0, 255)
        return (a shl 24) or (r shl 16) or (g shl 8) or b
    }

    @Suppress("unused")
    constructor(context: Context) : this(context, 0L, 0L)

    @Suppress("unused")
    constructor(context: Context, attrs: AttributeSet?) : this(context, 0L, 0L)
}
