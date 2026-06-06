import 'package:flutter/foundation.dart';

import 'ffi/chart_engine_ffi.dart';
import 'models/candle.dart';
import 'models/chart_style.dart';
import 'models/series_type.dart';
import 'models/trade_line.dart';

/// Public controller bound to a single [NativeChartView].
///
/// Routing rules:
///   * candle data            -> FFI (zero-copy `push_candles_raw`)
///   * series type            -> FFI
///   * style (incl. label)    -> FFI (`chart_engine_set_style`)
///   * hover / tap dismissal  -> FFI (`chart_engine_set_hover`)
///   * native UI sync         -> done natively, by the overlay polling
///                              the engine's `style_revision`,
///                              `viewport_revision`, `generation`,
///                              and `hover`. NOT via MethodChannel.
///
/// The per-view MethodChannel is only ever used once, by [NativeChartView],
/// for the `getEngineHandle` handshake. After that handshake, this
/// controller talks to the engine *exclusively* through `dart:ffi`, and
/// the Flutter main isolate stops being on the chart's hot path.
class ChartController extends ChangeNotifier {
  ChartController({
    ChartStyle? style,
    double? layoutWidth,
    double? layoutHeight,
  }) : _style = style ?? const ChartStyle(),
       _layoutWidth = layoutWidth,
       _layoutHeight = layoutHeight {
    assert(_extentOk(layoutWidth));
    assert(_extentOk(layoutHeight));
  }

  ChartEngineFfi? _engine;
  bool _disposed = false;

  // Queued state, replayed when the engine attaches.
  Float64List? _pendingRaw;
  List<Candle>? _pendingCandles;
  SeriesType? _pendingSeriesType;
  ChartStyle _style;
  double? _pendingTimeframeMs;
  List<TradeLine> _pendingTradeLines = const [];

  /// Fired when the user releases after drawing a segment (via FFI callback).
  void Function(double x1, double y1, double x2, double y2)? onTradeLineDrawEnd;

  /// Optional width for [NativeChartView] in **logical pixels**. Null lets
  /// the parent supply horizontal constraints only.
  double? _layoutWidth;

  /// Optional height for [NativeChartView] in **logical pixels**. Null lets
  /// the parent supply vertical constraints only.
  double? _layoutHeight;

  double? get layoutWidth => _layoutWidth;
  double? get layoutHeight => _layoutHeight;

  bool get isAttached => _engine != null;

  SeriesType get seriesType =>
      _pendingSeriesType ?? _engine?.seriesType ?? SeriesType.candlestick;

  ChartStyle get style => _style;

  static bool _extentOk(double? value) =>
      value == null || (value.isFinite && value >= 0);

  /// Internal: bind to a native engine handle reported by the PlatformView.
  /// `viewId` is accepted for symmetry but no longer used — there is no
  /// per-view MethodChannel on the controller side now that all updates
  /// flow via FFI.
  @protected
  void attachHandle(int handle, int viewId) {
    if (_disposed) return;
    _engine?.dispose();
    _engine = ChartEngineFfi.fromHandle(handle);

    final raw = _pendingRaw;
    final candles = _pendingCandles;
    if (raw != null) {
      _engine!.pushCandlesRaw(raw);
    } else if (candles != null) {
      _engine!.pushCandles(candles);
    }
    if (_pendingSeriesType != null) {
      _engine!.setSeriesType(_pendingSeriesType!);
    }
    // Style push covers every visual concern, including the series label —
    // the native overlay reads it back via `chart_engine_get_style` on
    // its own (Choreographer / CADisplayLink driven) polling loop.
    _engine!.setStyle(_style);
    if (_pendingTimeframeMs != null) {
      _engine!.setTimeframeIntervalMs(_pendingTimeframeMs!);
    }
    _engine!.syncTradeLines(_pendingTradeLines);
    _engine!.setTradeLineDrawEndCallback(_dispatchTradeLineDrawEnd);
    _engine!.requestTradeLineDrawCancel();
    notifyListeners();
  }

  void _dispatchTradeLineDrawEnd(double x1, double y1, double x2, double y2) {
    onTradeLineDrawEnd?.call(x1, y1, x2, y2);
  }

  @protected
  void detachHandle() {
    if (_disposed) return;
    _engine?.setTradeLineDrawEndCallback(null);
    _engine?.dispose();
    _engine = null;
    notifyListeners();
  }

  // ------------------------- Public API -------------------------

  /// Zero-copy ingestion. Engine memcpy-copies the buffer in a single shot.
  /// Recommended for streaming / large datasets.
  ///
  /// Layout: `[t0, o0, h0, l0, c0, v0, t1, ...]` (6 doubles per candle).
  ///
  /// For true zero memory spike on streaming data, hold a single
  /// [Float64List] and overwrite in place each tick.
  void pushCandlesRaw(Float64List data) {
    if (_disposed) throw StateError('ChartController disposed');
    if (data.length % 6 != 0) {
      throw ArgumentError(
        'data length (${data.length}) must be a multiple of 6',
      );
    }
    _pendingRaw = data;
    _pendingCandles = null;
    _engine?.pushCandlesRaw(data);
  }

  /// Convenience for `List<Candle>`. Packs into the engine's persistent
  /// staging buffer with no per-push allocation after the first call.
  void loadCandles(List<Candle> candles) {
    if (_disposed) throw StateError('ChartController disposed');
    _pendingCandles = List<Candle>.unmodifiable(candles);
    _pendingRaw = null;
    _engine?.pushCandles(candles);
  }

  /// Switches the GPU series geometry (candle / line / area) and updates
  /// the engine-side series label to match. Users that want a custom
  /// legend label should call [setStyle] with `copyWith(seriesLabel: ...)`
  /// afterwards.
  void setSeriesType(SeriesType type) {
    if (_disposed) throw StateError('ChartController disposed');
    _pendingSeriesType = type;
    _engine?.setSeriesType(type);
    final newStyle = _style.copyWith(seriesLabel: type.name.toUpperCase());
    if (newStyle.seriesLabel != _style.seriesLabel) {
      _style = newStyle;
      _engine?.setStyle(_style);
    }
    notifyListeners();
  }

  /// Updates the chart style. The entire visual configuration (colors,
  /// paddings, geometry, toggles, tick density, formatting, series label)
  /// is shipped to the engine via a single FFI call. The native overlay
  /// (axis labels, legend, tooltip) repaints itself on its own when it
  /// notices the engine's `style_revision` changed — Flutter main thread
  /// is never involved.
  void setStyle(ChartStyle style) {
    if (_disposed) throw StateError('ChartController disposed');
    _style = style;
    _engine?.setStyle(style);
    notifyListeners();
  }

  /// Clears any active hover/tooltip on the native side.
  void clearHover() {
    _engine?.setHover(-1);
  }

  /// Width for [NativeChartView] in **logical pixels**. Null yields
  /// width from parent constraints only.
  void setLayoutWidth(double? width) {
    if (_disposed) throw StateError('ChartController disposed');
    if (!_extentOk(width)) {
      throw ArgumentError.value(
        width,
        'width',
        'must be null, zero, or finite',
      );
    }
    if (_layoutWidth != width) {
      _layoutWidth = width;
      notifyListeners();
    }
  }

  /// Height for [NativeChartView] in **logical pixels**. Null yields
  /// height from parent constraints only.
  void setLayoutHeight(double? height) {
    if (_disposed) throw StateError('ChartController disposed');
    if (!_extentOk(height)) {
      throw ArgumentError.value(
        height,
        'height',
        'must be null, zero, or finite',
      );
    }
    if (_layoutHeight != height) {
      _layoutHeight = height;
      notifyListeners();
    }
  }

  /// Candle bucket width for [updateLivePrice]. Mirrors the native default
  /// (`60000`) until you override.
  void setTimeframe(Duration interval) {
    if (_disposed) throw StateError('ChartController disposed');
    final ms = interval.inMicroseconds / 1000.0;
    if (ms <= 0 || !ms.isFinite) {
      throw ArgumentError.value(
        interval,
        'interval',
        'must be positive and finite',
      );
    }
    _pendingTimeframeMs = ms;
    _engine?.setTimeframeIntervalMs(ms);
  }

  /// High-frequency **trade quote** path: mutates OHLC (**open** unchanged,
  /// **price** refreshes **close** and pushes **high**/**low**) for candle
  /// mode; **line**/**area** redraw from **close** only.
  void updateLivePrice({
    required double price,
    required double timestamp,
    double volume = 0,
  }) {
    if (_disposed) throw StateError('ChartController disposed');
    final e = _engine;
    if (e == null) {
      throw StateError('ChartController not attached to a native chart');
    }
    e.updateLiveTick(timestamp: timestamp, price: price, volume: volume);
  }

  /// Full OHLCV when upstream already aggregates bars (**candles** use all
  /// fields; **line**/**area** still plot **close**).
  /// Renders two-point trade/trend segments and clears any stale draw preview.
  void setTradeLines(List<TradeLine> lines) {
    if (_disposed) throw StateError('ChartController disposed');
    _pendingTradeLines = List<TradeLine>.unmodifiable(lines);
    _engine?.syncTradeLines(lines);
    notifyListeners();
  }

  /// Clears an in-progress native draw session (preview + gesture flags).
  void clearTradeLineDrawing() {
    if (_disposed) return;
    _engine?.requestTradeLineDrawCancel();
  }

  void updateLiveOhlc({
    required double timestamp,
    required double open,
    required double high,
    required double low,
    required double close,
    double volume = 0,
  }) {
    if (_disposed) throw StateError('ChartController disposed');
    final e = _engine;
    if (e == null) {
      throw StateError('ChartController not attached to a native chart');
    }
    e.updateLiveOhlc(
      timestamp: timestamp,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _engine?.dispose();
    _engine = null;
    super.dispose();
  }
}

extension ChartControllerInternal on ChartController {
  void attachHandleInternal(int handle, int viewId) =>
      attachHandle(handle, viewId);
  void detachHandleInternal() => detachHandle();
}
