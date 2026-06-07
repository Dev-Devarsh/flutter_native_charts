## 0.0.3

* **Trade lines:** GPU-rendered straight segments synced from Dart via FFI (`chart_engine_sync_trade_lines`).
* **`TradeLine`** / **`TradeLineType`** (`trend`, `entry`, `stopLoss`, `takeProfit`) with default colors (blue entry/trend, red stop loss, green take profit).
* **`ChartController.setTradeLines`** — copies a `NativeTradeLine` array through **`calloc`**, syncs to C++, then frees immediately.
* **Native draw gesture:** touch-and-hold → drag → release on the chart (Android/iOS) previews a draft line and calls **`ChartController.onTradeLineDrawEnd`** with data-space `(x1, y1, x2, y2)`; pan/zoom is suppressed while drawing.
* **`ChartController.clearTradeLineDrawing`** — cancels an in-progress native draw session.
* Example app: **Trade lines · draw segment** on the home screen.

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
