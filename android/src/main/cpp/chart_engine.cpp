#include "chart_engine_ffi.h"
#include "viewport_engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <iterator>
#include <mutex>
#include <vector>

namespace {

constexpr int kFloatsPerVertex = 6;

// After viewport culling, at most this many candles become GPU vertices. Beyond
// that we stride through the visible range (~1e6 candles would otherwise cost
// ~192MiB candle-body + wick buffers and OOM GLES on typical Android heaps).
constexpr size_t kMaxGpuCandles = 16384;

inline void writeVertex(float*& cursor,
                        double x, double y,
                        float r, float g, float b, float a) {
  cursor[0] = static_cast<float>(x);
  cursor[1] = static_cast<float>(y);
  cursor[2] = r;
  cursor[3] = g;
  cursor[4] = b;
  cursor[5] = a;
  cursor += kFloatsPerVertex;
}

struct PassData {
  std::vector<float> vertices;
  int primitive = CHART_PRIMITIVE_TRIANGLES;
};

inline void setColor(float dst[4], float r, float g, float b, float a) {
  dst[0] = r;
  dst[1] = g;
  dst[2] = b;
  dst[3] = a;
}

ChartStyle makeDefaultStyle() {
  ChartStyle s{};
  setColor(s.bg_color, 11.0f / 255.0f, 14.0f / 255.0f, 20.0f / 255.0f, 1.0f);
  setColor(s.grid_color, 0.20f, 0.22f, 0.28f, 0.45f);
  setColor(s.axis_text_color, 0.55f, 0.59f, 0.66f, 1.0f);
  setColor(s.up_color, 0.486f, 1.0f, 0.698f, 1.0f);
  setColor(s.down_color, 1.0f, 0.380f, 0.502f, 1.0f);
  setColor(s.line_color, 0.486f, 1.0f, 0.698f, 1.0f);
  setColor(s.area_top_color, 0.486f, 1.0f, 0.698f, 0.85f);
  setColor(s.area_bottom_color, 0.486f, 1.0f, 0.698f, 0.05f);
  setColor(s.crosshair_color, 1.0f, 0.85f, 0.40f, 0.75f);
  setColor(s.tooltip_bg_color, 0.07f, 0.09f, 0.12f, 0.95f);
  setColor(s.tooltip_text_color, 1.0f, 1.0f, 1.0f, 1.0f);
  setColor(s.legend_text_color, 0.486f, 1.0f, 0.698f, 1.0f);

  s.candle_body_width_fraction = 0.7f;
  s.line_width_px = 2.2f;
  s.wick_width_px = 1.0f;
  s.crosshair_width_px = 1.2f;
  s.x_pad_fraction = 0.02f;
  s.y_pad_fraction = 0.05f;

  s.show_grid = 1;
  s.show_x_axis = 1;
  s.show_y_axis = 1;
  s.show_crosshair = 1;
  s.show_tooltip = 1;
  s.show_legend = 1;

  s.approx_x_ticks = 6;
  s.approx_y_ticks = 5;
  s.y_decimals = 2;
  s.x_is_timestamp_ms = 1;

  s.allow_pan_x = 1;
  s.allow_pan_y = 1;
  s.allow_zoom_x = 1;
  s.allow_zoom_y = 1;

  std::memset(s.series_label, 0, sizeof(s.series_label));
  // Default series label; Dart can override per series via ChartStyle.seriesLabel.
  const char* defaultLabel = "CANDLE";
  std::strncpy(s.series_label, defaultLabel, sizeof(s.series_label) - 1);
  return s;
}

/// "Nice numbers" tick generator. Produces ticks within [min, max] using a
/// human-friendly step (1, 2, 5 × 10^n) aiming for approxCount ticks.
std::vector<double> niceTicks(double min, double max, int approxCount) {
  std::vector<double> out;
  if (approxCount <= 0 || !(max > min)) return out;
  const double range = max - min;
  const double rawStep = range / static_cast<double>(approxCount);
  const double exponent = std::floor(std::log10(rawStep));
  const double powTen = std::pow(10.0, exponent);
  const double fraction = rawStep / powTen;
  double niceFraction;
  if (fraction < 1.5) niceFraction = 1.0;
  else if (fraction < 3.0) niceFraction = 2.0;
  else if (fraction < 7.0) niceFraction = 5.0;
  else niceFraction = 10.0;
  const double step = niceFraction * powTen;
  const double first = std::ceil(min / step) * step;
  // Cap at a reasonable number to avoid runaway output for degenerate input.
  for (int i = 0; i < 1024; ++i) {
    const double t = first + step * i;
    if (t > max + step * 1e-6) break;
    out.push_back(t);
  }
  return out;
}

}  // namespace

struct ChartEngineState {
  mutable std::mutex mtx;

  ViewportEngine viewport;
  std::vector<NativeCandle> candles;
  int series_type = CHART_SERIES_CANDLE;
  ChartStyle style;

  std::vector<PassData> passes;
  int generation = 0;

  double data_x_min = -1.0;
  double data_x_max = 1.0;
  double data_y_min = -1.0;
  double data_y_max = 1.0;

  int hover_index = -1;

  std::vector<double> x_ticks;
  std::vector<double> y_ticks;
  long long ticks_revision = -1;

  // Monotonic counter bumped on every successful set_style. Native overlay
  // / renderer poll this each frame and re-snapshot the style when it
  // changes — replaces the per-view MethodChannel that used to push style
  // updates from Dart.
  long long style_revision = 0;

  double timeframe_interval_ms = 60000.0;

  /// Subtracted from baked world coords so float verts keep precision vs huge timestamps.
  double geom_vx_min_ = 0.0;
  double geom_vy_min_ = 0.0;

  ChartEngineState() : style(makeDefaultStyle()) {}

  void recomputeDataBounds() {
    if (candles.empty()) {
      data_x_min = -1.0;
      data_x_max = 1.0;
      data_y_min = -1.0;
      data_y_max = 1.0;
      return;
    }
    double xMin = candles.front().timestamp;
    double xMax = candles.back().timestamp;
    if (xMax <= xMin) {
      xMin -= 1.0;
      xMax += 1.0;
    } else {
      const double pad = (xMax - xMin) * style.x_pad_fraction;
      xMin -= pad;
      xMax += pad;
    }
    double yMin = candles.front().low;
    double yMax = candles.front().high;
    for (const auto& c : candles) {
      yMin = std::min(yMin, c.low);
      yMax = std::max(yMax, c.high);
    }
    if (yMax <= yMin) {
      yMin -= 1.0;
      yMax += 1.0;
    } else {
      const double pad = (yMax - yMin) * style.y_pad_fraction;
      yMin -= pad;
      yMax += pad;
    }
    data_x_min = xMin;
    data_x_max = xMax;
    data_y_min = yMin;
    data_y_max = yMax;
  }

  // Recomputes ticks from the current visible domain. Re-used by render
  // pass generation and by chart_engine_get_x/y_ticks (which is what the
  // native UI overlay reads on viewport change).
  void recomputeTicks() {
    x_ticks.clear();
    y_ticks.clear();
    if (candles.empty()) return;
    double xMin, xMax, yMin, yMax;
    viewport.getVisibleDomain(&xMin, &xMax);
    viewport.getVisibleRange(&yMin, &yMax);
    x_ticks = niceTicks(xMin, xMax, style.approx_x_ticks);
    y_ticks = niceTicks(yMin, yMax, style.approx_y_ticks);
    ticks_revision = viewport.revision();
  }

  void ensureTicksFresh() {
    if (ticks_revision != viewport.revision()) {
      recomputeTicks();
    }
  }

  struct GpuLodWindow {
    size_t begin = 0;
    size_t end = 0;
    int stride = 1;
  };

  GpuLodWindow computeGpuLodWindow() const {
    GpuLodWindow w;
    const size_t n = candles.size();
    if (n == 0) {
      return w;
    }
    w.begin = 0;
    w.end = n;

    double vx_min = 0.0;
    double vx_max = 0.0;
    viewport.getVisibleDomain(&vx_min, &vx_max);
    const double span = std::max(vx_max - vx_min, 1e-18);
    const double data_span =
        std::max(candles.back().timestamp - candles.front().timestamp, 1e-18);
    const double pad = std::max(span * 0.08, data_span * 1e-12);

    const auto lo_it = std::lower_bound(
        candles.begin(), candles.end(), vx_min - pad,
        [](const NativeCandle& c, double tt) { return c.timestamp < tt; });
    const auto hi_it = std::upper_bound(
        candles.begin(), candles.end(), vx_max + pad,
        [](double tt, const NativeCandle& c) { return tt < c.timestamp; });
    w.begin = static_cast<size_t>(std::distance(candles.begin(), lo_it));
    w.end = static_cast<size_t>(std::distance(candles.begin(), hi_it));

    if (w.end <= w.begin || w.begin >= n) {
      w.begin = 0;
      w.end = n;
    }
    const size_t vis = w.end - w.begin;
    if (vis > kMaxGpuCandles) {
      w.stride = static_cast<int>((vis + kMaxGpuCandles - 1) / kMaxGpuCandles);
    } else {
      w.stride = 1;
    }
    return w;
  }

  void emitWorld(float*& cur, double wx, double wy, float rb, float gb, float bb, float ab) {
    writeVertex(cur,
                static_cast<float>(wx - geom_vx_min_),
                static_cast<float>(wy - geom_vy_min_),
                rb,
                gb,
                bb,
                ab);
  }

  // ------- Geometry builders -------

  void buildLineGeometry(PassData& p) {
    p.primitive = CHART_PRIMITIVE_TRIANGLE_STRIP;
    p.vertices.clear();
    const size_t n = candles.size();
    if (n < 1) return;

    double vxMin, vxMax, vyMin, vyMax;
    viewport.getVisibleDomain(&vxMin, &vxMax);
    viewport.getVisibleRange(&vyMin, &vyMax);
    const double xrange = std::max(vxMax - vxMin, 1e-18);
    const double yrange = std::max(vyMax - vyMin, 1e-18);
    const double halfThickPx = style.line_width_px * 0.5;
    const double halfNdc = halfThickPx / 800.0;
    const float r = style.line_color[0];
    const float g = style.line_color[1];
    const float b = style.line_color[2];
    const float a = style.line_color[3];

    auto emitDirectedStripPoint = [&](float*& cur, double px, double py,
                                      double segDx, double segDy) {
      double tx = segDx / xrange;
      double ty = segDy / yrange;
      const double len = std::hypot(tx, ty);
      double nxc = 0.0;
      double nyc = 1.0;
      if (len > 1e-15) {
        nxc = -ty / len;
        nyc = tx / len;
      }
      const double offX = nxc * halfNdc * xrange * 0.5;
      const double offY = nyc * halfNdc * yrange * 0.5;
      emitWorld(cur, px + offX, py + offY, r, g, b, a);
      emitWorld(cur, px - offX, py - offY, r, g, b, a);
    };

    const GpuLodWindow lod = computeGpuLodWindow();
    const int st = std::max(lod.stride, 1);
    const size_t m =
        (lod.end > lod.begin)
            ? (lod.end - lod.begin + static_cast<size_t>(st) - 1) /
                  static_cast<size_t>(st)
            : 0;
    if (m < 1) {
      return;
    }

    if (m == 1) {
      const size_t idx = lod.begin;
      const double px = candles[idx].timestamp;
      const double py = candles[idx].close;
      const double fudge = std::max(1e-3, xrange * 1e-10);
      p.vertices.resize(4 * kFloatsPerVertex);
      float* cur = p.vertices.data();
      emitDirectedStripPoint(cur, px, py, fudge, 0.0);
      emitDirectedStripPoint(cur, px + fudge, py, fudge, 0.0);
      return;
    }

    p.vertices.resize(m * 2 * kFloatsPerVertex);
    float* cur = p.vertices.data();

    auto pt = [&](size_t i) {
      return std::pair<double, double>{candles[i].timestamp, candles[i].close};
    };
    auto emitAtIndex = [&](size_t i, float*& out_cur) {
      const auto [px, py] = pt(i);
      double dxN = 0.0;
      double dyN = 0.0;
      if (i == 0) {
        const auto [nx, ny] = pt(i + 1);
        dxN = nx - px;
        dyN = ny - py;
      } else if (i >= n - 1) {
        const auto [qx, qy] = pt(i - 1);
        dxN = px - qx;
        dyN = py - qy;
      } else {
        const auto [qx, qy] = pt(i - 1);
        const auto [nx, ny] = pt(i + 1);
        dxN = nx - qx;
        dyN = ny - qy;
      }
      emitDirectedStripPoint(out_cur, px, py, dxN, dyN);
    };
    for (size_t ii = lod.begin; ii < lod.end; ii += static_cast<size_t>(st)) {
      emitAtIndex(ii, cur);
    }
  }

  void buildAreaGeometry(PassData& p) {
    p.primitive = CHART_PRIMITIVE_TRIANGLE_STRIP;
    p.vertices.clear();
    const size_t n = candles.size();
    if (n < 1) return;

    double vyMin = data_y_min;
    viewport.getVisibleRange(&vyMin, nullptr);
    const double baseline = vyMin;
    const float* top = style.area_top_color;
    const float* bot = style.area_bottom_color;

    double vxMin, vxMax;
    viewport.getVisibleDomain(&vxMin, &vxMax);
    const double xrange = std::max(vxMax - vxMin, 1e-18);

    const GpuLodWindow lod = computeGpuLodWindow();
    const int st = std::max(lod.stride, 1);
    const size_t m =
        (lod.end > lod.begin)
            ? (lod.end - lod.begin + static_cast<size_t>(st) - 1) /
                  static_cast<size_t>(st)
            : 0;
    if (m < 1) {
      return;
    }

    if (m == 1) {
      const double fudge = std::max(1e-3, xrange * 1e-10);
      const size_t idx = lod.begin;
      const double px = candles[idx].timestamp;
      const double py = candles[idx].close;
      p.vertices.resize(4 * kFloatsPerVertex);
      float* cur = p.vertices.data();
      emitWorld(cur, px, py, top[0], top[1], top[2], top[3]);
      emitWorld(cur, px, baseline, bot[0], bot[1], bot[2], bot[3]);
      emitWorld(cur, px + fudge, py, top[0], top[1], top[2], top[3]);
      emitWorld(cur, px + fudge, baseline, bot[0], bot[1], bot[2], bot[3]);
      return;
    }

    p.vertices.resize(m * 2 * kFloatsPerVertex);
    float* cur = p.vertices.data();
    for (size_t ii = lod.begin; ii < lod.end; ii += static_cast<size_t>(st)) {
      const NativeCandle& c = candles[ii];
      emitWorld(cur, c.timestamp, c.close, top[0], top[1], top[2], top[3]);
      emitWorld(cur, c.timestamp, baseline, bot[0], bot[1], bot[2], bot[3]);
    }
  }

  void buildCandleBodyAndWick(PassData& body, PassData& wick) {
    body.primitive = CHART_PRIMITIVE_TRIANGLES;
    wick.primitive = CHART_PRIMITIVE_LINES;
    body.vertices.clear();
    wick.vertices.clear();
    const size_t n = candles.size();
    if (n == 0) return;

    double vyMin, vyMax;
    viewport.getVisibleRange(&vyMin, &vyMax);
    const double yVisRange = std::max(vyMax - vyMin, 1e-18);
    const double minBody = yVisRange * 0.001;

    const double fracHalf = style.candle_body_width_fraction * 0.5;

    const GpuLodWindow lod = computeGpuLodWindow();
    const int st = std::max(lod.stride, 1);
    const size_t m =
        (lod.end > lod.begin)
            ? (lod.end - lod.begin + static_cast<size_t>(st) - 1) /
                  static_cast<size_t>(st)
            : 0;
    if (m == 0) {
      return;
    }

    body.vertices.resize(m * 6 * kFloatsPerVertex);
    wick.vertices.resize(m * 2 * kFloatsPerVertex);
    float* bcur = body.vertices.data();
    float* wcur = wick.vertices.data();

    for (size_t ii = lod.begin; ii < lod.end; ii += static_cast<size_t>(st)) {
      const size_t i = ii;
      const NativeCandle& c = candles[i];

      double gapLeft = 0.0;
      double gapRight = 0.0;
      if (i > 0) {
        gapLeft = c.timestamp - candles[i - 1].timestamp;
      } else if (n > 1) {
        gapLeft = candles[1].timestamp - candles[0].timestamp;
      } else {
        gapLeft = 1.0;
      }
      if (i + 1 < n) {
        gapRight = candles[i + 1].timestamp - c.timestamp;
      } else if (n > 1) {
        gapRight = candles[n - 1].timestamp - candles[n - 2].timestamp;
      } else {
        gapRight = 1.0;
      }
      gapLeft = std::max(gapLeft, 1e-18);
      gapRight = std::max(gapRight, 1e-18);
      // Slot width for this index: neighbouring gaps (stable when zoom reveals dense regions).
      const double slot = std::min(gapLeft, gapRight);
      const double halfWidth = slot * fracHalf;

      const bool up = c.close >= c.open;
      const float* col = up ? style.up_color : style.down_color;
      const double bodyLow = std::min(c.open, c.close);
      const double bodyHigh = std::max(c.open, c.close);
      const double lo = bodyLow;
      const double hi =
          (bodyHigh - bodyLow < minBody) ? (bodyLow + minBody) : bodyHigh;
      const double tL = c.timestamp - halfWidth;
      const double tR = c.timestamp + halfWidth;

      emitWorld(bcur, tL, lo, col[0], col[1], col[2], col[3]);
      emitWorld(bcur, tR, lo, col[0], col[1], col[2], col[3]);
      emitWorld(bcur, tR, hi, col[0], col[1], col[2], col[3]);
      emitWorld(bcur, tL, lo, col[0], col[1], col[2], col[3]);
      emitWorld(bcur, tR, hi, col[0], col[1], col[2], col[3]);
      emitWorld(bcur, tL, hi, col[0], col[1], col[2], col[3]);

      emitWorld(wcur, c.timestamp, c.low, col[0], col[1], col[2], col[3]);
      emitWorld(wcur, c.timestamp, c.high, col[0], col[1], col[2], col[3]);
    }
  }

  void buildGridGeometry(PassData& p) {
    p.primitive = CHART_PRIMITIVE_LINES;
    p.vertices.clear();
    if (!style.show_grid || candles.empty()) return;
    if (x_ticks.empty() && y_ticks.empty()) return;

    const double yLo = data_y_min;
    const double yHi = data_y_max;
    const double xLo = data_x_min;
    const double xHi = data_x_max;
    const float* col = style.grid_color;

    p.vertices.resize((x_ticks.size() + y_ticks.size()) * 2 * kFloatsPerVertex);
    float* cur = p.vertices.data();
    if (style.show_x_axis) {
      for (double t : x_ticks) {
        emitWorld(cur, t, yLo, col[0], col[1], col[2], col[3]);
        emitWorld(cur, t, yHi, col[0], col[1], col[2], col[3]);
      }
    }
    if (style.show_y_axis) {
      for (double t : y_ticks) {
        emitWorld(cur, xLo, t, col[0], col[1], col[2], col[3]);
        emitWorld(cur, xHi, t, col[0], col[1], col[2], col[3]);
      }
    }
    // Trim if either axis was disabled.
    const size_t emittedVertices =
        ((style.show_x_axis ? x_ticks.size() : 0) +
         (style.show_y_axis ? y_ticks.size() : 0)) * 2;
    p.vertices.resize(emittedVertices * kFloatsPerVertex);
  }

  void buildCrosshairGeometry(PassData& p) {
    p.primitive = CHART_PRIMITIVE_LINES;
    p.vertices.clear();
    if (!style.show_crosshair) return;
    if (hover_index < 0 || hover_index >= static_cast<int>(candles.size())) return;

    const NativeCandle& c = candles[hover_index];
    const float* col = style.crosshair_color;
    p.vertices.resize(4 * kFloatsPerVertex);  // vertical + horizontal
    float* cur = p.vertices.data();
    // Vertical crosshair at hovered candle's timestamp.
    emitWorld(cur, c.timestamp, data_y_min, col[0], col[1], col[2], col[3]);
    emitWorld(cur, c.timestamp, data_y_max, col[0], col[1], col[2], col[3]);
    // Horizontal crosshair at hovered candle's close.
    emitWorld(cur, data_x_min, c.close, col[0], col[1], col[2], col[3]);
    emitWorld(cur, data_x_max, c.close, col[0], col[1], col[2], col[3]);
  }

  void rebuildGeometry() {
    passes.clear();
    if (candles.empty()) {
      ++generation;
      return;
    }
    recomputeTicks();
    {
      double vxMaxScr, vyMaxScr;
      viewport.getVisibleDomain(&geom_vx_min_, &vxMaxScr);
      viewport.getVisibleRange(&geom_vy_min_, &vyMaxScr);
    }

    if (style.show_grid) {
      PassData grid;
      buildGridGeometry(grid);
      if (!grid.vertices.empty()) passes.push_back(std::move(grid));
    }

    switch (series_type) {
      case CHART_SERIES_LINE: {
        PassData line;
        buildLineGeometry(line);
        if (!line.vertices.empty()) passes.push_back(std::move(line));
        break;
      }
      case CHART_SERIES_AREA: {
        PassData area;
        buildAreaGeometry(area);
        if (!area.vertices.empty()) passes.push_back(std::move(area));
        break;
      }
      case CHART_SERIES_CANDLE:
      default: {
        PassData body, wick;
        buildCandleBodyAndWick(body, wick);
        if (!body.vertices.empty()) passes.push_back(std::move(body));
        if (!wick.vertices.empty()) passes.push_back(std::move(wick));
        break;
      }
    }

    if (style.show_crosshair && hover_index >= 0) {
      PassData crosshair;
      buildCrosshairGeometry(crosshair);
      if (!crosshair.vertices.empty()) passes.push_back(std::move(crosshair));
    }

    ++generation;
  }

  // Binary search for the candle whose timestamp is closest to xData.
  int hitTest(double xData) const {
    if (candles.empty()) return -1;
    int lo = 0;
    int hi = static_cast<int>(candles.size()) - 1;
    if (xData <= candles[lo].timestamp) return lo;
    if (xData >= candles[hi].timestamp) return hi;
    while (hi - lo > 1) {
      const int mid = (lo + hi) / 2;
      if (candles[mid].timestamp < xData) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (xData - candles[lo].timestamp < candles[hi].timestamp - xData) ? lo : hi;
  }
};

namespace chart_engine_live {

inline void FinishPartialUpdate(ChartEngineState* state) {
  state->recomputeDataBounds();
  state->viewport.setDataExtents(state->data_x_min, state->data_x_max,
                                 state->data_y_min, state->data_y_max);
  state->viewport.shiftToLiveEdge(state->data_x_max);
  state->rebuildGeometry();
}

inline void BootstrapFromEmpty(ChartEngineState* state, const NativeCandle& seed) {
  state->candles.push_back(seed);
  state->recomputeDataBounds();
  state->viewport.setDataBounds(state->data_x_min, state->data_x_max,
                                state->data_y_min, state->data_y_max);
  state->rebuildGeometry();
}

}  // namespace chart_engine_live

extern "C" {

CHART_ENGINE_EXPORT void* create_chart_engine(void) {
  try {
    return new ChartEngineState();
  } catch (...) {
    return nullptr;
  }
}

CHART_ENGINE_EXPORT void destroy_chart_engine(void* engine) {
  if (engine == nullptr) return;
  delete static_cast<ChartEngineState*>(engine);
}

CHART_ENGINE_EXPORT void chart_engine_set_style(void* engine, const ChartStyle* style) {
  if (engine == nullptr || style == nullptr) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  state->style = *style;
  // Defensive: always ensure series_label is null-terminated.
  state->style.series_label[sizeof(state->style.series_label) - 1] = '\0';
  ++state->style_revision;
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT void chart_engine_get_default_style(ChartStyle* out_style) {
  if (out_style == nullptr) return;
  *out_style = makeDefaultStyle();
}

CHART_ENGINE_EXPORT void chart_engine_get_style(void* engine, ChartStyle* out_style) {
  if (engine == nullptr || out_style == nullptr) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  *out_style = state->style;
}

CHART_ENGINE_EXPORT long long chart_engine_style_revision(void* engine) {
  if (engine == nullptr) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return state->style_revision;
}

CHART_ENGINE_EXPORT void push_candles(void* engine, NativeCandle* candles, int count) {
  if (engine == nullptr || candles == nullptr || count <= 0) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  state->candles.assign(candles, candles + count);
  state->recomputeDataBounds();
  state->viewport.setDataBounds(state->data_x_min, state->data_x_max,
                                state->data_y_min, state->data_y_max);
  state->hover_index = -1;
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT void push_candles_raw(void* engine, const double* data, int count) {
  if (engine == nullptr || data == nullptr || count <= 0) return;
  static_assert(sizeof(NativeCandle) == 6 * sizeof(double),
                "NativeCandle layout must match flat 6-double array.");
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  state->candles.resize(static_cast<size_t>(count));
  std::memcpy(state->candles.data(), data,
              static_cast<size_t>(count) * sizeof(NativeCandle));
  state->recomputeDataBounds();
  state->viewport.setDataBounds(state->data_x_min, state->data_x_max,
                                state->data_y_min, state->data_y_max);
  state->hover_index = -1;
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT void append_candles_raw(void* engine, const double* data, int count) {
  if (engine == nullptr || data == nullptr || count <= 0) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  const size_t oldSize = state->candles.size();
  state->candles.resize(oldSize + static_cast<size_t>(count));
  std::memcpy(state->candles.data() + oldSize, data,
              static_cast<size_t>(count) * sizeof(NativeCandle));
  state->recomputeDataBounds();
  state->viewport.setDataBounds(state->data_x_min, state->data_x_max,
                                state->data_y_min, state->data_y_max);
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT void chart_engine_set_timeframe(void* engine, double interval_ms) {
  if (engine == nullptr || !(interval_ms > 0.0) || !std::isfinite(interval_ms)) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  state->timeframe_interval_ms = interval_ms;
}

CHART_ENGINE_EXPORT void chart_engine_update_live_tick(void* engine,
                                                       double timestamp,
                                                       double price,
                                                       double volume) {
  if (engine == nullptr) return;
  if (!std::isfinite(timestamp) || !std::isfinite(price)) return;

  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);

  NativeCandle bar{};
  bar.timestamp = timestamp;
  bar.open = bar.high = bar.low = bar.close = price;
  bar.volume = std::isfinite(volume) ? volume : 0.0;

  if (state->candles.empty()) {
    chart_engine_live::BootstrapFromEmpty(state, bar);
    return;
  }

  NativeCandle& last = state->candles.back();
  const double interval = state->timeframe_interval_ms;
  if (timestamp < last.timestamp) return;

  if (timestamp < last.timestamp + interval) {
    last.close = price;
    last.high = std::max(last.high, price);
    last.low = std::min(last.low, price);
    if (std::isfinite(volume)) last.volume += volume;
  } else {
    state->candles.push_back(bar);
  }

  chart_engine_live::FinishPartialUpdate(state);
}

/// Full OHLC for the forming candle (websocket aggregate / venue snapshot).
/// Same bucket semantics as chart_engine_update_live_tick; merges when
/// timestamp is inside `[last.timestamp, last.timestamp + interval)`.
/// \p timestamp should identify the candle period (normally bar open time).
CHART_ENGINE_EXPORT void chart_engine_update_live_ohlc(void* engine,
                                                       double timestamp,
                                                       double open,
                                                       double high,
                                                       double low,
                                                       double close,
                                                       double volume) {
  if (engine == nullptr) return;
  if (!std::isfinite(timestamp)) return;
  if (!std::isfinite(open) || !std::isfinite(high) ||
      !std::isfinite(low) || !std::isfinite(close)) {
    return;
  }

  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);

  NativeCandle bar{};
  bar.timestamp = timestamp;
  bar.open = open;
  bar.high = high;
  bar.low = low;
  bar.close = close;
  bar.volume = std::isfinite(volume) ? volume : 0.0;

  if (state->candles.empty()) {
    chart_engine_live::BootstrapFromEmpty(state, bar);
    return;
  }

  NativeCandle& last = state->candles.back();
  const double interval = state->timeframe_interval_ms;
  if (timestamp < last.timestamp) return;

  if (timestamp < last.timestamp + interval) {
    last.open = open;
    last.high = high;
    last.low = low;
    last.close = close;
    if (std::isfinite(volume)) last.volume = volume;
  } else {
    state->candles.push_back(bar);
  }

  chart_engine_live::FinishPartialUpdate(state);
}

CHART_ENGINE_EXPORT void chart_engine_get_data_bounds(void* engine,
                                                     double* xMin, double* xMax,
                                                     double* yMin, double* yMax) {
  if (engine == nullptr) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  if (xMin) *xMin = state->data_x_min;
  if (xMax) *xMax = state->data_x_max;
  if (yMin) *yMin = state->data_y_min;
  if (yMax) *yMax = state->data_y_max;
}

CHART_ENGINE_EXPORT int chart_engine_candle_count(void* engine) {
  if (engine == nullptr) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return static_cast<int>(state->candles.size());
}

CHART_ENGINE_EXPORT int chart_engine_get_candle(void* engine, int index, NativeCandle* out) {
  if (engine == nullptr || out == nullptr) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  if (index < 0 || index >= static_cast<int>(state->candles.size())) return 0;
  *out = state->candles[static_cast<size_t>(index)];
  return 1;
}

CHART_ENGINE_EXPORT void chart_engine_set_series_type(void* engine, int type) {
  if (engine == nullptr) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  if (type != CHART_SERIES_CANDLE && type != CHART_SERIES_LINE && type != CHART_SERIES_AREA) {
    return;
  }
  if (state->series_type == type) return;
  state->series_type = type;
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT int chart_engine_get_series_type(void* engine) {
  if (engine == nullptr) return -1;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return state->series_type;
}

CHART_ENGINE_EXPORT void* chart_engine_get_viewport(void* engine) {
  if (engine == nullptr) return nullptr;
  return &static_cast<ChartEngineState*>(engine)->viewport;
}

CHART_ENGINE_EXPORT long long chart_engine_viewport_revision(void* engine) {
  if (engine == nullptr) return 0;
  return static_cast<ChartEngineState*>(engine)->viewport.revision();
}

CHART_ENGINE_EXPORT void chart_engine_rebuild_for_viewport(void* engine) {
  if (engine == nullptr) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  if (state->candles.empty()) return;
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT int chart_engine_generation(void* engine) {
  if (engine == nullptr) return -1;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return state->generation;
}

CHART_ENGINE_EXPORT int chart_engine_pass_count(void* engine) {
  if (engine == nullptr) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return static_cast<int>(state->passes.size());
}

CHART_ENGINE_EXPORT int chart_engine_read_pass(void* engine,
                                                int pass,
                                                int* out_primitive,
                                                float* out_buffer,
                                                int out_capacity_floats) {
  if (engine == nullptr || pass < 0) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  if (pass >= static_cast<int>(state->passes.size())) return 0;
  const PassData& p = state->passes[static_cast<size_t>(pass)];
  if (out_primitive) *out_primitive = p.primitive;
  const int total_floats = static_cast<int>(p.vertices.size());
  const int vertex_count = total_floats / kFloatsPerVertex;
  if (out_buffer != nullptr && out_capacity_floats >= total_floats && total_floats > 0) {
    std::memcpy(out_buffer, p.vertices.data(),
                static_cast<size_t>(total_floats) * sizeof(float));
  }
  return vertex_count;
}

CHART_ENGINE_EXPORT int chart_engine_hit_test(void* engine, double xData) {
  if (engine == nullptr) return -1;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return state->hitTest(xData);
}

CHART_ENGINE_EXPORT void chart_engine_set_hover(void* engine, int index) {
  if (engine == nullptr) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  const int clamped = (index < 0) ? -1 :
      (index >= static_cast<int>(state->candles.size()) ? -1 : index);
  if (clamped == state->hover_index) return;
  state->hover_index = clamped;
  state->rebuildGeometry();
}

CHART_ENGINE_EXPORT int chart_engine_get_hover(void* engine) {
  if (engine == nullptr) return -1;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  return state->hover_index;
}

CHART_ENGINE_EXPORT int chart_engine_get_x_ticks(void* engine, double* out, int max_count) {
  if (engine == nullptr || max_count <= 0) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  state->ensureTicksFresh();
  const int n = std::min(max_count, static_cast<int>(state->x_ticks.size()));
  if (out != nullptr) {
    std::memcpy(out, state->x_ticks.data(), static_cast<size_t>(n) * sizeof(double));
  }
  return static_cast<int>(state->x_ticks.size());
}

CHART_ENGINE_EXPORT int chart_engine_get_y_ticks(void* engine, double* out, int max_count) {
  if (engine == nullptr || max_count <= 0) return 0;
  auto* state = static_cast<ChartEngineState*>(engine);
  std::lock_guard<std::mutex> lock(state->mtx);
  state->ensureTicksFresh();
  const int n = std::min(max_count, static_cast<int>(state->y_ticks.size()));
  if (out != nullptr) {
    std::memcpy(out, state->y_ticks.data(), static_cast<size_t>(n) * sizeof(double));
  }
  return static_cast<int>(state->y_ticks.size());
}

CHART_ENGINE_EXPORT void chart_engine_project_x(void* engine,
                                                 const double* in_x, int count,
                                                 double* out_ndc) {
  if (engine == nullptr || in_x == nullptr || out_ndc == nullptr || count <= 0) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  double xMin, xMax;
  state->viewport.getVisibleDomain(&xMin, &xMax);
  const double w = xMax - xMin;
  const double safe = (w == 0.0) ? 1.0 : w;
  for (int i = 0; i < count; ++i) {
    out_ndc[i] = (2.0 * (in_x[i] - xMin) / safe) - 1.0;
  }
}

CHART_ENGINE_EXPORT void chart_engine_project_y(void* engine,
                                                 const double* in_y, int count,
                                                 double* out_ndc) {
  if (engine == nullptr || in_y == nullptr || out_ndc == nullptr || count <= 0) return;
  auto* state = static_cast<ChartEngineState*>(engine);
  double yMin, yMax;
  state->viewport.getVisibleRange(&yMin, &yMax);
  const double h = yMax - yMin;
  const double safe = (h == 0.0) ? 1.0 : h;
  for (int i = 0; i < count; ++i) {
    out_ndc[i] = (2.0 * (in_y[i] - yMin) / safe) - 1.0;
  }
}

}  // extern "C"
