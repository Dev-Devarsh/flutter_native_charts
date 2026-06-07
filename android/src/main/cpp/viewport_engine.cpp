#include "viewport_engine.h"

#include <algorithm>

#include <cstring>

namespace {
constexpr double kMinScale = 1e-6;
}  // namespace

ViewportEngine::ViewportEngine()
    : data_x_min_(-1.0),
      data_x_max_(1.0),
      data_y_min_(-1.0),
      data_y_max_(1.0),
      vis_x_min_(-1.0),
      vis_x_max_(1.0),
      vis_y_min_(-1.0),
      vis_y_max_(1.0),
      revision_(0),
      tracking_live_edge_(true),
      last_known_padded_x_max_(1.0) {}

void ViewportEngine::setDataBounds(double xMin, double xMax, double yMin, double yMax) {
  if (xMin >= xMax || yMin >= yMax) {
    return;
  }
  std::lock_guard<std::mutex> lock(mtx_);
  data_x_min_ = xMin;
  data_x_max_ = xMax;
  data_y_min_ = yMin;
  data_y_max_ = yMax;
  vis_x_min_ = xMin;
  vis_x_max_ = xMax;
  vis_y_min_ = yMin;
  vis_y_max_ = yMax;
  tracking_live_edge_ = true;
  last_known_padded_x_max_ = xMax;
  ++revision_;
}

void ViewportEngine::setDataExtents(double xMin, double xMax, double yMin, double yMax) {
  if (xMin >= xMax || yMin >= yMax) {
    return;
  }
  std::lock_guard<std::mutex> lock(mtx_);
  data_x_min_ = xMin;
  data_x_max_ = xMax;
  data_y_min_ = yMin;
  data_y_max_ = yMax;
  clampVisibleToData_();
  ++revision_;
}

void ViewportEngine::shiftToLiveEdge(double new_data_x_max) {
  std::lock_guard<std::mutex> lock(mtx_);
  if (tracking_live_edge_) {
    const double dx = new_data_x_max - last_known_padded_x_max_;
    if (dx != 0.0) {
      vis_x_min_ += dx;
      vis_x_max_ += dx;
      clampVisibleToData_();
      ++revision_;
    }
  }
  last_known_padded_x_max_ = new_data_x_max;
}

void ViewportEngine::panNDC(double dxNDC, double dyNDC) {
  std::lock_guard<std::mutex> lock(mtx_);
  tracking_live_edge_ = false;
  const double dxData = -dxNDC * (vis_x_max_ - vis_x_min_) * 0.5;
  const double dyData = -dyNDC * (vis_y_max_ - vis_y_min_) * 0.5;
  vis_x_min_ += dxData;
  vis_x_max_ += dxData;
  vis_y_min_ += dyData;
  vis_y_max_ += dyData;
  clampVisibleToData_();
  ++revision_;
}

void ViewportEngine::zoomNDC(double scaleX, double scaleY, double focusXNDC, double focusYNDC) {
  if (scaleX < kMinScale || scaleY < kMinScale) {
    return;
  }
  std::lock_guard<std::mutex> lock(mtx_);
  tracking_live_edge_ = false;
  const double cx = (vis_x_max_ + vis_x_min_) * 0.5;
  const double hx = (vis_x_max_ - vis_x_min_) * 0.5;
  const double cy = (vis_y_max_ + vis_y_min_) * 0.5;
  const double hy = (vis_y_max_ - vis_y_min_) * 0.5;

  const double focusXData = cx + focusXNDC * hx;
  const double focusYData = cy + focusYNDC * hy;

  double next_vis_x_min = focusXData - (focusXData - vis_x_min_) / scaleX;
  double next_vis_x_max = focusXData + (vis_x_max_ - focusXData) / scaleX;
  double next_vis_y_min = focusYData - (focusYData - vis_y_min_) / scaleY;
  double next_vis_y_max = focusYData + (vis_y_max_ - focusYData) / scaleY;

  // Restrict Y axis zoom when Y axis label decimal point exceeds 3 digits
  // 3 decimal places correspond to a step of 0.001, so minimum visible range for 5 ticks is ~0.005.
  if (next_vis_y_max - next_vis_y_min < 0.005) {
    if (next_vis_y_max - next_vis_y_min < vis_y_max_ - vis_y_min_) {
      next_vis_y_min = vis_y_min_;
      next_vis_y_max = vis_y_max_;
    }
  }

  vis_x_min_ = next_vis_x_min;
  vis_x_max_ = next_vis_x_max;
  vis_y_min_ = next_vis_y_min;
  vis_y_max_ = next_vis_y_max;

  clampVisibleToData_();
  ++revision_;
}

void ViewportEngine::reset() {
  std::lock_guard<std::mutex> lock(mtx_);
  vis_x_min_ = data_x_min_;
  vis_x_max_ = data_x_max_;
  vis_y_min_ = data_y_min_;
  vis_y_max_ = data_y_max_;
  tracking_live_edge_ = true;
  last_known_padded_x_max_ = data_x_max_;
  ++revision_;
}

long long ViewportEngine::revision() const {
  std::lock_guard<std::mutex> lock(mtx_);
  return revision_;
}

void ViewportEngine::getProjectionMatrix(float out16[16]) const {
  std::lock_guard<std::mutex> lock(mtx_);
  const double w = vis_x_max_ - vis_x_min_;
  const double h = vis_y_max_ - vis_y_min_;
  const double safe_w = (w == 0.0) ? 1.0 : w;
  const double safe_h = (h == 0.0) ? 1.0 : h;

  // Vertices use coordinates relative to the visible min (vxMin, vyMin). With
  // rel_x = wx - vxMin, ndc_x = (2/w)*rel_x - 1, i.e. scale 2/w and translation -1.
  const double sx = 2.0 / safe_w;
  const double sy = 2.0 / safe_h;

  std::memset(out16, 0, sizeof(float) * 16);
  out16[0] = static_cast<float>(sx);
  out16[5] = static_cast<float>(sy);
  out16[10] = 1.0f;
  out16[12] = -1.0f;
  out16[13] = -1.0f;
  out16[15] = 1.0f;
}

void ViewportEngine::getVisibleDomain(double* xMin, double* xMax) const {
  std::lock_guard<std::mutex> lock(mtx_);
  if (xMin) *xMin = vis_x_min_;
  if (xMax) *xMax = vis_x_max_;
}

void ViewportEngine::getVisibleRange(double* yMin, double* yMax) const {
  std::lock_guard<std::mutex> lock(mtx_);
  if (yMin) *yMin = vis_y_min_;
  if (yMax) *yMax = vis_y_max_;
}

void ViewportEngine::clampVisibleToData_() {
  auto clamp_axis = [](double dmin, double dmax, double& vmin, double& vmax) {
    const double dlen = std::max(1e-18, dmax - dmin);
    const double span = std::max(1e-18, vmax - vmin);
    if (span >= dlen) {
      vmin = dmin;
      vmax = dmax;
      return;
    }
    if (vmin < dmin) {
      vmin = dmin;
      vmax = dmin + span;
    }
    if (vmax > dmax) {
      vmax = dmax;
      vmin = dmax - span;
    }
    if (vmin < dmin) {
      vmin = dmin;
    }
  };

  clamp_axis(data_x_min_, data_x_max_, vis_x_min_, vis_x_max_);
  clamp_axis(data_y_min_, data_y_max_, vis_y_min_, vis_y_max_);
}
