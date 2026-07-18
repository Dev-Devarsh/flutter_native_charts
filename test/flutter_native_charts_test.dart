import 'dart:ui' show Color;

import 'package:flutter_native_charts/flutter_native_charts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SeriesType', () {
    test('native values match C enum ABI', () {
      expect(SeriesType.candlestick.nativeValue, 0);
      expect(SeriesType.line.nativeValue, 1);
      expect(SeriesType.bar.nativeValue, 2);
    });
  });

  group('Candle', () {
    test('stores OHLCV fields', () {
      const candle = Candle(
        timestamp: 1_700_000_000_000,
        open: 100,
        high: 110,
        low: 90,
        close: 105,
        volume: 1_000,
      );

      expect(candle.timestamp, 1_700_000_000_000);
      expect(candle.open, 100);
      expect(candle.high, 110);
      expect(candle.low, 90);
      expect(candle.close, 105);
      expect(candle.volume, 1_000);
    });
  });

  group('ChartStyle', () {
    test('defaults are stable', () {
      const style = ChartStyle();

      expect(style.bgColor, const Color(0xFF0B0E14));
      expect(style.upColor, const Color(0xFF7CFFB2));
      expect(style.downColor, const Color(0xFFFF6180));
      expect(style.candleBodyWidthFraction, 0.8);
      expect(style.showGrid, isTrue);
      expect(style.allowPanX, isTrue);
      expect(style.allowPanY, isFalse);
      expect(style.seriesLabel, 'CANDLE');
    });

    test('copyWith overrides only provided fields', () {
      const base = ChartStyle();
      final updated = base.copyWith(
        seriesLabel: 'BTCUSD',
        showLegend: false,
        lineWidthPx: 3.5,
      );

      expect(updated.seriesLabel, 'BTCUSD');
      expect(updated.showLegend, isFalse);
      expect(updated.lineWidthPx, 3.5);
      expect(updated.bgColor, base.bgColor);
      expect(updated.allowZoomX, base.allowZoomX);
    });
  });
}
