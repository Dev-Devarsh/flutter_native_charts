import 'package:flutter/material.dart';
import 'package:flutter_native_charts/flutter_native_charts.dart';

/// One of six example flows: series type × data feed vs live.
enum DemoKind {
  candleDataFeed,
  candleLive,
  areaDataFeed,
  areaLive,
  lineDataFeed,
  lineLive,
}

extension DemoKindX on DemoKind {
  String get title => switch (this) {
    DemoKind.candleDataFeed => 'Candle · Data feed',
    DemoKind.candleLive => 'Candle · Live',
    DemoKind.areaDataFeed => 'Area · Data feed',
    DemoKind.areaLive => 'Area · Live',
    DemoKind.lineDataFeed => 'Line · Data feed',
    DemoKind.lineLive => 'Line · Live',
  };

  String get description => switch (this) {
    DemoKind.candleDataFeed =>
      'OHLC candlesticks loaded in one shot via pushCandlesRaw (180 bars). Pan and zoom to explore history.',
    DemoKind.candleLive =>
      'Starts with a short history, then streams ticks through updateLivePrice over FFI (1-minute buckets).',
    DemoKind.areaDataFeed =>
      'Gradient area chart filled from a bulk pushCandlesRaw snapshot. Close drives the filled region.',
    DemoKind.areaLive =>
      'Area series with live close updates via updateLivePrice as new trades arrive.',
    DemoKind.lineDataFeed =>
      'Line stroke from a single bulk FFI load. Ideal for static close-price series.',
    DemoKind.lineLive =>
      'Line series fed by updateLivePrice — only close moves; open/high/low ignored for drawing.',
  };

  IconData get icon => switch (this) {
    DemoKind.candleDataFeed || DemoKind.candleLive => Icons.candlestick_chart,
    DemoKind.areaDataFeed || DemoKind.areaLive => Icons.area_chart,
    DemoKind.lineDataFeed || DemoKind.lineLive => Icons.show_chart,
  };

  SeriesType get seriesType => switch (this) {
    DemoKind.candleDataFeed || DemoKind.candleLive => SeriesType.candlestick,
    DemoKind.areaDataFeed || DemoKind.areaLive => SeriesType.bar,
    DemoKind.lineDataFeed || DemoKind.lineLive => SeriesType.line,
  };

  bool get isLive => switch (this) {
    DemoKind.candleLive || DemoKind.areaLive || DemoKind.lineLive => true,
    _ => false,
  };

  String get seriesLabel => switch (this) {
    DemoKind.candleDataFeed || DemoKind.candleLive => 'BTC/USD',
    DemoKind.areaDataFeed || DemoKind.areaLive => 'SOL/USD',
    DemoKind.lineDataFeed || DemoKind.lineLive => 'ETH/USD',
  };
}
