import 'dart:ui' show Color;

/// Role / style for a two-point trade or trend line segment.
enum TradeLineType {
  trend(0),
  entry(1),
  stopLoss(2),
  takeProfit(3);

  const TradeLineType(this.nativeValue);
  final int nativeValue;
}

/// A straight segment between two chart data points (time/price space).
///
/// [x1]/[x2] are data X values (typically unix ms timestamps).
/// [y1]/[y2] are prices.
class TradeLine {
  const TradeLine({
    required this.orderId,
    required this.type,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.color,
  }) : assert(orderId.length <= 31, 'orderId must be at most 31 UTF-8 bytes');

  final String orderId;
  final TradeLineType type;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// When null, [defaultColorFor] is used when syncing to native.
  final Color? color;

  static Color defaultColorFor(TradeLineType type) {
    switch (type) {
      case TradeLineType.trend:
        return const Color(0xFF4A9EFF);
      case TradeLineType.entry:
        return const Color(0xFF4A9EFF);
      case TradeLineType.stopLoss:
        return const Color(0xFFFF6161);
      case TradeLineType.takeProfit:
        return const Color(0xFF4ADE80);
    }
  }

  Color resolvedColor() => color ?? defaultColorFor(type);
}
