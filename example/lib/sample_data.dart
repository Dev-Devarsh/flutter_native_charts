import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_native_charts/flutter_native_charts.dart';

/// Generates [count] synthetic OHLCV candles ending at [endTimeMs].
List<Candle> generateCandles({
  required int count,
  required double endTimeMs,
  required double intervalMs,
  double startPrice = 100.0,
  int seed = 42,
}) {
  final random = Random(seed);
  final candles = <Candle>[];
  var price = startPrice;
  var t = endTimeMs - (count - 1) * intervalMs;

  for (var i = 0; i < count; i++) {
    final open = price;
    final delta = (random.nextDouble() - 0.48) * 2.5;
    final close = (open + delta).clamp(1.0, 10000.0);
    final high = max(open, close) + random.nextDouble() * 1.2;
    final low = min(open, close) - random.nextDouble() * 1.2;
    final volume = 500 + random.nextDouble() * 2500;
    candles.add(
      Candle(
        timestamp: t,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ),
    );
    price = close;
    t += intervalMs;
  }
  return candles;
}

/// Generates `[t, o, h, l, c, v, …]` directly (no intermediate [Candle] list).
Float64List generateCandlesRaw({
  required int count,
  required double endTimeMs,
  required double intervalMs,
  double startPrice = 100.0,
  int seed = 42,
}) {
  final random = Random(seed);
  final raw = Float64List(count * 6);
  var price = startPrice;
  var t = endTimeMs - (count - 1) * intervalMs;

  for (var i = 0; i < count; i++) {
    final open = price;
    final delta = (random.nextDouble() - 0.48) * 2.5;
    final close = (open + delta).clamp(1.0, 10000.0);
    final high = max(open, close) + random.nextDouble() * 1.2;
    final low = min(open, close) - random.nextDouble() * 1.2;
    final volume = 500 + random.nextDouble() * 2500;
    final o = i * 6;
    raw[o] = t;
    raw[o + 1] = open;
    raw[o + 2] = high;
    raw[o + 3] = low;
    raw[o + 4] = close;
    raw[o + 5] = volume;
    price = close;
    t += intervalMs;
  }
  return raw;
}

/// Like [generateCandles] but injects a few extreme volume spikes so the split
/// volume pane (bottom 20%) is easy to see without overlapping price candles.
List<Candle> generateCandlesWithVolumeSpikes({
  required int count,
  required double endTimeMs,
  required double intervalMs,
  double startPrice = 100.0,
  int seed = 42,
}) {
  final candles = generateCandles(
    count: count,
    endTimeMs: endTimeMs,
    intervalMs: intervalMs,
    startPrice: startPrice,
    seed: seed,
  );
  if (candles.length < 8) return candles;

  final spikeIndices = {
    candles.length ~/ 4,
    candles.length ~/ 2,
    (candles.length * 3) ~/ 4,
  };
  for (final i in spikeIndices) {
    final c = candles[i];
    candles[i] = Candle(
      timestamp: c.timestamp,
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close,
      volume: c.volume * 18,
    );
  }
  return candles;
}

/// Packs candles into `[t, o, h, l, c, v, …]` for [ChartController.pushCandlesRaw].
Float64List candlesToRaw(List<Candle> candles) {
  final raw = Float64List(candles.length * 6);
  for (var i = 0; i < candles.length; i++) {
    final c = candles[i];
    final o = i * 6;
    raw[o] = c.timestamp;
    raw[o + 1] = c.open;
    raw[o + 2] = c.high;
    raw[o + 3] = c.low;
    raw[o + 4] = c.close;
    raw[o + 5] = c.volume;
  }
  return raw;
}

/// In-place random walk on the last candle (streaming buffer demo).
void nudgeLastCandleRaw(Float64List raw, Random random) {
  if (raw.isEmpty) return;
  final o = raw.length - 6;
  final open = raw[o + 1];
  final delta = (random.nextDouble() - 0.5) * 0.8;
  final close = (open + delta).clamp(1.0, 10000.0);
  raw[o + 4] = close;
  raw[o + 2] = max(raw[o + 2], max(open, close));
  raw[o + 3] = min(raw[o + 3], min(open, close));
  raw[o + 5] += random.nextDouble() * 50;
}
