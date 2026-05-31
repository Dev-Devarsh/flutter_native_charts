package com.example.flutter_native_charts

/**
 * Phase 5: JNI surface for the native [ViewportEngine] C++ class.
 *
 * Owns nothing on the Kotlin side beyond a `Long` handle returned from
 * [nativeCreate]. Callers are responsible for calling [nativeDestroy] exactly
 * once when the chart view is torn down.
 */
internal object ViewportEngineJni {
    init {
        System.loadLibrary("chart_engine")
    }

    @JvmStatic external fun nativeCreate(): Long

    @JvmStatic external fun nativeDestroy(handle: Long)

    @JvmStatic external fun nativeSetDataBounds(
        handle: Long,
        xMin: Double,
        xMax: Double,
        yMin: Double,
        yMax: Double,
    )

    @JvmStatic external fun nativePan(handle: Long, dxNDC: Double, dyNDC: Double)

    @JvmStatic external fun nativeZoom(
        handle: Long,
        scaleX: Double,
        scaleY: Double,
        focusXNDC: Double,
        focusYNDC: Double,
    )

    @JvmStatic external fun nativeReset(handle: Long)

    @JvmStatic external fun nativeGetProjectionMatrix(handle: Long, outMatrix: FloatArray)

    @JvmStatic external fun nativeRevision(handle: Long): Long

    @JvmStatic external fun nativeGetVisibleDomain(handle: Long, out2: DoubleArray)
    @JvmStatic external fun nativeGetVisibleRange(handle: Long, out2: DoubleArray)
}
