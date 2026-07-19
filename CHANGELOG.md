## 0.0.2

* **Live price tracer:** horizontal GPU line at the latest candle **close**, with a synchronized **Y-axis price badge** on the native overlay (Android Kotlin / iOS Swift).
* **`ChartStyle.showCurrentPriceLine`** and **`ChartStyle.currentPriceLineColor`** — toggled from Dart via FFI (`ChartController.setStyle`).
* C++ chart engine emits `CHART_PRIMITIVE_LINES` geometry when the tracer is enabled.
* Example app: live price tracer enabled on **Candle · Live**, **Area · Live**, and **Line · Live**; **Price line** toggle in the customization sheet on those screens.

## 0.0.1

* Initial release of `flutter_native_charts`.
* Native GPU-backed chart engine for iOS and Android.
* Minimal Dart surface and zero Canvas dependencies.
* Includes example application demonstrating usage.
