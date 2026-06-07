#include <jni.h>

#include <cstring>

#include "chart_engine_ffi.h"
#include "viewport_engine.h"

#define VIEWPORT_JNI_METHOD(NAME) \
  Java_com_example_flutter_1native_1charts_ViewportEngineJni_##NAME

#define CHART_JNI_METHOD(NAME) \
  Java_com_example_flutter_1native_1charts_ChartEngineJni_##NAME

extern "C" {

// =========================================================================
// ViewportEngineJni
// =========================================================================

JNIEXPORT jlong JNICALL
VIEWPORT_JNI_METHOD(nativeCreate)(JNIEnv*, jclass) {
  return reinterpret_cast<jlong>(new ViewportEngine());
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeDestroy)(JNIEnv*, jclass, jlong handle) {
  if (handle == 0) return;
  delete reinterpret_cast<ViewportEngine*>(handle);
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeSetDataBounds)(JNIEnv*, jclass, jlong handle,
                                         jdouble xMin, jdouble xMax,
                                         jdouble yMin, jdouble yMax) {
  if (handle == 0) return;
  reinterpret_cast<ViewportEngine*>(handle)->setDataBounds(xMin, xMax, yMin, yMax);
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativePan)(JNIEnv*, jclass, jlong handle, jdouble dxNDC, jdouble dyNDC) {
  if (handle == 0) return;
  reinterpret_cast<ViewportEngine*>(handle)->panNDC(dxNDC, dyNDC);
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeZoom)(JNIEnv*, jclass, jlong handle,
                                jdouble sx, jdouble sy,
                                jdouble fx, jdouble fy) {
  if (handle == 0) return;
  reinterpret_cast<ViewportEngine*>(handle)->zoomNDC(sx, sy, fx, fy);
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeReset)(JNIEnv*, jclass, jlong handle) {
  if (handle == 0) return;
  reinterpret_cast<ViewportEngine*>(handle)->reset();
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeGetProjectionMatrix)(JNIEnv* env, jclass, jlong handle,
                                               jfloatArray out16) {
  if (handle == 0 || out16 == nullptr) return;
  if (env->GetArrayLength(out16) < 16) return;
  float buf[16];
  reinterpret_cast<ViewportEngine*>(handle)->getProjectionMatrix(buf);
  env->SetFloatArrayRegion(out16, 0, 16, buf);
}

JNIEXPORT jlong JNICALL
VIEWPORT_JNI_METHOD(nativeRevision)(JNIEnv*, jclass, jlong handle) {
  if (handle == 0) return 0;
  return reinterpret_cast<ViewportEngine*>(handle)->revision();
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeGetVisibleDomain)(JNIEnv* env, jclass, jlong handle,
                                            jdoubleArray out2) {
  if (handle == 0 || out2 == nullptr) return;
  if (env->GetArrayLength(out2) < 2) return;
  double a, b;
  reinterpret_cast<ViewportEngine*>(handle)->getVisibleDomain(&a, &b);
  jdouble tmp[2] = {a, b};
  env->SetDoubleArrayRegion(out2, 0, 2, tmp);
}

JNIEXPORT void JNICALL
VIEWPORT_JNI_METHOD(nativeGetVisibleRange)(JNIEnv* env, jclass, jlong handle,
                                           jdoubleArray out2) {
  if (handle == 0 || out2 == nullptr) return;
  if (env->GetArrayLength(out2) < 2) return;
  double a, b;
  reinterpret_cast<ViewportEngine*>(handle)->getVisibleRange(&a, &b);
  jdouble tmp[2] = {a, b};
  env->SetDoubleArrayRegion(out2, 0, 2, tmp);
}

// =========================================================================
// ChartEngineJni
// =========================================================================

JNIEXPORT jlong JNICALL
CHART_JNI_METHOD(nativeCreate)(JNIEnv*, jclass) {
  return reinterpret_cast<jlong>(create_chart_engine());
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeDestroy)(JNIEnv*, jclass, jlong handle) {
  destroy_chart_engine(reinterpret_cast<void*>(handle));
}

JNIEXPORT jlong JNICALL
CHART_JNI_METHOD(nativeGetViewport)(JNIEnv*, jclass, jlong handle) {
  return reinterpret_cast<jlong>(chart_engine_get_viewport(reinterpret_cast<void*>(handle)));
}

JNIEXPORT jlong JNICALL
CHART_JNI_METHOD(nativeViewportRevision)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_viewport_revision(reinterpret_cast<void*>(handle));
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeSetSeriesType)(JNIEnv*, jclass, jlong handle, jint type) {
  chart_engine_set_series_type(reinterpret_cast<void*>(handle), type);
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeGetSeriesType)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_get_series_type(reinterpret_cast<void*>(handle));
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeGeneration)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_generation(reinterpret_cast<void*>(handle));
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeRebuildForViewport)(JNIEnv*, jclass, jlong handle) {
  if (handle == 0) return;
  chart_engine_rebuild_for_viewport(reinterpret_cast<void*>(handle));
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativePassCount)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_pass_count(reinterpret_cast<void*>(handle));
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeReadPass)(JNIEnv* env, jclass, jlong handle, jint pass,
                                 jintArray outPrimitive,
                                 jfloatArray outVertices) {
  int primitive = 0;
  float* buffer = nullptr;
  jsize capacity = 0;
  if (outVertices != nullptr) {
    capacity = env->GetArrayLength(outVertices);
    if (capacity > 0) {
      buffer = env->GetFloatArrayElements(outVertices, nullptr);
    }
  }

  const int vertex_count = chart_engine_read_pass(
      reinterpret_cast<void*>(handle),
      pass,
      &primitive,
      buffer,
      static_cast<int>(capacity));

  if (outPrimitive != nullptr && env->GetArrayLength(outPrimitive) >= 1) {
    env->SetIntArrayRegion(outPrimitive, 0, 1, &primitive);
  }
  if (buffer != nullptr) {
    env->ReleaseFloatArrayElements(outVertices, buffer, 0);
  }
  return vertex_count;
}

// -- Data --

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativePushCandlesRaw)(JNIEnv* env, jclass, jlong handle,
                                       jdoubleArray data, jint count) {
  if (handle == 0 || data == nullptr || count <= 0) return;
  jsize len = env->GetArrayLength(data);
  if (len < count * 6) return;
  jdouble* ptr = env->GetDoubleArrayElements(data, nullptr);
  push_candles_raw(reinterpret_cast<void*>(handle), ptr, count);
  env->ReleaseDoubleArrayElements(data, ptr, JNI_ABORT);
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeAppendCandlesRaw)(JNIEnv* env, jclass, jlong handle,
                                         jdoubleArray data, jint count) {
  if (handle == 0 || data == nullptr || count <= 0) return;
  jsize len = env->GetArrayLength(data);
  if (len < count * 6) return;
  jdouble* ptr = env->GetDoubleArrayElements(data, nullptr);
  append_candles_raw(reinterpret_cast<void*>(handle), ptr, count);
  env->ReleaseDoubleArrayElements(data, ptr, JNI_ABORT);
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeCandleCount)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_candle_count(reinterpret_cast<void*>(handle));
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeGetCandle)(JNIEnv* env, jclass, jlong handle, jint index,
                                  jdoubleArray out6) {
  if (handle == 0 || out6 == nullptr) return 0;
  if (env->GetArrayLength(out6) < 6) return 0;
  NativeCandle c{};
  const int ok = chart_engine_get_candle(reinterpret_cast<void*>(handle), index, &c);
  if (ok) {
    jdouble tmp[6] = {c.timestamp, c.open, c.high, c.low, c.close, c.volume};
    env->SetDoubleArrayRegion(out6, 0, 6, tmp);
  }
  return ok;
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeGetDataBounds)(JNIEnv* env, jclass, jlong handle,
                                       jdoubleArray out4) {
  if (handle == 0 || out4 == nullptr) return;
  if (env->GetArrayLength(out4) < 4) return;
  double xMin, xMax, yMin, yMax;
  chart_engine_get_data_bounds(reinterpret_cast<void*>(handle), &xMin, &xMax, &yMin, &yMax);
  jdouble tmp[4] = {xMin, xMax, yMin, yMax};
  env->SetDoubleArrayRegion(out4, 0, 4, tmp);
}

// -- Hit-test + hover --

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeHitTest)(JNIEnv*, jclass, jlong handle, jdouble xData) {
  return chart_engine_hit_test(reinterpret_cast<void*>(handle), xData);
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeSetHover)(JNIEnv*, jclass, jlong handle, jint index) {
  chart_engine_set_hover(reinterpret_cast<void*>(handle), index);
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeGetHover)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_get_hover(reinterpret_cast<void*>(handle));
}

// -- Ticks --

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeGetXTicks)(JNIEnv* env, jclass, jlong handle,
                                  jdoubleArray out, jint maxCount) {
  if (handle == 0) return 0;
  jdouble* ptr = nullptr;
  if (out != nullptr && maxCount > 0) {
    ptr = env->GetDoubleArrayElements(out, nullptr);
  }
  const int total = chart_engine_get_x_ticks(
      reinterpret_cast<void*>(handle),
      ptr,
      maxCount);
  if (ptr != nullptr) {
    env->ReleaseDoubleArrayElements(out, ptr, 0);
  }
  return total;
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeGetYTicks)(JNIEnv* env, jclass, jlong handle,
                                  jdoubleArray out, jint maxCount) {
  if (handle == 0) return 0;
  jdouble* ptr = nullptr;
  if (out != nullptr && maxCount > 0) {
    ptr = env->GetDoubleArrayElements(out, nullptr);
  }
  const int total = chart_engine_get_y_ticks(
      reinterpret_cast<void*>(handle),
      ptr,
      maxCount);
  if (ptr != nullptr) {
    env->ReleaseDoubleArrayElements(out, ptr, 0);
  }
  return total;
}

// -- Projection --

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeProjectX)(JNIEnv* env, jclass, jlong handle,
                                 jdoubleArray in_x, jint count,
                                 jdoubleArray out_ndc) {
  if (handle == 0 || in_x == nullptr || out_ndc == nullptr || count <= 0) return;
  if (env->GetArrayLength(in_x) < count || env->GetArrayLength(out_ndc) < count) return;
  jdouble* in_ptr = env->GetDoubleArrayElements(in_x, nullptr);
  jdouble* out_ptr = env->GetDoubleArrayElements(out_ndc, nullptr);
  chart_engine_project_x(reinterpret_cast<void*>(handle), in_ptr, count, out_ptr);
  env->ReleaseDoubleArrayElements(in_x, in_ptr, JNI_ABORT);
  env->ReleaseDoubleArrayElements(out_ndc, out_ptr, 0);
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeProjectY)(JNIEnv* env, jclass, jlong handle,
                                 jdoubleArray in_y, jint count,
                                 jdoubleArray out_ndc) {
  if (handle == 0 || in_y == nullptr || out_ndc == nullptr || count <= 0) return;
  if (env->GetArrayLength(in_y) < count || env->GetArrayLength(out_ndc) < count) return;
  jdouble* in_ptr = env->GetDoubleArrayElements(in_y, nullptr);
  jdouble* out_ptr = env->GetDoubleArrayElements(out_ndc, nullptr);
  chart_engine_project_y(reinterpret_cast<void*>(handle), in_ptr, count, out_ptr);
  env->ReleaseDoubleArrayElements(in_y, in_ptr, JNI_ABORT);
  env->ReleaseDoubleArrayElements(out_ndc, out_ptr, 0);
}

JNIEXPORT jdouble JNICALL
CHART_JNI_METHOD(nativeUnprojectY)(JNIEnv*, jclass, jlong handle, jdouble y_ndc) {
  if (handle == 0) return 0.0;
  return chart_engine_unproject_y(reinterpret_cast<void*>(handle), y_ndc);
}

JNIEXPORT jdouble JNICALL
CHART_JNI_METHOD(nativeUnprojectX)(JNIEnv*, jclass, jlong handle, jdouble x_ndc) {
  if (handle == 0) return 0.0;
  return chart_engine_unproject_x(reinterpret_cast<void*>(handle), x_ndc);
}

// -- Trade lines --

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeSetTradeLineDraft)(JNIEnv*, jclass, jlong handle,
                                           jint active,
                                           jdouble x1, jdouble y1,
                                           jdouble x2, jdouble y2) {
  if (handle == 0) return;
  chart_engine_set_trade_line_draft(reinterpret_cast<void*>(handle),
                                    active, x1, y1, x2, y2);
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeNotifyTradeLineDrawEnd)(JNIEnv*, jclass, jlong handle,
                                                jdouble x1, jdouble y1,
                                                jdouble x2, jdouble y2) {
  if (handle == 0) return;
  chart_engine_notify_trade_line_draw_end(reinterpret_cast<void*>(handle),
                                          x1, y1, x2, y2);
}

JNIEXPORT jlong JNICALL
CHART_JNI_METHOD(nativeTradeLineDrawCancelRevision)(JNIEnv*, jclass, jlong handle) {
  if (handle == 0) return 0;
  return chart_engine_trade_line_draw_cancel_revision(reinterpret_cast<void*>(handle));
}

// -- Style --

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeSetStyle)(JNIEnv* env, jclass, jlong handle,
                                 jfloatArray floats, jintArray ints) {
  if (handle == 0 || floats == nullptr || ints == nullptr) return;
  ChartStyle style{};
  // Default values, then overlay.
  chart_engine_get_default_style(&style);

  const jsize floatCount = env->GetArrayLength(floats);
  const jsize intCount = env->GetArrayLength(ints);
  // Float layout (matches Dart):
  // [0..47]   = 12 RGBA colors (48 floats)
  // [48]      = candle_body_width_fraction
  // [49]      = line_width_px
  // [50]      = wick_width_px
  // [51]      = crosshair_width_px
  // [52]      = x_pad_fraction
  // [53]      = y_pad_fraction
  if (floatCount >= 54) {
    jfloat* fp = env->GetFloatArrayElements(floats, nullptr);
    std::memcpy(style.bg_color, fp + 0, sizeof(float) * 4);
    std::memcpy(style.grid_color, fp + 4, sizeof(float) * 4);
    std::memcpy(style.axis_text_color, fp + 8, sizeof(float) * 4);
    std::memcpy(style.up_color, fp + 12, sizeof(float) * 4);
    std::memcpy(style.down_color, fp + 16, sizeof(float) * 4);
    std::memcpy(style.line_color, fp + 20, sizeof(float) * 4);
    std::memcpy(style.area_top_color, fp + 24, sizeof(float) * 4);
    std::memcpy(style.area_bottom_color, fp + 28, sizeof(float) * 4);
    std::memcpy(style.crosshair_color, fp + 32, sizeof(float) * 4);
    std::memcpy(style.tooltip_bg_color, fp + 36, sizeof(float) * 4);
    std::memcpy(style.tooltip_text_color, fp + 40, sizeof(float) * 4);
    std::memcpy(style.legend_text_color, fp + 44, sizeof(float) * 4);
    style.candle_body_width_fraction = fp[48];
    style.line_width_px = fp[49];
    style.wick_width_px = fp[50];
    style.crosshair_width_px = fp[51];
    style.x_pad_fraction = fp[52];
    style.y_pad_fraction = fp[53];
    if (floatCount >= 58) {
      std::memcpy(style.current_price_line_color, fp + 54, sizeof(float) * 4);
    }
    env->ReleaseFloatArrayElements(floats, fp, JNI_ABORT);
  }
  // Int layout (matches Dart):
  // [0] show_grid, [1] show_x_axis, [2] show_y_axis,
  // [3] show_crosshair, [4] show_tooltip, [5] show_legend,
  // [6] approx_x_ticks, [7] approx_y_ticks,
  // [8] y_decimals, [9] x_is_timestamp_ms,
  // [10..13] optional: allow_pan_x, allow_pan_y, allow_zoom_x, allow_zoom_y (1 = allow)
  if (intCount >= 10) {
    jint* ip = env->GetIntArrayElements(ints, nullptr);
    style.show_grid = ip[0];
    style.show_x_axis = ip[1];
    style.show_y_axis = ip[2];
    style.show_crosshair = ip[3];
    style.show_tooltip = ip[4];
    style.show_legend = ip[5];
    style.approx_x_ticks = ip[6];
    style.approx_y_ticks = ip[7];
    style.y_decimals = ip[8];
    style.x_is_timestamp_ms = ip[9];
    if (intCount >= 14) {
      style.allow_pan_x = ip[10];
      style.allow_pan_y = ip[11];
      style.allow_zoom_x = ip[12];
      style.allow_zoom_y = ip[13];
    }
    if (intCount >= 15) {
      style.show_current_price_line = ip[14];
    }
    env->ReleaseIntArrayElements(ints, ip, JNI_ABORT);
  }
  chart_engine_set_style(reinterpret_cast<void*>(handle), &style);
}

JNIEXPORT jlong JNICALL
CHART_JNI_METHOD(nativeStyleRevision)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_style_revision(reinterpret_cast<void*>(handle));
}

// Float layout (matches Dart NativeChartStyle / JNI nativeSetStyle):
//   [0..47]  = 12 RGBA colors (48 floats)
//   [48]     = candle_body_width_fraction
//   [49]     = line_width_px
//   [50]     = wick_width_px
//   [51]     = crosshair_width_px
//   [52]     = x_pad_fraction
//   [53]     = y_pad_fraction
//   [54..57] = current_price_line_color (4 floats)
JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeGetStyleFloats)(JNIEnv* env, jclass, jlong handle,
                                       jfloatArray out) {
  if (handle == 0 || out == nullptr) return;
  if (env->GetArrayLength(out) < 58) return;
  ChartStyle s{};
  chart_engine_get_style(reinterpret_cast<void*>(handle), &s);
  jfloat buf[58];
  std::memcpy(buf + 0,  s.bg_color,           sizeof(float) * 4);
  std::memcpy(buf + 4,  s.grid_color,         sizeof(float) * 4);
  std::memcpy(buf + 8,  s.axis_text_color,    sizeof(float) * 4);
  std::memcpy(buf + 12, s.up_color,           sizeof(float) * 4);
  std::memcpy(buf + 16, s.down_color,         sizeof(float) * 4);
  std::memcpy(buf + 20, s.line_color,         sizeof(float) * 4);
  std::memcpy(buf + 24, s.area_top_color,     sizeof(float) * 4);
  std::memcpy(buf + 28, s.area_bottom_color,  sizeof(float) * 4);
  std::memcpy(buf + 32, s.crosshair_color,    sizeof(float) * 4);
  std::memcpy(buf + 36, s.tooltip_bg_color,   sizeof(float) * 4);
  std::memcpy(buf + 40, s.tooltip_text_color, sizeof(float) * 4);
  std::memcpy(buf + 44, s.legend_text_color,  sizeof(float) * 4);
  buf[48] = s.candle_body_width_fraction;
  buf[49] = s.line_width_px;
  buf[50] = s.wick_width_px;
  buf[51] = s.crosshair_width_px;
  buf[52] = s.x_pad_fraction;
  buf[53] = s.y_pad_fraction;
  std::memcpy(buf + 54, s.current_price_line_color, sizeof(float) * 4);
  env->SetFloatArrayRegion(out, 0, 58, buf);
}

// Int layout (matches Dart NativeChartStyle / JNI nativeSetStyle):
//   [0] show_grid, [1] show_x_axis, [2] show_y_axis,
//   [3] show_crosshair, [4] show_tooltip, [5] show_legend,
//   [6] approx_x_ticks, [7] approx_y_ticks,
//   [8] y_decimals, [9] x_is_timestamp_ms,
//   [10..13] allow_pan_x, allow_pan_y, allow_zoom_x, allow_zoom_y
//   [14] show_current_price_line
//   [15] double_tap_to_reset
JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeGetStyleInts)(JNIEnv* env, jclass, jlong handle,
                                     jintArray out) {
  if (handle == 0 || out == nullptr) return;
  const jsize want = 16;
  if (env->GetArrayLength(out) < want) return;
  ChartStyle s{};
  chart_engine_get_style(reinterpret_cast<void*>(handle), &s);
  jint buf[16] = {
    s.show_grid, s.show_x_axis, s.show_y_axis,
    s.show_crosshair, s.show_tooltip, s.show_legend,
    s.approx_x_ticks, s.approx_y_ticks,
    s.y_decimals, s.x_is_timestamp_ms,
    s.allow_pan_x, s.allow_pan_y, s.allow_zoom_x, s.allow_zoom_y,
    s.show_current_price_line,
    s.double_tap_to_reset,
  };
  env->SetIntArrayRegion(out, 0, want, buf);
}

JNIEXPORT jstring JNICALL
CHART_JNI_METHOD(nativeGetSeriesLabel)(JNIEnv* env, jclass, jlong handle) {
  if (handle == 0) return env->NewStringUTF("");
  ChartStyle s{};
  chart_engine_get_style(reinterpret_cast<void*>(handle), &s);
  // Force null-termination paranoia, then hand to JNI.
  s.series_label[sizeof(s.series_label) - 1] = '\0';
  return env->NewStringUTF(s.series_label);
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativeHasVolumePane)(JNIEnv*, jclass, jlong handle) {
  return chart_engine_has_volume_pane(reinterpret_cast<void*>(handle));
}

JNIEXPORT jint JNICALL
CHART_JNI_METHOD(nativePassZone)(JNIEnv*, jclass, jlong handle, jint pass) {
  return chart_engine_pass_zone(reinterpret_cast<void*>(handle), pass);
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeGetPriceProjectionMatrix)(JNIEnv* env, jclass, jlong handle,
                                                  jfloatArray out16) {
  if (handle == 0 || out16 == nullptr) return;
  if (env->GetArrayLength(out16) < 16) return;
  jfloat* ptr = env->GetFloatArrayElements(out16, nullptr);
  chart_engine_get_price_projection_matrix(reinterpret_cast<void*>(handle), ptr);
  env->ReleaseFloatArrayElements(out16, ptr, 0);
}

JNIEXPORT void JNICALL
CHART_JNI_METHOD(nativeGetVolumeProjectionMatrix)(JNIEnv* env, jclass, jlong handle,
                                                   jfloatArray out16) {
  if (handle == 0 || out16 == nullptr) return;
  if (env->GetArrayLength(out16) < 16) return;
  jfloat* ptr = env->GetFloatArrayElements(out16, nullptr);
  chart_engine_get_volume_projection_matrix(reinterpret_cast<void*>(handle), ptr);
  env->ReleaseFloatArrayElements(out16, ptr, 0);
}

JNIEXPORT jdouble JNICALL
CHART_JNI_METHOD(nativeUnprojectY)(JNIEnv*, jclass, jlong handle, jdouble yNdc) {
  return chart_engine_unproject_y(reinterpret_cast<void*>(handle), yNdc);
}

JNIEXPORT jdouble JNICALL
CHART_JNI_METHOD(nativeUnprojectX)(JNIEnv*, jclass, jlong handle, jdouble xNdc) {
  return chart_engine_unproject_x(reinterpret_cast<void*>(handle), xNdc);
}

}  // extern "C"
