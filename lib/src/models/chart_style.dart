import 'dart:ui' show Color;

/// Immutable visual configuration for a [NativeChartView].
///
/// Maps to the C-side `ChartStyle` struct. [ChartController.setStyle] pushes it
/// through FFI; the native overlay polls `style_revision` so axis/legend/tooltip
/// stay in sync without streaming style over a channel.
class ChartStyle {
  const ChartStyle({
    this.bgColor = const Color(0xFF0B0E14),
    this.gridColor = const Color(0x66363B47),
    this.axisTextColor = const Color(0xFF8D93A2),
    this.upColor = const Color(0xFF7CFFB2),
    this.downColor = const Color(0xFFFF6180),
    this.lineColor = const Color(0xFF7CFFB2),
    this.areaTopColor = const Color(0xD97CFFB2),
    this.areaBottomColor = const Color(0x0D7CFFB2),
    this.crosshairColor = const Color(0xBFFFD466),
    this.tooltipBgColor = const Color(0xF210161F),
    this.tooltipTextColor = const Color(0xFFFFFFFF),
    this.legendTextColor = const Color(0xFF8D93A2),
    this.candleBodyWidthFraction = 0.8,
    this.lineWidthPx = 2.0,
    this.wickWidthPx = 1.0,
    this.crosshairWidthPx = 1.0,
    this.xPadFraction = 0.1,
    this.yPadFraction = 0.1,
    this.showGrid = true,
    this.showXAxis = true,
    this.showYAxis = true,
    this.showCrosshair = true,
    this.showTooltip = true,
    this.showLegend = true,
    this.approxXTicks = 5,
    this.approxYTicks = 5,
    this.yDecimals = 2,
    this.xIsTimestampMs = true,
    this.allowPanX = true,
    this.allowPanY = false,
    this.allowZoomX = true,
    this.allowZoomY = false,
    this.doubleTapToReset = true,
    this.seriesLabel = 'CANDLE',
    this.showCurrentPriceLine = true,
    this.currentPriceLineColor = const Color(0xBF7CFFB2),
  });

  final Color bgColor;
  final Color gridColor;
  final Color axisTextColor;
  final Color upColor;
  final Color downColor;
  final Color lineColor;
  final Color areaTopColor;
  final Color areaBottomColor;
  final Color crosshairColor;
  final Color tooltipBgColor;
  final Color tooltipTextColor;
  final Color legendTextColor;

  final double candleBodyWidthFraction;
  final double lineWidthPx;
  final double wickWidthPx;
  final double crosshairWidthPx;
  final double xPadFraction;
  final double yPadFraction;

  final bool showGrid;
  final bool showXAxis;
  final bool showYAxis;
  final bool showCrosshair;
  final bool showTooltip;
  final bool showLegend;

  final int approxXTicks;
  final int approxYTicks;
  final int yDecimals;
  final bool xIsTimestampMs;

  final bool allowPanX;
  final bool allowPanY;
  final bool allowZoomX;
  final bool allowZoomY;
  final bool doubleTapToReset;

  final String seriesLabel;

  final bool showCurrentPriceLine;
  final Color currentPriceLineColor;

  ChartStyle copyWith({
    Color? bgColor,
    Color? gridColor,
    Color? axisTextColor,
    Color? upColor,
    Color? downColor,
    Color? lineColor,
    Color? areaTopColor,
    Color? areaBottomColor,
    Color? crosshairColor,
    Color? tooltipBgColor,
    Color? tooltipTextColor,
    Color? legendTextColor,
    double? candleBodyWidthFraction,
    double? lineWidthPx,
    double? wickWidthPx,
    double? crosshairWidthPx,
    double? xPadFraction,
    double? yPadFraction,
    bool? showGrid,
    bool? showXAxis,
    bool? showYAxis,
    bool? showCrosshair,
    bool? showTooltip,
    bool? showLegend,
    int? approxXTicks,
    int? approxYTicks,
    int? yDecimals,
    bool? xIsTimestampMs,
    bool? allowPanX,
    bool? allowPanY,
    bool? allowZoomX,
    bool? allowZoomY,
    bool? doubleTapToReset,
    String? seriesLabel,
    bool? showCurrentPriceLine,
    Color? currentPriceLineColor,
  }) {
    return ChartStyle(
      bgColor: bgColor ?? this.bgColor,
      gridColor: gridColor ?? this.gridColor,
      axisTextColor: axisTextColor ?? this.axisTextColor,
      upColor: upColor ?? this.upColor,
      downColor: downColor ?? this.downColor,
      lineColor: lineColor ?? this.lineColor,
      areaTopColor: areaTopColor ?? this.areaTopColor,
      areaBottomColor: areaBottomColor ?? this.areaBottomColor,
      crosshairColor: crosshairColor ?? this.crosshairColor,
      tooltipBgColor: tooltipBgColor ?? this.tooltipBgColor,
      tooltipTextColor: tooltipTextColor ?? this.tooltipTextColor,
      legendTextColor: legendTextColor ?? this.legendTextColor,
      candleBodyWidthFraction:
          candleBodyWidthFraction ?? this.candleBodyWidthFraction,
      lineWidthPx: lineWidthPx ?? this.lineWidthPx,
      wickWidthPx: wickWidthPx ?? this.wickWidthPx,
      crosshairWidthPx: crosshairWidthPx ?? this.crosshairWidthPx,
      xPadFraction: xPadFraction ?? this.xPadFraction,
      yPadFraction: yPadFraction ?? this.yPadFraction,
      showGrid: showGrid ?? this.showGrid,
      showXAxis: showXAxis ?? this.showXAxis,
      showYAxis: showYAxis ?? this.showYAxis,
      showCrosshair: showCrosshair ?? this.showCrosshair,
      showTooltip: showTooltip ?? this.showTooltip,
      showLegend: showLegend ?? this.showLegend,
      approxXTicks: approxXTicks ?? this.approxXTicks,
      approxYTicks: approxYTicks ?? this.approxYTicks,
      yDecimals: yDecimals ?? this.yDecimals,
      xIsTimestampMs: xIsTimestampMs ?? this.xIsTimestampMs,
      allowPanX: allowPanX ?? this.allowPanX,
      allowPanY: allowPanY ?? this.allowPanY,
      allowZoomX: allowZoomX ?? this.allowZoomX,
      allowZoomY: allowZoomY ?? this.allowZoomY,
      doubleTapToReset: doubleTapToReset ?? this.doubleTapToReset,
      seriesLabel: seriesLabel ?? this.seriesLabel,
      showCurrentPriceLine: showCurrentPriceLine ?? this.showCurrentPriceLine,
      currentPriceLineColor:
          currentPriceLineColor ?? this.currentPriceLineColor,
    );
  }
}
