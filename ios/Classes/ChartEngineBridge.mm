#import "ChartEngineBridge.h"

#include <cstring>

#include "chart_engine_ffi.h"

@implementation ChartEngineBridge {
  void* _engine;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _engine = create_chart_engine();
  }
  return self;
}

- (void)dealloc {
  if (_engine != nullptr) {
    destroy_chart_engine(_engine);
    _engine = nullptr;
  }
}

- (intptr_t)handle {
  return reinterpret_cast<intptr_t>(_engine);
}

- (intptr_t)viewportHandle {
  return reinterpret_cast<intptr_t>(chart_engine_get_viewport(_engine));
}

- (void)setSeriesType:(int)type {
  chart_engine_set_series_type(_engine, type);
}

- (int)seriesType {
  return chart_engine_get_series_type(_engine);
}

- (int)generation {
  return chart_engine_generation(_engine);
}

- (int)passCount {
  return chart_engine_pass_count(_engine);
}

- (long long)viewportRevision {
  return chart_engine_viewport_revision(_engine);
}

- (void)rebuildGeometryForViewport {
  chart_engine_rebuild_for_viewport(_engine);
}

- (int)readPass:(int)pass
   outPrimitive:(int *)outPrimitive
    outVertices:(float *)outVertices
       capacity:(int)capacityInFloats {
  return chart_engine_read_pass(_engine, pass, outPrimitive, outVertices, capacityInFloats);
}

- (void)pushCandlesRaw:(const double *)data count:(int)count {
  push_candles_raw(_engine, data, count);
}

- (void)appendCandlesRaw:(const double *)data count:(int)count {
  append_candles_raw(_engine, data, count);
}

- (int)candleCount {
  return chart_engine_candle_count(_engine);
}

- (int)getCandle:(int)index out6:(double *)out6 {
  if (out6 == nullptr) return 0;
  NativeCandle c{};
  const int ok = chart_engine_get_candle(_engine, index, &c);
  if (ok) {
    out6[0] = c.timestamp;
    out6[1] = c.open;
    out6[2] = c.high;
    out6[3] = c.low;
    out6[4] = c.close;
    out6[5] = c.volume;
  }
  return ok;
}

- (void)getDataBoundsOut4:(double *)out4 {
  if (out4 == nullptr) return;
  chart_engine_get_data_bounds(_engine, &out4[0], &out4[1], &out4[2], &out4[3]);
}

- (int)hitTest:(double)xData {
  return chart_engine_hit_test(_engine, xData);
}

- (void)setHover:(int)index {
  chart_engine_set_hover(_engine, index);
}

- (int)hover {
  return chart_engine_get_hover(_engine);
}

- (int)getXTicks:(double *)out maxCount:(int)maxCount {
  return chart_engine_get_x_ticks(_engine, out, maxCount);
}

- (int)getYTicks:(double *)out maxCount:(int)maxCount {
  return chart_engine_get_y_ticks(_engine, out, maxCount);
}

- (void)projectX:(const double *)inX count:(int)count outNdc:(double *)outNdc {
  chart_engine_project_x(_engine, inX, count, outNdc);
}

- (void)projectY:(const double *)inY count:(int)count outNdc:(double *)outNdc {
  chart_engine_project_y(_engine, inY, count, outNdc);
}

- (void)setStyleFloats:(const float *)floats floatCount:(int)floatCount
                  ints:(const int *)ints intCount:(int)intCount
           seriesLabel:(NSString *)seriesLabel {
  ChartStyle style{};
  chart_engine_get_default_style(&style);
  if (floats != nullptr && floatCount >= 54) {
    std::memcpy(style.bg_color, floats + 0, sizeof(float) * 4);
    std::memcpy(style.grid_color, floats + 4, sizeof(float) * 4);
    std::memcpy(style.axis_text_color, floats + 8, sizeof(float) * 4);
    std::memcpy(style.up_color, floats + 12, sizeof(float) * 4);
    std::memcpy(style.down_color, floats + 16, sizeof(float) * 4);
    std::memcpy(style.line_color, floats + 20, sizeof(float) * 4);
    std::memcpy(style.area_top_color, floats + 24, sizeof(float) * 4);
    std::memcpy(style.area_bottom_color, floats + 28, sizeof(float) * 4);
    std::memcpy(style.crosshair_color, floats + 32, sizeof(float) * 4);
    std::memcpy(style.tooltip_bg_color, floats + 36, sizeof(float) * 4);
    std::memcpy(style.tooltip_text_color, floats + 40, sizeof(float) * 4);
    std::memcpy(style.legend_text_color, floats + 44, sizeof(float) * 4);
    style.candle_body_width_fraction = floats[48];
    style.line_width_px = floats[49];
    style.wick_width_px = floats[50];
    style.crosshair_width_px = floats[51];
    style.x_pad_fraction = floats[52];
    style.y_pad_fraction = floats[53];
    if (floatCount >= 58) {
      std::memcpy(style.current_price_line_color, floats + 54, sizeof(float) * 4);
    }
  }
  if (ints != nullptr && intCount >= 10) {
    style.show_grid = ints[0];
    style.show_x_axis = ints[1];
    style.show_y_axis = ints[2];
    style.show_crosshair = ints[3];
    style.show_tooltip = ints[4];
    style.show_legend = ints[5];
    style.approx_x_ticks = ints[6];
    style.approx_y_ticks = ints[7];
    style.y_decimals = ints[8];
    style.x_is_timestamp_ms = ints[9];
    if (intCount >= 14) {
      style.allow_pan_x = ints[10];
      style.allow_pan_y = ints[11];
      style.allow_zoom_x = ints[12];
      style.allow_zoom_y = ints[13];
    }
    if (intCount >= 15) {
      style.show_current_price_line = ints[14];
    }
    if (intCount >= 16) {
      style.double_tap_to_reset = ints[15];
    }
  }
  std::memset(style.series_label, 0, sizeof(style.series_label));
  if (seriesLabel != nil) {
    const char* utf8 = [seriesLabel UTF8String];
    if (utf8 != nullptr) {
      std::strncpy(style.series_label, utf8, sizeof(style.series_label) - 1);
    }
  }
  chart_engine_set_style(_engine, &style);
}

- (long long)styleRevision {
  return chart_engine_style_revision(_engine);
}

- (void)getStyleFloats:(float *)out floatCount:(int)floatCount {
  if (out == nullptr || floatCount < 58) return;
  ChartStyle s{};
  chart_engine_get_style(_engine, &s);
  std::memcpy(out + 0,  s.bg_color,           sizeof(float) * 4);
  std::memcpy(out + 4,  s.grid_color,         sizeof(float) * 4);
  std::memcpy(out + 8,  s.axis_text_color,    sizeof(float) * 4);
  std::memcpy(out + 12, s.up_color,           sizeof(float) * 4);
  std::memcpy(out + 16, s.down_color,         sizeof(float) * 4);
  std::memcpy(out + 20, s.line_color,         sizeof(float) * 4);
  std::memcpy(out + 24, s.area_top_color,     sizeof(float) * 4);
  std::memcpy(out + 28, s.area_bottom_color,  sizeof(float) * 4);
  std::memcpy(out + 32, s.crosshair_color,    sizeof(float) * 4);
  std::memcpy(out + 36, s.tooltip_bg_color,   sizeof(float) * 4);
  std::memcpy(out + 40, s.tooltip_text_color, sizeof(float) * 4);
  std::memcpy(out + 44, s.legend_text_color,  sizeof(float) * 4);
  out[48] = s.candle_body_width_fraction;
  out[49] = s.line_width_px;
  out[50] = s.wick_width_px;
  out[51] = s.crosshair_width_px;
  out[52] = s.x_pad_fraction;
  out[53] = s.y_pad_fraction;
  std::memcpy(out + 54, s.current_price_line_color, sizeof(float) * 4);
}

- (void)getStyleInts:(int *)out intCount:(int)intCount {
  if (out == nullptr || intCount < 16) return;
  ChartStyle s{};
  chart_engine_get_style(_engine, &s);
  out[0] = s.show_grid;
  out[1] = s.show_x_axis;
  out[2] = s.show_y_axis;
  out[3] = s.show_crosshair;
  out[4] = s.show_tooltip;
  out[5] = s.show_legend;
  out[6] = s.approx_x_ticks;
  out[7] = s.approx_y_ticks;
  out[8] = s.y_decimals;
  out[9] = s.x_is_timestamp_ms;
  out[10] = s.allow_pan_x;
  out[11] = s.allow_pan_y;
  out[12] = s.allow_zoom_x;
  out[13] = s.allow_zoom_y;
  out[14] = s.show_current_price_line;
  out[15] = s.double_tap_to_reset;
}

- (NSString *)seriesLabel {
  ChartStyle s{};
  chart_engine_get_style(_engine, &s);
  s.series_label[sizeof(s.series_label) - 1] = '\0';
  return [NSString stringWithUTF8String:s.series_label] ?: @"";
}

@end
