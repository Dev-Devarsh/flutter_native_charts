# flutter_native_charts

High-performance **financial / time-series charts** for Flutter on **Android** and **iOS**. The chart is rendered **natively on the GPU** inside a `PlatformView`; Dart talks to a C++ chart engine through **`dart:ffi`**, not through `MethodChannel` / `EventChannel` for data or style updates.

**Customization:** every **`ChartStyle`** field and **`ChartController`** / **`NativeChartView`** option is documented in [API reference (customization)](#api-reference-customization).

## Ideal Use Cases

- **Crypto & Trading Apps:** Rendering tens of thousands of candles smoothly with continuous pan/zoom at 60–120 fps.
- **Live Dashboards:** High-frequency streaming data (live ticks, real-time price updates) where typical Flutter `Canvas` repaints would cause UI thread jank.
- **Heavy Interactive Charts:** When you need batched GPU geometry to maintain predictability during rapid user interactions over large datasets.
---

## Why this package exists

Flutter is excellent for UI composition, but **rich, high-frequency charts** often hit practical limits depending on how you draw:

| Limitation in typical Flutter & native-*Canvas* approaches | What this package does instead |
|---------------------------------------------------------------|--------------------------------|
| **Dart `CustomPaint` / `Canvas`** (Skia/Impeller) — every repaint walks the Flutter layer tree; **many path/line primitives** scale poorly with **tens of thousands** of candles and **continuous pan/zoom** at **60–120 fps**. Decode + layout work often stays on Dart / raster thread in ways that contend with the rest of your UI. | The chart bitmap is produced **outside** Skia’s per-frame `Canvas` API for geometry: triangles/lines go through **Metal (iOS)** or **GLES3 (Android)** as **vertex buffers**, so the heavy **fragment work runs on the GPU**. |
| **Native Android `android.graphics.Canvas`** (e.g. `View.onDraw`, many `drawLine`/`drawRoundRect`/path calls) — convenient for simple UI chrome, but a **dense candle chart** implies **lots of separate draw operations** that are **mostly CPU‑bound** batching-wise compared to **one batched drawable mesh**. Syncing frequent updates through JNI + invalidation paths can also add cost when layered under Flutter composition. | The **GLES3 renderer** submits **indexed/batched draws** driven by native C++/JNI; redraw cost tracks **viewport-sized workload**, not “one JNI/draw call per visual element” in the naive Canvas sense. |
| **Native iOS `CALayer` + `draw(_:)` / Core Graphics (`CGContext`)** — similar story for **thick** plots: rebuilding paths/layers each frame burns **CPU time** before bits hit the framebuffer; **`CAShapeLayer`** with huge paths stresses **backing store and tessellation**. Good for dashboards with few shapes; weaker as a generic **GPU-scale** throughput path for scrolling market data. | **MetalKit (`MTKView`) + compiled `.metal`** — vertex/fragment stages run on the GPU; shaders handle projection, color, and blending in **parallel**, which scales better with **dense geometry**. |
| **`MethodChannel` / `EventChannel`** serialize data across the Flutter bridge — fine occasionally, painful for **streaming OHLC / large snapshots** where every chunk pays **allocation + codecs + threading hops**. | Candles, style, series type, hover, and live ticks go through **`dart:ffi`** into native memory (**no per-bar/per-tick MethodChannel/EventChannel**). |
| **Flutter main isolate** doing both business logic **and** driving every pixel of a reactive chart amplifies GC and jank sensitivity. After a **one-time** native handle handshake, chart updates bypass that hot path for data delivery. | A **native overlay** (Kotlin / Swift) reads axis/ticks/legend/tooltip inputs from the engine (**revision polling**) without streaming overlay state over Flutter channels on every change. |

In short: we chose a **native GPU drawable** (`PlatformView` + **Metal/GLES**) so the chart behaves more like **batched GPU geometry + shaders** than like **Flutter `Canvas`** or **per-primitive CPU Canvas/CoreGraphics** workloads at scale — while still embedding cleanly in a Flutter UI.

---

### Why talk to the GPU? Advantages

| Advantage | Explanation |
|-----------|-------------|
| **Throughput** | The GPU executes **many pixels and fragments in parallel**. A candle mesh (triangles/quads/strips + line primitives) amortizes cost across **few draw calls**, instead of issuing thousands of separate 2D path draws from CPU. |
| **Predictable scaling** | Cost tracks **what is visible / submitted as geometry**, not “re-run Dart layout + Skia replay for every history edit” — important for pan, zoom, and live ticks. |
| **Less CPU‑bound rasterization** | **`Canvas`/Core Graphics‑style APIs** excel at modest vector art; huge bar counts shift work to **CPU tessellation/stroking**. **Vertex + fragment shaders** move that pressure to silicon built for it. |
| **Coherent embedding** | Rendering happens in **one native GL/Metal context** beside the Flutter compositor (`PlatformView`), instead of piping millions of primitives through **`CustomPaint`** on every gesture frame. |
| **Pairs with FFI** | The **Dart ↔ native** boundary moves **dense numeric buffers** (`Float64List` → mmap/memcpy‑style ingestion) rather than structured platform messages — which matches a **native engine that immediately feeds GPU buffers**. |

**Caveats (stay honest):** the **CPU** still runs viewport math, input, overlay layout text, and **building vertex data** — nothing is “zero CPU”. The win is avoiding **Dart/bridge/Canvas redraw** as the **primary bottleneck** for big, interactive plots.

---

## How rendering reaches the GPU (and what “skips” the CPU-heavy Flutter path)

Flutter’s normal model is: **Dart → Framework → Engine (Skia/Impeller)** to composite layers. Your chart, if drawn with `Canvas`, participates in that pipeline on every change.

Here, the visible chart is a **`PlatformView`**:

1. **Metal (iOS)** or **OpenGL ES (Android)** clears and draws **vertex buffers** produced by the chart engine (triangles, lines, etc.).
2. Those draws execute on the **GPU**; the Flutter engine mostly **composites** your platform view as a texture/layer — it is **not** repainting thousands of candles through Dart’s `Canvas` API.
3. The **CPU** still runs the engine (viewport math, candle layout, generating vertex data, input). The important distinction is: you are **not** paying the cost of **serialization + main-thread chart repaints** on every update like a typical channel-driven approach.

So: **GPU does the rasterization** (shaders, blending, large triangle batches). **CPU** does engine work, but **not** “Flutter widget tree repaints the whole chart for every tick.”

---

## Why chart data does *not* use `MethodChannel` or `EventChannel`

**Design rule:** after the view exists, **chart state is not streamed over platform channels**.

| Concern | Approach in this package |
|--------|---------------------------|
| Bulk history / streaming OHLC | **`ChartController.pushCandlesRaw`** (`Float64List`, 6 doubles per candle) → **FFI** → native engine memory. |
| Style, series type, hover | **`setStyle`**, **`setSeriesType`**, **`setHover` / `clearHover`** → **FFI**. |
| Live price / bar | **`updateLivePrice`**, **`updateLiveOhlc`** → **FFI**. |
| Overlay (axes, legend, tooltip) | Native code **reads style and ticks from the engine** (e.g. style revision polling). **No `MethodChannel` push** for each label change. |

**Exception (unavoidable once):** `NativeChartView` uses a **per-view `MethodChannel` only once** to call `getEngineHandle` so Dart can attach the FFI `ChartEngine`. After that, **no chart data path goes through MethodChannel**.

There is **no `EventChannel`** for chart feeds — live and historical updates are **FFI calls** from Dart into native code.

---

## Platform implementation notes

### iOS — Metal & `Shaders.metal`

- Rendering uses **Metal** and **MetalKit** (`MTKView`).
- Shaders live in **`ios/Classes/Shaders.metal`**; they are compiled to **`.metallib`** as part of the Xcode/CocoaPods build (offline compilation).

### Android — OpenGL ES 3.0

- The renderer uses **`GLES30`** and GLSL ES 3.0 shaders embedded in **`ChartRenderer.kt`** — same idea: batched GPU drawing driven by the C++ chart engine via JNI.

---

## iOS setup for developers

### Requirements

- **macOS** with **full Xcode** from the Mac App Store (not “Command Line Tools only” — those are insufficient to compile `.metal` and link Metal frameworks reliably).
- **iOS deployment target**: **13.0+** (see `ios/flutter_native_charts.podspec`).
- CocoaPods (`pod install` in `ios/` of your app, or Flutter handles this for plugins).

### Install / enable Metal build support in Xcode

1. **Install Xcode** and launch it once; accept the license agreement.
2. Open **Xcode → Settings → Locations** and set **Command Line Tools** to your **Xcode.app** (not standalone CLT when you need Metal tooling).
3. Ensure **Metal development** is available (bundled with full Xcode):
   - In older Xcode releases, Apple sometimes shipped extra items under **Xcode → Settings → Components / Platforms**. With current Xcode, a normal install includes the **Metal compiler** (`metal`, `metallib`) used when building pods that contain `.metal` files.
4. If a build fails with errors about **Metal**, **metallib**, or **MTLDevice**, verify:
   - You are building with **Xcode**, not only `flutter build` on a machine that has no UI Xcode install.
   - **Simulator**: Metal is supported on the iOS Simulator on Apple Silicon; on Intel simulators some Metal features differ — test on device if you see simulator-only GPU issues.

### App integration (consumer)

Add the dependency, then **`flutter pub get`**. For iOS:

```bash
cd ios && pod install && cd ..
```

No extra “Metal capability” toggle is normally required inside your **Flutter app target** specifically for this plugin: the **`flutter_native_charts`** pod links **Metal** / **MetalKit** and compiles shaders. Contributors working **inside the plugin repo** should open **`example/ios/Runner.xcworkspace`** and build Run to compile `Shaders.metal` with the rest of the pod.

---

## Installation

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_native_charts:
    path: ../path/to/flutter_native_charts  # or pub.dev version when published
```

Minimum SDK / Flutter version: see this package’s `pubspec.yaml`.

**Dart dependencies:** `flutter` + `ffi` only (small API surface).

---

## Minimal usage example

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_native_charts/flutter_native_charts.dart';

class CandleScreen extends StatefulWidget {
  const CandleScreen({super.key});

  @override
  State<CandleScreen> createState() => _CandleScreenState();
}

class _CandleScreenState extends State<CandleScreen> {
  late final ChartController _chart = ChartController(
    style: const ChartStyle(
      seriesLabel: 'BTC',
      showLegend: true,
      showTooltip: true,
    ),
  );

  @override
  void dispose() {
    _chart.dispose();
    super.dispose();
  }

  void _seedDemoBars() {
    // Layout: [t, o, h, l, c, v] per candle (6 doubles each) — FFI path, no MethodChannel.
    final Float64List raw = Float64List(100 * 6);
    final double t0 = DateTime.now().millisecondsSinceEpoch.toDouble();
    for (var i = 0; i < 100; i++) {
      final o = i * 6;
      raw[o] = t0 + i * 60_000.0; // time (ms since epoch in this example)
      raw[o + 1] = 100 + i * 0.1;
      raw[o + 2] = raw[o + 1] + 0.5;
      raw[o + 3] = raw[o + 1] - 0.5;
      raw[o + 4] = raw[o + 1] + 0.2;
      raw[o + 5] = 1000 + i.toDouble(); // volume
    }
    _chart.pushCandlesRaw(raw);

    _chart.setStyle(_chart.style.copyWith(approxXTicks: 6));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 280,
              child: NativeChartView(controller: _chart),
            ),
            FilledButton(
              onPressed: _seedDemoBars,
              child: const Text('Load demo candles (FFI)'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`NativeChartView` creates the platform surface, retrieves the native engine handle **once**, and `ChartController` uses **FFI** for subsequent updates.

See the **`example/`** app for presets, interaction flags (`allowPanX`, …), live `Timer` demos, and layout sizing patterns.

---

## API reference (customization)

Apply changes with **`controller.setStyle(…)`** or **`chart.style.copyWith(…)`** after updates. Values are mirrored into native code in one FFI call; the overlay (axes, legend, tooltip) observes **`style_revision`** and repaints accordingly.

### `ChartStyle` — colors

| Property | Type | Meaning |
|----------|------|--------|
| **`bgColor`** | `Color` | Plot/chart background behind the grid and series (ARGB). |
| **`gridColor`** | `Color` | Major grid lines (horizontal/vertical subdivisions inside the plot). |
| **`axisTextColor`** | `Color` | Tick labels drawn on the **native overlay** along the X and Y axes (not Flutter `Text`). |
| **`upColor`** | `Color` | Candle **bull** body/outline and related “up” emphasis (exact use depends on shader pass). |
| **`downColor`** | `Color` | Candle **bear** body/outline and related “down” emphasis. |
| **`lineColor`** | `Color` | **Line** series stroke color (also primary line tint where the engine ties line + cue together). |
| **`areaTopColor`** | `Color` | **Area** fill: upper / high-opacity side of the gradient (ARGB with alpha supported). |
| **`areaBottomColor`** | `Color` | **Area** fill: lower / fade side of the gradient. |
| **`crosshairColor`** | `Color` | Crosshair guides and hover marker accents drawn by the GPU + overlay cues. |
| **`tooltipBgColor`** | `Color` | Hover/scrub OHLC tooltip panel background on the native overlay. |
| **`tooltipTextColor`** | `Color` | Tooltip body text (`TIME`, `O`, `H`, `L`, `C`, `VOL` lines). |
| **`legendTextColor`** | `Color` | **Legend chip** label color (series name + optional count badge area). |

### `ChartStyle` — geometry (plot & series drawing)

| Property | Type | Meaning |
|----------|------|--------|
| **`candleBodyWidthFraction`** | `double` | Body width relative to candle slot (0–1 style fraction; engine clamps). Wider bodies fill more horizontal space between bars. |
| **`lineWidthPx`** | `double` | Line stroke width (**logical** thickness for line mode; forwarded to rasterization as px-oriented width). |
| **`wickWidthPx`** | `double` | Candle **wick** (high–low spine) thickness in pixels. |
| **`crosshairWidthPx`** | `double` | Line thickness for crosshair rules. |
| **`xPadFraction`** | `double` | Horizontal **padding fraction** applied inside the viewport (unused side margins vs full X span). Helps keep candles off the left/right gutter. |
| **`yPadFraction`** | `double` | Vertical **padding fraction** for price scale breathing room above/below min/max displayed range. |

### `ChartStyle` — visibility toggles

| Property | Type | Meaning |
|----------|------|--------|
| **`showGrid`** | `bool` | Draw inner grid aligned to tick subdivisions when true. |
| **`showXAxis`** | `bool` | Show bottom X axis ruler baseline (native overlay draws the axis spine + labels). |
| **`showYAxis`** | `bool` | Show left Y axis ruler baseline (native overlay spine + labels). |
| **`showCrosshair`** | `bool` | Hover/scrub vertical/horizontal GPU crosshair and marker participation. |
| **`showTooltip`** | `bool` | Native OHLC/tooltip bubble when hovering or scrubbing. |
| **`showLegend`** | `bool` | Top-left-style **series legend** badge (native overlay; uses `seriesLabel`). |

### `ChartStyle` — ticks & formatting

| Property | Type | Meaning |
|----------|------|--------|
| **`approxXTicks`** | `int` | Target number of labeled **X** tick marks (approximate — engine overlaps/culls for density). |
| **`approxYTicks`** | `int` | Target number of labeled **Y** tick marks (approximate — same rationale). |
| **`yDecimals`** | `int` | Decimal places shown for **numeric Y** ticks and OHLC/tooltip formatting on the overlay. |
| **`xIsTimestampMs`** | `bool` | If **true**, X ticks and tooltip TIME field are interpreted as **Unix Epoch milliseconds** and formatted as time strings; if **false**, X reads as opaque/scalar numeric and formats like Y. |

### `ChartStyle` — legend & gestures

| Property | Type | Meaning |
|----------|------|--------|
| **`seriesLabel`** | `String` | Legend text beside the candle count badge. **Truncated at 31 UTF‑8 bytes** for the native `series_label` field (remaining bytes zeroed); keep labels short when using non‑ASCII. Calling **`setSeriesType`** overwrites label with uppercase `SeriesType.name` unless you **`setStyle(copyWith(seriesLabel: …))`** afterward. |
| **`allowPanX`** | `bool` | **True:** drag pans the viewport horizontally when zoom allows. **False:** horizontal drag **scrubs**: finger drives bar index/tooltip (`allowPanY`/`allowZoom*` still respected). |
| **`allowPanY`** | `bool` | Enables vertical pan (viewport offset on price axis) when interacting. |
| **`allowZoomX`** | `bool` | Enables pinch/scroll widening or narrowing horizontal span (platform gesture mapping). |
| **`allowZoomY`** | `bool` | Enables vertical zoom/stretch of the price viewport. |

### `ChartController`

Constructor: **`ChartController({ ChartStyle? style, double? layoutWidth, double? layoutHeight })`**.

| Getter / member | Meaning |
|-----------------|--------|
| **`style`** | Current style object (immutable); update via **`setStyle`**. |
| **`layoutWidth` / `layoutHeight`** | Optional fixed **logical px** mirrored into **`NativeChartView`** sizing when you use **`setLayoutWidth`** / **`setLayoutHeight`** (otherwise null = parent-driven only). |
| **`isAttached`** | **True** after the platform view returned an engine pointer and FFI is live. |
| **`seriesType`** | Last requested **`SeriesType`** (pending replay before attach stays consistent). |

| Method | Meaning |
|--------|--------|
| **`pushCandlesRaw(Float64List data)`** | Bulk load; **`data.length` must be a multiple of six**. Order **per candle:** **`[t, o, h, l, c, v]`** doubles (see below). FFI copies into native; ideal for reuse of one backing buffer across ticks. |
| **`loadCandles(List<Candle> candles)`** | Same payload as boxed **`Candle`** objects; staged into native staging buffer once allocated. |
| **`setSeriesType(SeriesType type)`** | Switches **`candle` / `line` / `area`** GPU passes; bumps **`seriesLabel`** to uppercase enum name unless you override with **`setStyle`**. |
| **`setStyle(ChartStyle style)`** | Full-style push (colors, ticks, gestures, overlay toggles); bumps native **`style_revision`**. |
| **`clearHover()`** | **`setHover(-1)`** on native side — hides tooltip/markers until next touch/move. |
| **`setLayoutWidth` / `setLayoutHeight`** | Fixed chart size hints in **logical** pixels (**null** = unconstrained dimension). **`NativeChartView(width: …)`** wins over controller if both set. **`ChangeNotifier`** — triggers **`NativeChartView`** rebuild when layout/size changes only for that subtree. |
| **`setTimeframe(Duration interval)`** | Bar bucket width (**ms**) for **`updateLivePrice`** / live OHLC rollup (native default aligns to **60 s** until overridden). Interval must be **positive** and finite (`Duration` internally converted via microseconds → ms float). |
| **`updateLivePrice({ price, timestamp, volume })`** | Tick path: mutate current bucket’s OHLC (**open** pinned, **close** refreshed, **high/low** widen, **volume** summed). Throws if **not attached**. |
| **`updateLiveOhlc(...)`** | Full aggregated bar mutation when upstream already has OHLC. |
| **`dispose()`** | Releases native FFI handle backing and disables further calls; always **`dispose`** the controller bound to each view lifecycle. |

### `NativeChartView`

| Parameter | Meaning |
|-----------|--------|
| **`controller`** | Required **`ChartController`** (one chart view ↔ one controller is the supported model). |
| **`width` / `height`** | Optional **logical px** clamps on chart box; if **`null`**, **`ChartController`** layout getters can still supply extents. |
| **`creationParams`** | Optional map forwarded to platform view constructors (advanced embedding; seldom needed). |

Supports **Android** and **iOS** only (**`UnsupportedError`** elsewhere).

### `SeriesType`

| Value | Meaning |
|-------|--------|
| **`candle`** | Classic OHLC rectangles + wicks. |
| **`line`** | Closing price (or scalar series) drawn as stroke/line strips. |
| **`area`** | Close-driven filled area gradient using **`areaTopColor`** / **`areaBottomColor`**. |

Native enum **`0` / `1` / `2`** — see `SeriesType.nativeValue`.

### `Candle` & raw layout

**`Candle` fields:** **`timestamp`**, **`open`**, **`high`**, **`low`**, **`close`**, **`volume`** — **`double`** to match **`NativeCandle`** FFI layout. **`timestamp`** is opaque ordering unless **`xIsTimestampMs`** is **`true`** (then UX formats as epoch ms clock time).

**`pushCandlesRaw` layout** (six doubles per candle, contiguous):

`t₀, o₀, h₀, l₀, c₀, v₀, t₁, o₁, …`

---

## Summary

| Topic | Detail |
|-------|--------|
| **GPU** | Metal (iOS) / GLES3 (Android) draws chart geometry natively inside a `PlatformView`. |
| **Data path** | `dart:ffi` for candles, style, series, hover, live ticks — **not** `MethodChannel` / `EventChannel` for chart feeds. |
| **One MethodChannel call** | `getEngineHandle` per view instance only. |
| **Flutter limitations addressed** | Reduces reliance on Dart `Canvas`/bridge serialization for dense, interactive charts. |
| **Lightweight Dart** | No Material import required for `NativeChartView`; depends on **`ffi`** plus Flutter SDK only. |

## License / links

See `LICENSE`. Plugin layout follows [Flutter federated/plugin](https://docs.flutter.dev/packages-and-plugins/developing-packages) conventions.
