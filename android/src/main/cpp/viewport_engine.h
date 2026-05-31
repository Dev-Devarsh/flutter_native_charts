#pragma once

#include <mutex>

/// Phase 5: Native viewport math.
///
/// Holds the visible data domain (X) and range (Y), supports pan/zoom in NDC
/// space, and produces a column-major mat4 that the shaders use to project
/// data coordinates into NDC.
///
/// Thread-safe: gestures arrive on the UI thread, the renderer reads on the
/// GL/Metal thread. All mutating and accessing methods take an internal mutex.
class ViewportEngine {
 public:
  ViewportEngine();

  /// Sets the full data extent and resets the visible window to match it.
  /// Re-enables live-edge tracking (bulk history load / reset semantics).
  void setDataBounds(double xMin, double xMax, double yMin, double yMax);

  /// Updates clamp extents only; preserves the current visible domain (used
  /// for live ticks so pan/zoom context is not destroyed).
  void setDataExtents(double xMin, double xMax, double yMin, double yMax);

  /// When live-edge tracking is enabled and `new_data_x_max` advances the
  /// padded X extent, pans the visible X window by the same delta so the
  /// newest data stays in view. Always refreshes the internal X-max anchor.
  void shiftToLiveEdge(double new_data_x_max);

  /// Pan the visible window in NDC ("follow finger") on both axes.
  /// Positive dxNDC shifts data right; positive dyNDC shifts data down in view.
  void panNDC(double dxNDC, double dyNDC);

  /// Zoom around a focus point in NDC. scale > 1 zooms in (smaller visible
  /// window); 0 < scale < 1 zooms out.
  void zoomNDC(double scaleX, double scaleY, double focusXNDC, double focusYNDC);

  /// Resets the visible window to the data bounds.
  void reset();

  /// Fills a column-major 4x4 projection matrix mapping data (x, y, 0, 1) to NDC.
  void getProjectionMatrix(float out16[16]) const;

  void getVisibleDomain(double* xMin, double* xMax) const;
  void getVisibleRange(double* yMin, double* yMax) const;

  /// Monotonically incremented on every mutating op (setDataBounds, pan,
  /// zoom, reset). Native UI overlays cache the last seen value and only
  /// repaint when it changes — keeps text labels in sync with pan/zoom
  /// without polling on every frame.
  long long revision() const;

 private:
  mutable std::mutex mtx_;
  double data_x_min_;
  double data_x_max_;
  double data_y_min_;
  double data_y_max_;
  double vis_x_min_;
  double vis_x_max_;
  double vis_y_min_;
  double vis_y_max_;
  long long revision_;

  void clampVisibleToData_();

  bool tracking_live_edge_;
  double last_known_padded_x_max_;
};
