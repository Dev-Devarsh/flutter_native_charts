package com.example.flutter_native_charts

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers the chart [PlatformView] factory; chart I/O uses FFI after view creation. */
class FlutterNativeChartsPlugin : FlutterPlugin {
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding
            .platformViewRegistry
            .registerViewFactory(
                "flutter_native_charts_view",
                ChartPlatformViewFactory(flutterPluginBinding.binaryMessenger),
            )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
