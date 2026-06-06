#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define CHART_ENGINE_EXPORT __declspec(dllexport)
#else
#define CHART_ENGINE_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

struct NativeCandle {
  double timestamp;
  double open;
  double high;
  double low;
  double close;
  double volume;
};

// Series types. Must mirror Dart `SeriesType`.
#define CHART_SERIES_CANDLE 0
#define CHART_SERIES_LINE 1
#define CHART_SERIES_AREA 2

// Renderer-agnostic primitive types.
#define CHART_PRIMITIVE_TRIANGLES 0
#define CHART_PRIMITIVE_LINES 1
#define CHART_PRIMITIVE_LINE_STRIP 2
#define CHART_PRIMITIVE_TRIANGLE_STRIP 3

// Trade line types. Must mirror Dart `TradeLineType`.
#define CHART_TRADE_LINE_TREND 0
#define CHART_TRADE_LINE_ENTRY 1
#define CHART_TRADE_LINE_STOP_LOSS 2
#define CHART_TRADE_LINE_TAKE_PROFIT 3

/// POD trend / trade segment (two data-space endpoints + color).
struct NativeTradeLine {
  char order_id[32];
  int type;
  int _abi_pad;
  double x1;
  double y1;
  double x2;
  double y2;
  float color[4];
};

// =========================================================================
// ChartStyle (POD, ABI-stable).
//
// Drives every visual aspect of the chart so Dart can hand the engine one
// struct and the engine handles colors / widths / paddings / visibility /
// tick density entirely on the native side.
//
// CRITICAL: keep field order and types in lock-step with the Dart-side
// `NativeChartStyle` struct in chart_engine_ffi.dart. Reserved tail keeps
// the ABI growable without breaking older callers.
// =========================================================================
struct ChartStyle {
  // -- Colors (RGBA, 0..1 floats) --
  float bg_color[4];
  float grid_color[4];
  float axis_text_color[4];
  float up_color[4];
  float down_color[4];
  float line_color[4];
  float area_top_color[4];
  float area_bottom_color[4];
  float crosshair_color[4];
  float tooltip_bg_color[4];
  float tooltip_text_color[4];
  float legend_text_color[4];

  // -- Geometry --
  float candle_body_width_fraction;  // 0..1 of avg candle spacing
  float line_width_px;
  float wick_width_px;
  float crosshair_width_px;

  // -- Padding (fraction of data extent) --
  float x_pad_fraction;
  float y_pad_fraction;

  // -- Toggles (1 = on, 0 = off) --
  int show_grid;
  int show_x_axis;
  int show_y_axis;
  int show_crosshair;
  int show_tooltip;
  int show_legend;

  // -- Tick density --
  int approx_x_ticks;
  int approx_y_ticks;

  // -- Formatting --
  int y_decimals;
  int x_is_timestamp_ms;  // 1 = x axis values are unix ms; native UI formats as date/time

  // -- Interaction (1 = allow, 0 = lock) --
  // When pan X is locked, horizontal drag scrubs: hover follows x under finger
  // and the native tooltip tracks the scrub point (TradingView / Grow-like).
  int allow_pan_x;
  int allow_pan_y;
  int allow_zoom_x;
  int allow_zoom_y;

  // -- Series label (UTF-8, null-terminated, max 31 chars + '\0') --
  // Lives in the style struct so it can flow Dart -> engine -> native UI via
  // a single FFI call (no MethodChannel hop). The native overlay reads it
  // back via chart_engine_get_style on every style_revision bump.
  char series_label[32];

  // -- Current price line (appended at tail for ABI compat) --
  int show_current_price_line;         // 4 bytes
  float current_price_line_color[4];   // 16 bytes  → total 20

  int double_tap_to_reset;             // 4 bytes

  // -- Current price line (appended at tail for ABI compat) --
  int show_current_price_line;         // 4 bytes
  float current_price_line_color[4];   // 16 bytes  → total 20

  int double_tap_to_reset;             // 4 bytes
};

// --- Lifecycle ---
CHART_ENGINE_EXPORT void* create_chart_engine(void);
CHART_ENGINE_EXPORT void destroy_chart_engine(void* engine);

// --- Style ---
CHART_ENGINE_EXPORT void chart_engine_set_style(void* engine, const struct ChartStyle* style);
CHART_ENGINE_EXPORT void chart_engine_get_default_style(struct ChartStyle* out_style);

/// Snapshot of the engine's current style. Native overlays / renderers
/// poll this whenever `chart_engine_style_revision` changes; replaces the
/// per-view MethodChannel that used to ferry style updates from Dart to
/// the native UI layer.
CHART_ENGINE_EXPORT void chart_engine_get_style(void* engine, struct ChartStyle* out_style);

/// Monotonic counter bumped on every successful `chart_engine_set_style`.
/// Lets the native overlay treat style updates like viewport/generation
/// changes (poll-on-change, no IPC).
CHART_ENGINE_EXPORT long long chart_engine_style_revision(void* engine);

// --- Data ---
/// Legacy struct-based ingestion (one entry per `NativeCandle`).
CHART_ENGINE_EXPORT void push_candles(void* engine, struct NativeCandle* candles, int count);

/// Zero-copy raw-double ingestion. `data` points to 6 * `count` doubles laid
/// out as [t, o, h, l, c, v] per candle. Matches NativeCandle byte layout
/// exactly so the engine performs ONE memcpy and rebuilds geometry.
CHART_ENGINE_EXPORT void push_candles_raw(void* engine, const double* data, int count);

/// Appends `count` candles to the existing buffer (does not replace).
/// Same layout as push_candles_raw. Use for streaming / live data.
CHART_ENGINE_EXPORT void append_candles_raw(void* engine, const double* data, int count);

/// Width of each aggregate bar in milliseconds (live tick bucketing).
CHART_ENGINE_EXPORT void chart_engine_set_timeframe(void* engine, double interval_ms);

/// Apply one trade tick: updates the last candle while `timestamp` remains
/// inside the current `[last.timestamp, last.timestamp + interval)` window,
/// otherwise appends a new OHLC bar. Updates geometry and may auto-pan the
/// viewport when live-edge tracking is active.
CHART_ENGINE_EXPORT void chart_engine_update_live_tick(void* engine,
                                                       double timestamp,
                                                       double price,
                                                       double volume);

/// Venue / aggregate OHLC for the forming or next candle (same timeframe rules).
CHART_ENGINE_EXPORT void chart_engine_update_live_ohlc(void* engine,
                                                       double timestamp,
                                                       double open,
                                                       double high,
                                                       double low,
                                                       double close,
                                                       double volume);

CHART_ENGINE_EXPORT void chart_engine_get_data_bounds(void* engine,
                                                     double* xMin, double* xMax,
                                                     double* yMin, double* yMax);

CHART_ENGINE_EXPORT int chart_engine_candle_count(void* engine);
CHART_ENGINE_EXPORT int chart_engine_get_candle(void* engine, int index, struct NativeCandle* out);

// --- Series ---
CHART_ENGINE_EXPORT void chart_engine_set_series_type(void* engine, int type);
CHART_ENGINE_EXPORT int chart_engine_get_series_type(void* engine);

// --- Viewport ---
CHART_ENGINE_EXPORT void* chart_engine_get_viewport(void* engine);
CHART_ENGINE_EXPORT long long chart_engine_viewport_revision(void* engine);

/// Rebuilds baked GPU geometry using the **current visible** viewport bounds.
/// Needed after pan/zoom so line/area meshes keep correct thickness and retain
/// float precision (vertices are shifted by visible min).
CHART_ENGINE_EXPORT void chart_engine_rebuild_for_viewport(void* engine);

// --- Geometry ---
CHART_ENGINE_EXPORT int chart_engine_generation(void* engine);
CHART_ENGINE_EXPORT int chart_engine_pass_count(void* engine);
CHART_ENGINE_EXPORT int chart_engine_read_pass(void* engine,
                                                int pass,
                                                int* out_primitive,
                                                float* out_buffer,
                                                int out_capacity_floats);

// --- Hit-testing + hover ---
/// Returns the index of the candle whose timestamp is closest to `xData`,
/// or -1 if the engine has no data.
CHART_ENGINE_EXPORT int chart_engine_hit_test(void* engine, double xData);

/// Sets the currently-hovered candle. Pass -1 to clear. Triggers a geometry
/// rebuild so the crosshair pass appears / disappears.
CHART_ENGINE_EXPORT void chart_engine_set_hover(void* engine, int index);

CHART_ENGINE_EXPORT int chart_engine_get_hover(void* engine);

// --- Ticks (computed for current visible domain/range) ---
CHART_ENGINE_EXPORT int chart_engine_get_x_ticks(void* engine, double* out, int max_count);
CHART_ENGINE_EXPORT int chart_engine_get_y_ticks(void* engine, double* out, int max_count);

// --- Projection (data <-> NDC) ---
CHART_ENGINE_EXPORT void chart_engine_project_x(void* engine,
                                                 const double* in_x, int count,
                                                 double* out_ndc);
CHART_ENGINE_EXPORT void chart_engine_project_y(void* engine,
                                                 const double* in_y, int count,
                                                 double* out_ndc);

#ifdef __cplusplus
}
#endif
