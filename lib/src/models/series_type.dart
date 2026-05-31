/// Native chart series type. Values intentionally match the
/// corresponding C enum values in `native_chart_types.h`.
enum SeriesType {
  /// Candlestick series:OHLC data points.
  candlestick(0),

  /// Line series: single-line data points.
  line(1),

  /// Bar series:OHLC-like data points presented as bars.
  bar(2);

  const SeriesType(this.nativeValue);
  final int nativeValue;
}
