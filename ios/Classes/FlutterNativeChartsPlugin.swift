import Flutter

public class FlutterNativeChartsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      ChartPlatformViewFactory(messenger: registrar.messenger()),
      withId: "flutter_native_charts_view"
    )
  }
}
