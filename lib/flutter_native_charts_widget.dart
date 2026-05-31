import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/chart_controller.dart';

const String kFlutterNativeChartsViewType = 'flutter_native_charts_view';
const String _kMethodChannelPrefix = 'flutter_native_charts/view';

/// Flutter-side host for the native chart surface.
///
/// The native [PlatformView] owns the chart engine *and* the overlay UI
/// (axes / legend / tooltip). Avoid wrapping this view in a [ClipRRect] with
/// tight radii — platform views are composited as one layer and clipping can
/// remove axis margins drawn at the edges. Once the view is created we ask it
/// for the engine handle and bind it into the supplied [controller]. Past
/// that point, the Flutter main thread is uninvolved on the chart hot path.
///
/// ### Sizing
///
/// By default the view expands to parent [BoxConstraints]. Optionally set
/// [width] / [height] (logical pixels), or set the same on [ChartController]
/// via [ChartController.setLayoutWidth] / [ChartController.setLayoutHeight] so
/// dimensions can be updated without rebuilding the widget subtree. When both
/// widget and controller specify a dimension, the **widget value wins**.
class NativeChartView extends StatefulWidget {
  const NativeChartView({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.creationParams,
  });

  final ChartController controller;
  final double? width;
  final double? height;
  final Map<String, dynamic>? creationParams;

  @override
  State<NativeChartView> createState() => _NativeChartViewState();
}

class _NativeChartViewState extends State<NativeChartView> {
  MethodChannel? _channel;

  @override
  void dispose() {
    widget.controller.detachHandleInternal();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _bindEngineHandle(int viewId) async {
    final channel = MethodChannel('$_kMethodChannelPrefix/$viewId');
    _channel = channel;
    try {
      final dynamic raw = await channel.invokeMethod<dynamic>(
        'getEngineHandle',
      );
      if (!mounted) return;
      if (raw is int) {
        widget.controller.attachHandleInternal(raw, viewId);
      } else if (raw != null) {
        widget.controller.attachHandleInternal((raw as num).toInt(), viewId);
      }
    } on PlatformException catch (e, st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          context: ErrorDescription('NativeChartView.getEngineHandle'),
        ),
      );
    }
  }

  Widget _buildPlatformLayers(TextDirection layoutDirection) {
    if (Platform.isAndroid) {
      return PlatformViewLink(
        viewType: kFlutterNativeChartsViewType,
        surfaceFactory:
            (BuildContext context, PlatformViewController controller) {
              return AndroidViewSurface(
                controller: controller as AndroidViewController,
                gestureRecognizers:
                    const <Factory<OneSequenceGestureRecognizer>>{},
                hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              );
            },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          final AndroidViewController controller =
              PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: kFlutterNativeChartsViewType,
                layoutDirection: layoutDirection,
                creationParams: widget.creationParams,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              );
          controller.addOnPlatformViewCreatedListener((int viewId) {
            params.onPlatformViewCreated(viewId);
            _bindEngineHandle(viewId);
          });
          controller.create();
          return controller;
        },
      );
    }
    if (Platform.isIOS) {
      return UiKitView(
        viewType: kFlutterNativeChartsViewType,
        layoutDirection: layoutDirection,
        creationParams: widget.creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (int viewId) {
          _bindEngineHandle(viewId);
        },
      );
    }
    throw UnsupportedError('NativeChartView supports Android and iOS only.');
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection layoutDirection = Directionality.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final double? w = widget.width ?? widget.controller.layoutWidth;
        final double? h = widget.height ?? widget.controller.layoutHeight;

        // Keep platform view state when only layout fields change on [ChartController].
        Widget chart = KeyedSubtree(
          key: ObjectKey(widget.controller),
          child: _buildPlatformLayers(layoutDirection),
        );
        if (w != null || h != null) {
          chart = SizedBox(width: w, height: h, child: chart);
        }
        return chart;
      },
    );
  }
}
