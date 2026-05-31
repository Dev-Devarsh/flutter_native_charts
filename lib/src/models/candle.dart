/// Immutable OHLCV candle. Fields use [double] to match the native ABI exactly
/// (`NativeCandle` in `chart_engine_ffi.h`).
class Candle {
  const Candle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final double timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
}
