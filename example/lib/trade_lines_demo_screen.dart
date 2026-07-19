import 'package:flutter/material.dart';
import 'package:flutter_native_charts/flutter_native_charts.dart';

import 'sample_data.dart';

/// Draw trend-line segments: touch-and-hold → drag → release (TradingView-style).
class TradeLinesDemoScreen extends StatefulWidget {
  const TradeLinesDemoScreen({super.key});

  @override
  State<TradeLinesDemoScreen> createState() => _TradeLinesDemoScreenState();
}

class _TradeLinesDemoScreenState extends State<TradeLinesDemoScreen> {
  static const double _intervalMs = 60_000;

  late final ChartController _chart = ChartController(
    style: ChartStyle(
      seriesLabel: 'TRADE LINES',
      showLegend: true,
      showTooltip: true,
      showCrosshair: true,
      showCurrentPriceLine: true,
      currentPriceLineColor: const Color(0xBF7CFFB2),
      approxXTicks: 6,
      approxYTicks: 6,
      yDecimals: 2,
      allowPanX: true,
      allowPanY: false,
      allowZoomX: true,
      allowZoomY: false,
    ),
  );

  final List<TradeLine> _lines = [];
  int _lineCounter = 0;

  @override
  void initState() {
    super.initState();
    _chart.addListener(_onChartChanged);
    _chart.setTimeframe(const Duration(minutes: 1));
    _chart.setSeriesType(SeriesType.candlestick);
    _seedChart();
    _chart.onTradeLineDrawEnd = _onTradeLineDrawEnd;
  }

  void _onChartChanged() {
    if (mounted) setState(() {});
  }

  void _onTradeLineDrawEnd(double x1, double y1, double x2, double y2) {
    _lineCounter++;
    final line = TradeLine(
      orderId: 'line-$_lineCounter',
      type: TradeLineType.trend,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
    );
    setState(() {
      _lines.add(line);
    });
    _chart.setTradeLines(_lines);
  }

  void _seedChart() {
    final end = DateTime.now().millisecondsSinceEpoch.toDouble();
    final candles = generateCandles(
      count: 120,
      endTimeMs: end,
      intervalMs: _intervalMs,
      startPrice: 102,
      seed: 903,
    );
    _chart.pushCandlesRaw(candlesToRaw(candles));
  }

  void _clearLines() {
    setState(() {
      _lines.clear();
      _lineCounter = 0;
    });
    _chart.setTradeLines(const []);
    _chart.clearTradeLineDrawing();
  }

  @override
  void dispose() {
    _chart.clearTradeLineDrawing();
    _chart.onTradeLineDrawEnd = null;
    _chart.removeListener(_onChartChanged);
    _chart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text('Trade lines · draw segment'),
        backgroundColor: const Color(0xFF12161F),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _StatusChip(attached: _chart.isAttached)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Touch and hold on the chart to anchor the start point, drag to the end '
              'point, then release to create a straight trend line (like TradingView). '
              'The chart will not pan while you are drawing.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Color(0xFF8D93A2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _LinesPanel(lines: _lines),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF363B47)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: NativeChartView(controller: _chart),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _lines.isEmpty ? null : _clearLines,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear lines'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesPanel extends StatelessWidget {
  const _LinesPanel({required this.lines});

  final List<TradeLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12161F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF363B47)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Drawn lines (${lines.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            const Text(
              'No lines yet — touch and hold on the chart to start.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8D93A2)),
            ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${line.orderId}: (${line.y1.toStringAsFixed(2)}) → (${line.y2.toStringAsFixed(2)})',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.attached});

  final bool attached;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: attached ? const Color(0x337CFFB2) : const Color(0x33FF6180),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        attached ? 'READY' : '…',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: attached ? const Color(0xFF7CFFB2) : const Color(0xFFFF6180),
        ),
      ),
    );
  }
}
