package com.example.flutter_native_charts

/**
 * JNI surface for the native chart engine.
 *
 * Owns nothing on the Kotlin side beyond a `Long` handle. Caller must call
 * [nativeDestroy] exactly once when finished with an engine they created.
 *
 * The viewport pointer obtained from [nativeGetViewport] is borrowed; it
 * is freed when the engine is destroyed.
 */
internal object ChartEngineJni {
    init {
        System.loadLibrary("chart_engine")
    }

    // -- lifecycle --
    @JvmStatic external fun nativeCreate(): Long
    @JvmStatic external fun nativeDestroy(handle: Long)

    // -- viewport / generation --
    @JvmStatic external fun nativeGetViewport(handle: Long): Long
    @JvmStatic external fun nativeViewportRevision(handle: Long): Long
    @JvmStatic external fun nativeGeneration(handle: Long): Int

    @JvmStatic external fun nativeRebuildForViewport(handle: Long)

    // -- series --
    @JvmStatic external fun nativeSetSeriesType(handle: Long, type: Int)
    @JvmStatic external fun nativeGetSeriesType(handle: Long): Int

    @JvmStatic external fun nativeHasVolumePane(handle: Long): Int

    // -- passes --
    @JvmStatic external fun nativePassCount(handle: Long): Int
    @JvmStatic external fun nativeReadPass(
        handle: Long,
        pass: Int,
        outPrimitive: IntArray,
        outVertices: FloatArray?,
    ): Int

    @JvmStatic external fun nativePassZone(handle: Long, pass: Int): Int

    @JvmStatic external fun nativeGetPriceProjectionMatrix(handle: Long, out16: FloatArray)

    @JvmStatic external fun nativeGetVolumeProjectionMatrix(handle: Long, out16: FloatArray)

    // -- data --
    /**
     * Zero-copy candle ingestion. `data.size` must be 6 * count and the layout
     * must be tightly packed [t,o,h,l,c,v] per candle. Replaces existing data.
     */
    @JvmStatic external fun nativePushCandlesRaw(handle: Long, data: DoubleArray, count: Int)
    @JvmStatic external fun nativeAppendCandlesRaw(handle: Long, data: DoubleArray, count: Int)
    @JvmStatic external fun nativeCandleCount(handle: Long): Int

    /** Writes [t,o,h,l,c,v] into [out6]; returns 1 on success, 0 if index OOB. */
    @JvmStatic external fun nativeGetCandle(handle: Long, index: Int, out6: DoubleArray): Int

    /** Writes [xMin,xMax,yMin,yMax]. */
    @JvmStatic external fun nativeGetDataBounds(handle: Long, out4: DoubleArray)

    // -- hit-test + hover --
    @JvmStatic external fun nativeHitTest(handle: Long, xData: Double): Int
    @JvmStatic external fun nativeSetHover(handle: Long, index: Int)
    @JvmStatic external fun nativeGetHover(handle: Long): Int

    // -- ticks --
    /** Returns total tick count; copies up to maxCount into out. */
    @JvmStatic external fun nativeGetXTicks(handle: Long, out: DoubleArray?, maxCount: Int): Int
    @JvmStatic external fun nativeGetYTicks(handle: Long, out: DoubleArray?, maxCount: Int): Int

    // -- projection --
    @JvmStatic external fun nativeProjectX(
        handle: Long, inX: DoubleArray, count: Int, outNdc: DoubleArray,
    )
    @JvmStatic external fun nativeProjectY(
        handle: Long, inY: DoubleArray, count: Int, outNdc: DoubleArray,
    )

    @JvmStatic external fun nativeUnprojectY(handle: Long, yNdc: Double): Double

    @JvmStatic external fun nativeUnprojectX(handle: Long, xNdc: Double): Double

    @JvmStatic external fun nativeSetTradeLineDraft(
        handle: Long,
        active: Int,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double,
    )

    @JvmStatic external fun nativeNotifyTradeLineDrawEnd(
        handle: Long,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double,
    )

    @JvmStatic external fun nativeTradeLineDrawCancelRevision(handle: Long): Long
    // -- style --
    @JvmStatic external fun nativeSetStyle(handle: Long, floats: FloatArray, ints: IntArray)

    /** Monotonic counter; bumps on every successful nativeSetStyle. */
    @JvmStatic external fun nativeStyleRevision(handle: Long): Long

    /**
     * Fills [out] with 54 floats describing the engine's *current* style.
     * Layout matches [nativeSetStyle]:
     *   [0..47]   = 12 RGBA colors (48 floats)
     *   [48]      = candle_body_width_fraction
     *   [49]      = line_width_px
     *   [50]      = wick_width_px
     *   [51]      = crosshair_width_px
     *   [52]      = x_pad_fraction
     *   [53]      = y_pad_fraction
     */
    @JvmStatic external fun nativeGetStyleFloats(handle: Long, out: FloatArray)

    /**
     * Fills [out] with 14 ints: show flags [0–5], tick counts / format [6–9],
     * interaction [10]=allowPanX [11]=allowPanY [12]=allowZoomX [13]=allowZoomY (1=yes).
     */
    @JvmStatic external fun nativeGetStyleInts(handle: Long, out: IntArray)

    /** Returns the engine's current series label (UTF-8 from ChartStyle). */
    @JvmStatic external fun nativeGetSeriesLabel(handle: Long): String
}
