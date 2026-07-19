import 'dart:convert' show utf8;
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:ffi/ffi.dart';

import '../models/candle.dart';
import '../models/chart_style.dart';
import '../models/series_type.dart';

final class NativeCandle extends ffi.Struct {
  @ffi.Double()
  external double timestamp;

  @ffi.Double()
  external double open;

  @ffi.Double()
  external double high;

  @ffi.Double()
  external double low;

  @ffi.Double()
  external double close;

  @ffi.Double()
  external double volume;
}

typedef _PushCandlesRawNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Void> engine,
      ffi.Pointer<ffi.Double> data,
      ffi.Int32 count,
    );
typedef _PushCandlesRawDart =
    void Function(
      ffi.Pointer<ffi.Void> engine,
      ffi.Pointer<ffi.Double> data,
      int count,
    );

typedef _SetSeriesTypeNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> engine, ffi.Int32 type);
typedef _SetSeriesTypeDart =
    void Function(ffi.Pointer<ffi.Void> engine, int type);

typedef _GetSeriesTypeNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> engine);
typedef _GetSeriesTypeDart = int Function(ffi.Pointer<ffi.Void> engine);

typedef _SetHoverNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> engine, ffi.Int32 index);
typedef _SetHoverDart = void Function(ffi.Pointer<ffi.Void> engine, int index);

typedef _SetTimeframeNative =
    ffi.Void Function(ffi.Pointer<ffi.Void> engine, ffi.Double intervalMs);
typedef _SetTimeframeDart =
    void Function(ffi.Pointer<ffi.Void> engine, double intervalMs);

typedef _UpdateLiveTickNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Void> engine,
      ffi.Double timestamp,
      ffi.Double price,
      ffi.Double volume,
    );
typedef _UpdateLiveTickDart =
    void Function(
      ffi.Pointer<ffi.Void> engine,
      double timestamp,
      double price,
      double volume,
    );

typedef _UpdateLiveOhlcNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Void> engine,
      ffi.Double timestamp,
      ffi.Double open,
      ffi.Double high,
      ffi.Double low,
      ffi.Double close,
      ffi.Double volume,
    );
typedef _UpdateLiveOhlcDart =
    void Function(
      ffi.Pointer<ffi.Void> engine,
      double timestamp,
      double open,
      double high,
      double low,
      double close,
      double volume,
    );

typedef _SetStyleNative =
    ffi.Void Function(
      ffi.Pointer<ffi.Void> engine,
      ffi.Pointer<NativeChartStyle> style,
    );
typedef _SetStyleDart =
    void Function(
      ffi.Pointer<ffi.Void> engine,
      ffi.Pointer<NativeChartStyle> style,
    );

/// FFI mirror of the C `ChartStyle` struct. Keep field order, types, and
/// counts identical to chart_engine_ffi.h.
final class NativeChartStyle extends ffi.Struct {
  @ffi.Array(4)
  external ffi.Array<ffi.Float> bgColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> gridColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> axisTextColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> upColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> downColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> lineColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> areaTopColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> areaBottomColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> crosshairColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> tooltipBgColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> tooltipTextColor;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> legendTextColor;

  @ffi.Float()
  external double candleBodyWidthFraction;
  @ffi.Float()
  external double lineWidthPx;
  @ffi.Float()
  external double wickWidthPx;
  @ffi.Float()
  external double crosshairWidthPx;

  @ffi.Float()
  external double xPadFraction;
  @ffi.Float()
  external double yPadFraction;

  @ffi.Int32()
  external int showGrid;
  @ffi.Int32()
  external int showXAxis;
  @ffi.Int32()
  external int showYAxis;
  @ffi.Int32()
  external int showCrosshair;
  @ffi.Int32()
  external int showTooltip;
  @ffi.Int32()
  external int showLegend;

  @ffi.Int32()
  external int approxXTicks;
  @ffi.Int32()
  external int approxYTicks;

  @ffi.Int32()
  external int yDecimals;
  @ffi.Int32()
  external int xIsTimestampMs;

  @ffi.Int32()
  external int allowPanX;
  @ffi.Int32()
  external int allowPanY;
  @ffi.Int32()
  external int allowZoomX;
  @ffi.Int32()
  external int allowZoomY;

  /// UTF-8, null-terminated. Max 31 chars + '\0'. Lives in the style struct
  /// so the series label flows Dart -> engine -> native overlay via a
  /// single FFI call (no MethodChannel hop, no Flutter main-thread work).
  @ffi.Array(32)
  external ffi.Array<ffi.Uint8> seriesLabel;

  @ffi.Int32()
  external int showCurrentPriceLine;
  @ffi.Array(4)
  external ffi.Array<ffi.Float> currentPriceLineColor;

  @ffi.Int32()
  external int doubleTapToReset;
}

ffi.DynamicLibrary _openChartEngineLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libchart_engine.so');
  }
  if (Platform.isIOS) {
    return ffi.DynamicLibrary.process();
  }
  throw UnsupportedError(
    'ChartEngineFfi is only supported on Android and iOS.',
  );
}

/// FFI wrapper around the native chart engine.
///
/// Most users don't use this class directly — `ChartController` does. The
/// engine pointer is owned by the native PlatformView, not by Dart; this
/// class is a borrowed view onto it.
class ChartEngineFfi {
  /// Wraps an existing engine pointer. Caller retains ownership; `dispose`
  /// does not free the engine.
  factory ChartEngineFfi.fromHandle(int handle) {
    if (handle == 0) {
      throw ArgumentError.value(handle, 'handle', 'must not be zero');
    }
    final lib = _openChartEngineLibrary();
    final engine = ffi.Pointer<ffi.Void>.fromAddress(handle);
    return ChartEngineFfi._(lib, engine);
  }

  ChartEngineFfi._(this._lib, this._engine) {
    _pushCandlesRaw = _lib
        .lookupFunction<_PushCandlesRawNative, _PushCandlesRawDart>(
          'push_candles_raw',
        );
    _appendCandlesRaw = _lib
        .lookupFunction<_PushCandlesRawNative, _PushCandlesRawDart>(
          'append_candles_raw',
        );
    _setSeriesType = _lib
        .lookupFunction<_SetSeriesTypeNative, _SetSeriesTypeDart>(
          'chart_engine_set_series_type',
        );
    _getSeriesType = _lib
        .lookupFunction<_GetSeriesTypeNative, _GetSeriesTypeDart>(
          'chart_engine_get_series_type',
        );
    _setHover = _lib.lookupFunction<_SetHoverNative, _SetHoverDart>(
      'chart_engine_set_hover',
    );
    _setTimeframe = _lib.lookupFunction<_SetTimeframeNative, _SetTimeframeDart>(
      'chart_engine_set_timeframe',
    );
    _updateLiveTick = _lib
        .lookupFunction<_UpdateLiveTickNative, _UpdateLiveTickDart>(
          'chart_engine_update_live_tick',
        );
    _updateLiveOhlc = _lib
        .lookupFunction<_UpdateLiveOhlcNative, _UpdateLiveOhlcDart>(
          'chart_engine_update_live_ohlc',
        );
    _setStyle = _lib.lookupFunction<_SetStyleNative, _SetStyleDart>(
      'chart_engine_set_style',
    );
  }

  final ffi.DynamicLibrary _lib;
  final ffi.Pointer<ffi.Void> _engine;

  late final _PushCandlesRawDart _pushCandlesRaw;
  late final _PushCandlesRawDart _appendCandlesRaw;
  late final _SetSeriesTypeDart _setSeriesType;
  late final _GetSeriesTypeDart _getSeriesType;
  late final _SetHoverDart _setHover;
  late final _SetTimeframeDart _setTimeframe;
  late final _UpdateLiveTickDart _updateLiveTick;
  late final _UpdateLiveOhlcDart _updateLiveOhlc;
  late final _SetStyleDart _setStyle;

  bool _disposed = false;

  // ---------------- Persistent FFI staging buffer ----------------
  //
  // Avoids per-push allocation. Grows monotonically. Freed only when this
  // ChartEngineFfi instance is disposed.
  ffi.Pointer<ffi.Double> _scratch = ffi.nullptr;
  Float64List _scratchView = Float64List(0);
  int _scratchCapacityDoubles = 0;

  int get handle => _engine.address;

  void _ensureScratch(int doubles) {
    if (_scratchCapacityDoubles >= doubles) return;
    if (_scratchCapacityDoubles > 0) {
      malloc.free(_scratch);
    }
    // Round capacity up to power of 2 (min 64KB).
    int newCap = 1024;
    while (newCap < doubles) {
      newCap <<= 1;
    }
    _scratch = malloc<ffi.Double>(newCap);
    _scratchView = _scratch.asTypedList(newCap);
    _scratchCapacityDoubles = newCap;
  }

  /// Zero-copy candle ingestion. `data` MUST be 6*N doubles laid out as
  /// `[t0, o0, h0, l0, c0, v0, t1, ...]`.
  ///
  /// One bulk `setRange` from the caller's `Float64List` into the engine's
  /// scratch buffer, then a single FFI call. The engine performs one memcpy
  /// internally and rebuilds geometry. No per-candle Dart-side allocations.
  void pushCandlesRaw(Float64List data) {
    if (_disposed) throw StateError('ChartEngineFfi disposed');
    if (data.isEmpty) return;
    if (data.length % 6 != 0) {
      throw ArgumentError(
        'data length (${data.length}) must be a multiple of 6',
      );
    }
    _ensureScratch(data.length);
    _scratchView.setRange(0, data.length, data);
    _pushCandlesRaw(_engine, _scratch, data.length ~/ 6);
  }

  /// Convenience wrapper that packs a `List<Candle>` into the scratch buffer
  /// and pushes. Allocations are bounded by the persistent scratch buffer;
  /// no GC pressure beyond the caller's list.
  void pushCandles(List<Candle> candles) {
    if (_disposed) throw StateError('ChartEngineFfi disposed');
    final n = candles.length;
    if (n == 0) return;
    _ensureScratch(n * 6);
    final view = _scratchView;
    for (int i = 0; i < n; i++) {
      final c = candles[i];
      final base = i * 6;
      view[base] = c.timestamp;
      view[base + 1] = c.open;
      view[base + 2] = c.high;
      view[base + 3] = c.low;
      view[base + 4] = c.close;
      view[base + 5] = c.volume;
    }
    _pushCandlesRaw(_engine, _scratch, n);
  }

  /// Appends candles to the engine buffer; same layout as [pushCandlesRaw].
  void appendCandlesRaw(Float64List data) {
    if (_disposed) throw StateError('ChartEngineFfi disposed');
    if (data.isEmpty) return;
    if (data.length % 6 != 0) {
      throw ArgumentError(
        'data length (${data.length}) must be a multiple of 6',
      );
    }
    _ensureScratch(data.length);
    _scratchView.setRange(0, data.length, data);
    _appendCandlesRaw(_engine, _scratch, data.length ~/ 6);
  }

  void setSeriesType(SeriesType type) {
    if (_disposed) return;
    _setSeriesType(_engine, type.nativeValue);
  }

  SeriesType get seriesType {
    if (_disposed) return SeriesType.candlestick;
    final raw = _getSeriesType(_engine);
    return SeriesType.values.firstWhere(
      (t) => t.nativeValue == raw,
      orElse: () => SeriesType.candlestick,
    );
  }

  void setHover(int index) {
    if (_disposed) return;
    _setHover(_engine, index);
  }

  /// Live bar width in milliseconds (OHLC bucket). Must be positive.
  void setTimeframeIntervalMs(double intervalMs) {
    if (_disposed) return;
    if (intervalMs <= 0 || !intervalMs.isFinite) return;
    _setTimeframe(_engine, intervalMs);
  }

  /// Single-trade path (**all series types**): updates **high / low / close**
  /// from **price** inside the forming bucket (**open** unchanged). Volume
  /// accumulates while in-bucket.
  ///
  /// **Rendering:** **candles** use full OHLC; **line** and **area** read
  /// **close** only (same backing `NativeCandle` buffer).
  void updateLiveTick({
    required double timestamp,
    required double price,
    double volume = 0,
  }) {
    if (_disposed) throw StateError('ChartEngineFfi disposed');
    _updateLiveTick(_engine, timestamp, price, volume);
  }

  /// Full OHLCV snapshot for the forming or next candle (venue aggregate /
  /// consolidated feeds). Prefer over [updateLiveTick] when the stream
  /// already computes **open / high / low / close**.
  void updateLiveOhlc({
    required double timestamp,
    required double open,
    required double high,
    required double low,
    required double close,
    double volume = 0,
  }) {
    if (_disposed) throw StateError('ChartEngineFfi disposed');
    _updateLiveOhlc(_engine, timestamp, open, high, low, close, volume);
  }

  /// Push the visual configuration to the engine. Affects geometry colors,
  /// paddings, candle width, tick density, visibility toggles.
  void setStyle(ChartStyle style) {
    if (_disposed) return;
    final ptr = calloc<NativeChartStyle>();
    try {
      final s = ptr.ref;
      _writeColor(s.bgColor, style.bgColor);
      _writeColor(s.gridColor, style.gridColor);
      _writeColor(s.axisTextColor, style.axisTextColor);
      _writeColor(s.upColor, style.upColor);
      _writeColor(s.downColor, style.downColor);
      _writeColor(s.lineColor, style.lineColor);
      _writeColor(s.areaTopColor, style.areaTopColor);
      _writeColor(s.areaBottomColor, style.areaBottomColor);
      _writeColor(s.crosshairColor, style.crosshairColor);
      _writeColor(s.tooltipBgColor, style.tooltipBgColor);
      _writeColor(s.tooltipTextColor, style.tooltipTextColor);
      _writeColor(s.legendTextColor, style.legendTextColor);

      s.candleBodyWidthFraction = style.candleBodyWidthFraction;
      s.lineWidthPx = style.lineWidthPx;
      s.wickWidthPx = style.wickWidthPx;
      s.crosshairWidthPx = style.crosshairWidthPx;
      s.xPadFraction = style.xPadFraction;
      s.yPadFraction = style.yPadFraction;

      s.showGrid = style.showGrid ? 1 : 0;
      s.showXAxis = style.showXAxis ? 1 : 0;
      s.showYAxis = style.showYAxis ? 1 : 0;
      s.showCrosshair = style.showCrosshair ? 1 : 0;
      s.showTooltip = style.showTooltip ? 1 : 0;
      s.showLegend = style.showLegend ? 1 : 0;

      s.approxXTicks = style.approxXTicks;
      s.approxYTicks = style.approxYTicks;

      s.yDecimals = style.yDecimals;
      s.xIsTimestampMs = style.xIsTimestampMs ? 1 : 0;

      s.allowPanX = style.allowPanX ? 1 : 0;
      s.allowPanY = style.allowPanY ? 1 : 0;
      s.allowZoomX = style.allowZoomX ? 1 : 0;
      s.allowZoomY = style.allowZoomY ? 1 : 0;

      _writeSeriesLabel(s.seriesLabel, style.seriesLabel);

      s.showCurrentPriceLine = style.showCurrentPriceLine ? 1 : 0;
      _writeColor(s.currentPriceLineColor, style.currentPriceLineColor);

      s.doubleTapToReset = style.doubleTapToReset ? 1 : 0;

      _setStyle(_engine, ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  static void _writeColor(ffi.Array<ffi.Float> arr, Color c) {
    // Color components are doubles in [0, 1] in Flutter; struct expects float.
    arr[0] = c.r;
    arr[1] = c.g;
    arr[2] = c.b;
    arr[3] = c.a;
  }

  /// Writes a UTF-8, null-terminated copy of [label] into the fixed-size
  /// [arr] (32 bytes). Truncates to 31 bytes if necessary. Zero-pads the
  /// remainder so the C side always reads a clean C-string.
  static void _writeSeriesLabel(ffi.Array<ffi.Uint8> arr, String label) {
    final encoded = utf8.encode(label);
    const int capacity = 32;
    final int maxBytes = (encoded.length < capacity - 1)
        ? encoded.length
        : capacity - 1;
    for (int i = 0; i < maxBytes; i++) {
      arr[i] = encoded[i];
    }
    for (int i = maxBytes; i < capacity; i++) {
      arr[i] = 0;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_scratchCapacityDoubles > 0) {
      malloc.free(_scratch);
      _scratch = ffi.nullptr;
      _scratchCapacityDoubles = 0;
      _scratchView = Float64List(0);
    }
  }
}
