import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_charts/flutter_native_charts.dart';

import 'demo_kind.dart';
import 'sample_data.dart';

class ChartDemoScreen extends StatefulWidget {
  const ChartDemoScreen({super.key, required this.kind});

  final DemoKind kind;

  @override
  State<ChartDemoScreen> createState() => _ChartDemoScreenState();
}

class _RawGenArgs {
  const _RawGenArgs({
    required this.count,
    required this.endTimeMs,
    required this.intervalMs,
    required this.startPrice,
    required this.seed,
  });

  final int count;
  final double endTimeMs;
  final double intervalMs;
  final double startPrice;
  final int seed;
}

Float64List _generateRawIsolate(_RawGenArgs args) {
  return generateCandlesRaw(
    count: args.count,
    endTimeMs: args.endTimeMs,
    intervalMs: args.intervalMs,
    startPrice: args.startPrice,
    seed: args.seed,
  );
}

class _ChartDemoScreenState extends State<ChartDemoScreen> {
  static const int _feedBarCount = 180;
  static const int _liveSeedBars = 48;
  static const int _bars100k = 100_000;
  static const int _bars1m = 1_000_000;
  static const double _intervalMs = 60_000;

  late final ChartController _chart = ChartController(
    style: ChartStyle(
      seriesLabel: widget.kind.seriesLabel,
      showLegend: true,
      showTooltip: true,
      showCrosshair: true,
      showCurrentPriceLine: widget.kind.isLive,
      currentPriceLineColor: const Color(0xBF7CFFB2),
      approxXTicks: 6,
      approxYTicks: 6,
      yDecimals: 2,
    ),
  );

  final Random _random = Random();
  Timer? _liveTimer;
  Float64List? _rawBuffer;
  double _livePrice = 100;
  double _liveTs = 0;
  String? _interactionPresetLabel = 'Default';
  bool _loadingData = false;

  @override
  void initState() {
    super.initState();
    _chart.addListener(_onChartChanged);
    _chart.setTimeframe(const Duration(minutes: 1));
    _chart.setSeriesType(widget.kind.seriesType);
    _seedChart();
    if (widget.kind.isLive) {
      _chart.addListener(_maybeStartLive);
    }
  }

  void _onChartChanged() {
    if (mounted) setState(() {});
  }

  void _maybeStartLive() {
    if (!widget.kind.isLive || !_chart.isAttached || _liveTimer != null) return;
    _chart.removeListener(_maybeStartLive);
    _startLive();
  }

  @override
  void dispose() {
    _chart.removeListener(_onChartChanged);
    _chart.removeListener(_maybeStartLive);
    _liveTimer?.cancel();
    _chart.dispose();
    super.dispose();
  }

  void _seedChart() {
    final barCount = widget.kind.isLive ? _liveSeedBars : _feedBarCount;
    final end = DateTime.now().millisecondsSinceEpoch.toDouble();
    final candles = generateCandles(
      count: barCount,
      endTimeMs: end,
      intervalMs: _intervalMs,
      startPrice: 95 + _random.nextDouble() * 30,
      seed: widget.kind.index * 17 + 3,
    );
    _rawBuffer = candlesToRaw(candles);
    _chart.pushCandlesRaw(_rawBuffer!);
    _livePrice = candles.last.close;
    _liveTs = candles.last.timestamp;
    _chart.setStyle(
      _chart.style.copyWith(seriesLabel: widget.kind.seriesLabel),
    );
  }

  Future<void> _loadBars(int count) async {
    if (_loadingData) return;
    setState(() => _loadingData = true);
    final end = DateTime.now().millisecondsSinceEpoch.toDouble();
    final raw = await compute(
      _generateRawIsolate,
      _RawGenArgs(
        count: count,
        endTimeMs: end,
        intervalMs: _intervalMs,
        startPrice: 95 + _random.nextDouble() * 30,
        seed: _random.nextInt(1 << 31),
      ),
    );
    if (!mounted) return;
    _rawBuffer = raw;
    _chart.pushCandlesRaw(raw);
    _livePrice = raw[raw.length - 2];
    _liveTs = raw[raw.length - 6];
    _chart.setStyle(
      _chart.style.copyWith(seriesLabel: widget.kind.seriesLabel),
    );
    setState(() => _loadingData = false);
  }

  void _startLive() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (!_chart.isAttached) return;
      _livePrice += (_random.nextDouble() - 0.5) * 1.8;
      _liveTs += _intervalMs * 0.12;
      try {
        _chart.updateLivePrice(
          price: _livePrice,
          timestamp: _liveTs,
          volume: 20 + _random.nextDouble() * 80,
        );
      } on StateError {
        return;
      }
    });
    setState(() {});
  }

  void _applyInteractionPreset(_InteractionPreset preset) {
    _interactionPresetLabel = preset.label;
    _chart.setStyle(
      _chart.style.copyWith(
        allowPanX: preset.allowPanX,
        allowPanY: preset.allowPanY,
        allowZoomX: preset.allowZoomX,
        allowZoomY: preset.allowZoomY,
      ),
    );
    setState(() {});
  }

  void _toggleInteraction({
    required bool allowPanX,
    required bool allowPanY,
    required bool allowZoomX,
    required bool allowZoomY,
  }) {
    _interactionPresetLabel = null;
    _chart.setStyle(
      _chart.style.copyWith(
        allowPanX: allowPanX,
        allowPanY: allowPanY,
        allowZoomX: allowZoomX,
        allowZoomY: allowZoomY,
      ),
    );
    setState(() {});
  }

  void _patchStyle(ChartStyle Function(ChartStyle) patch) {
    _chart.setStyle(patch(_chart.style));
    setState(() {});
  }

  void _showCustomizationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12161F),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StyleOptionsPanel(
                        title: 'Overlay',
                        style: _chart.style,
                        options: [
                          const _StyleBoolOption(
                            'Grid',
                            _StyleBoolField.showGrid,
                          ),
                          const _StyleBoolOption(
                            'X axis',
                            _StyleBoolField.showXAxis,
                          ),
                          const _StyleBoolOption(
                            'Y axis',
                            _StyleBoolField.showYAxis,
                          ),
                          const _StyleBoolOption(
                            'Crosshair',
                            _StyleBoolField.showCrosshair,
                          ),
                          const _StyleBoolOption(
                            'Tooltip',
                            _StyleBoolField.showTooltip,
                          ),
                          const _StyleBoolOption(
                            'Legend',
                            _StyleBoolField.showLegend,
                          ),
                          if (widget.kind.isLive)
                            const _StyleBoolOption(
                              'Price line',
                              _StyleBoolField.showCurrentPriceLine,
                            ),
                        ],
                        onChanged: (field, value) {
                          _patchStyle((s) => field.apply(s, value));
                          setSheetState(() {});
                        },
                      ),
                      _StyleOptionsPanel(
                        title: 'Format',
                        style: _chart.style,
                        options: const [
                          _StyleBoolOption(
                            'X as timestamp (ms)',
                            _StyleBoolField.xIsTimestampMs,
                          ),
                        ],
                        onChanged: (field, value) {
                          _patchStyle((s) => field.apply(s, value));
                          setSheetState(() {});
                        },
                      ),
                      _InteractionPanel(
                        style: _chart.style,
                        selectedPresetLabel: _interactionPresetLabel,
                        onPreset: (p) {
                          _applyInteractionPreset(p);
                          setSheetState(() {});
                        },
                        onToggle:
                            ({
                              required allowPanX,
                              required allowPanY,
                              required allowZoomX,
                              required allowZoomY,
                            }) {
                              _toggleInteraction(
                                allowPanX: allowPanX,
                                allowPanY: allowPanY,
                                allowZoomX: allowZoomX,
                                allowZoomY: allowZoomY,
                              );
                              setSheetState(() {});
                            },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: Text(kind.title),
        backgroundColor: const Color(0xFF12161F),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showCustomizationSheet,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _StatusChip(
                attached: _chart.isAttached,
                live: kind.isLive,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              kind.description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8D93A2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _ModeBanner(kind: kind, liveActive: _liveTimer != null),
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
                  if (!kind.isLive) ...[
                    Expanded(
                      child: FilledButton(
                        onPressed: _loadingData
                            ? null
                            : () => _loadBars(_bars100k),
                        child: _loadingData
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Add 100K data'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _loadingData
                            ? null
                            : () => _loadBars(_bars1m),
                        child: const Text('Add 1M data'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: _chart.isAttached ? _chart.clearHover : null,
                    icon: const Icon(Icons.touch_app_outlined),
                    label: const Text('clearHover'),
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

enum _StyleBoolField {
  showGrid,
  showXAxis,
  showYAxis,
  showCrosshair,
  showTooltip,
  showLegend,
  showCurrentPriceLine,
  xIsTimestampMs;

  bool read(ChartStyle s) => switch (this) {
    _StyleBoolField.showGrid => s.showGrid,
    _StyleBoolField.showXAxis => s.showXAxis,
    _StyleBoolField.showYAxis => s.showYAxis,
    _StyleBoolField.showCrosshair => s.showCrosshair,
    _StyleBoolField.showTooltip => s.showTooltip,
    _StyleBoolField.showLegend => s.showLegend,
    _StyleBoolField.showCurrentPriceLine => s.showCurrentPriceLine,
    _StyleBoolField.xIsTimestampMs => s.xIsTimestampMs,
  };

  ChartStyle apply(ChartStyle s, bool value) => switch (this) {
    _StyleBoolField.showGrid => s.copyWith(showGrid: value),
    _StyleBoolField.showXAxis => s.copyWith(showXAxis: value),
    _StyleBoolField.showYAxis => s.copyWith(showYAxis: value),
    _StyleBoolField.showCrosshair => s.copyWith(showCrosshair: value),
    _StyleBoolField.showTooltip => s.copyWith(showTooltip: value),
    _StyleBoolField.showLegend => s.copyWith(showLegend: value),
    _StyleBoolField.showCurrentPriceLine => s.copyWith(
      showCurrentPriceLine: value,
    ),
    _StyleBoolField.xIsTimestampMs => s.copyWith(xIsTimestampMs: value),
  };
}

class _StyleBoolOption {
  const _StyleBoolOption(this.label, this.field);

  final String label;
  final _StyleBoolField field;
}

/// Checkbox-style toggles mapped to [ChartStyle] via [ChartController.setStyle].
class _StyleOptionsPanel extends StatelessWidget {
  const _StyleOptionsPanel({
    required this.title,
    required this.style,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final ChartStyle style;
  final List<_StyleBoolOption> options;
  final void Function(_StyleBoolField field, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF12161F),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 0,
              runSpacing: 0,
              children: [
                for (final opt in options)
                  FilterChip(
                    label: Text(opt.label),
                    selected: opt.field.read(style),
                    onSelected: (v) => onChanged(opt.field, v),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pan / zoom locks via [ChartStyle.allowPanX/Y] and [ChartStyle.allowZoomX/Y].
class _InteractionPanel extends StatelessWidget {
  const _InteractionPanel({
    required this.style,
    required this.selectedPresetLabel,
    required this.onPreset,
    required this.onToggle,
  });

  final ChartStyle style;
  final String? selectedPresetLabel;
  final ValueChanged<_InteractionPreset> onPreset;
  final void Function({
    required bool allowPanX,
    required bool allowPanY,
    required bool allowZoomX,
    required bool allowZoomY,
  })
  onToggle;

  static const _presets = <_InteractionPreset>[
    _InteractionPreset(
      label: 'Default',
      hint: 'Pan X + zoom X (library default)',
      allowPanX: true,
      allowPanY: false,
      allowZoomX: true,
      allowZoomY: false,
    ),
    _InteractionPreset(
      label: 'Lock X',
      hint: 'allowPanX & allowZoomX off · Y pan/zoom stay on',
      allowPanX: false,
      allowPanY: true,
      allowZoomX: false,
      allowZoomY: true,
    ),
    _InteractionPreset(
      label: 'Lock Y',
      hint: 'allowPanY & allowZoomY off · X pan/zoom stay on',
      allowPanX: true,
      allowPanY: false,
      allowZoomX: true,
      allowZoomY: false,
    ),
    _InteractionPreset(
      label: 'Lock XY',
      hint: 'All pan and zoom disabled',
      allowPanX: false,
      allowPanY: false,
      allowZoomX: false,
      allowZoomY: false,
    ),
    _InteractionPreset(
      label: 'Lock pan',
      hint: 'Pan off both axes · zoom still on',
      allowPanX: false,
      allowPanY: false,
      allowZoomX: true,
      allowZoomY: true,
    ),
    _InteractionPreset(
      label: 'Free',
      hint: 'Pan and zoom on X and Y',
      allowPanX: true,
      allowPanY: true,
      allowZoomX: true,
      allowZoomY: true,
    ),
    _InteractionPreset(
      label: 'Scrub',
      hint: 'Pan X off · zoom X on (tooltip scrub)',
      allowPanX: false,
      allowPanY: false,
      allowZoomX: true,
      allowZoomY: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF12161F),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Interaction · setStyle → FFI',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'allowPanX=false uses horizontal scrub instead of pan. Toggle each axis independently.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8D93A2)),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in _presets) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(p.label),
                        selected: selectedPresetLabel == p.label,
                        onSelected: (_) => onPreset(p),
                        tooltip: p.hint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _InteractionSwitch(
                    label: 'Pan X',
                    subtitle: style.allowPanX ? 'pan' : 'scrub',
                    value: style.allowPanX,
                    onChanged: (v) => onToggle(
                      allowPanX: v,
                      allowPanY: style.allowPanY,
                      allowZoomX: style.allowZoomX,
                      allowZoomY: style.allowZoomY,
                    ),
                  ),
                ),
                Expanded(
                  child: _InteractionSwitch(
                    label: 'Pan Y',
                    value: style.allowPanY,
                    onChanged: (v) => onToggle(
                      allowPanX: style.allowPanX,
                      allowPanY: v,
                      allowZoomX: style.allowZoomX,
                      allowZoomY: style.allowZoomY,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _InteractionSwitch(
                    label: 'Zoom X',
                    value: style.allowZoomX,
                    onChanged: (v) => onToggle(
                      allowPanX: style.allowPanX,
                      allowPanY: style.allowPanY,
                      allowZoomX: v,
                      allowZoomY: style.allowZoomY,
                    ),
                  ),
                ),
                Expanded(
                  child: _InteractionSwitch(
                    label: 'Zoom Y',
                    value: style.allowZoomY,
                    onChanged: (v) => onToggle(
                      allowPanX: style.allowPanX,
                      allowPanY: style.allowPanY,
                      allowZoomX: style.allowZoomX,
                      allowZoomY: v,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionPreset {
  const _InteractionPreset({
    required this.label,
    required this.hint,
    required this.allowPanX,
    required this.allowPanY,
    required this.allowZoomX,
    required this.allowZoomY,
  });

  final String label;
  final String hint;
  final bool allowPanX;
  final bool allowPanY;
  final bool allowZoomX;
  final bool allowZoomY;
}

class _InteractionSwitch extends StatelessWidget {
  const _InteractionSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 11))
          : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.kind, required this.liveActive});

  final DemoKind kind;
  final bool liveActive;

  @override
  Widget build(BuildContext context) {
    final feed = !kind.isLive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: feed ? const Color(0xFF1A2230) : const Color(0xFF1A2A22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: feed ? const Color(0xFF363B47) : const Color(0xFF3D5C4A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            feed ? Icons.cloud_download_outlined : Icons.sensors,
            size: 20,
            color: feed ? const Color(0xFF8D93A2) : const Color(0xFF7CFFB2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              feed
                  ? 'Data feed · pushCandlesRaw → FFI'
                  : liveActive
                  ? 'Live · updateLivePrice + price tracer (running)'
                  : 'Live · waiting for native engine…',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.attached, required this.live});

  final bool attached;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final ok = attached;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? const Color(0x337CFFB2) : const Color(0x33FF6180),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        ok ? (live ? 'LIVE' : 'READY') : '…',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ok ? const Color(0xFF7CFFB2) : const Color(0xFFFF6180),
        ),
      ),
    );
  }
}
