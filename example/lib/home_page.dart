import 'package:flutter/material.dart';

import 'chart_demo_screen.dart';
import 'demo_kind.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const List<DemoKind> _demos = DemoKind.values;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text('flutter_native_charts'),
        backgroundColor: const Color(0xFF12161F),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Six demos — each series type in data-feed and live mode.',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: const Color(0xFF8D93A2)),
          ),
          const SizedBox(height: 16),
          ..._demos.map(
            (kind) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _DemoTile(kind: kind),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({required this.kind});

  final DemoKind kind;

  @override
  Widget build(BuildContext context) {
    final isLive = kind.isLive;
    return Material(
      color: const Color(0xFF12161F),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChartDemoScreen(kind: kind),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isLive
                      ? const Color(0xFF1A2A22)
                      : const Color(0xFF1A2230),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  kind.icon,
                  color: isLive
                      ? const Color(0xFF7CFFB2)
                      : const Color(0xFF8D93A2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            kind.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _Badge(
                          label: isLive ? 'LIVE' : 'FEED',
                          color: isLive
                              ? const Color(0xFF7CFFB2)
                              : const Color(0xFF8D93A2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      kind.description,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF8D93A2),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8D93A2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
