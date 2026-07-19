import Flutter
import MetalKit
import UIKit
import simd

private let kChannelPrefix = "flutter_native_charts/view"

private struct ChartUniforms {
  var projection: simd_float4x4
}

private extension simd_float4x4 {
  init(columnMajor m: UnsafePointer<Float>) {
    self.init(
      SIMD4<Float>(m[0],  m[1],  m[2],  m[3]),
      SIMD4<Float>(m[4],  m[5],  m[6],  m[7]),
      SIMD4<Float>(m[8],  m[9],  m[10], m[11]),
      SIMD4<Float>(m[12], m[13], m[14], m[15])
    )
  }
}

private enum ChartPrimitive: Int {
  case triangles = 0
  case lines = 1
  case lineStrip = 2
  case triangleStrip = 3

  var metal: MTLPrimitiveType {
    switch self {
    case .triangles: return .triangle
    case .lines: return .line
    case .lineStrip: return .lineStrip
    case .triangleStrip: return .triangleStrip
    }
  }
}

private struct PassEntry {
  var vertices: [Float] = []
  var vertexCount: Int = 0
  var primitive: ChartPrimitive = .triangles
}

// =========================================================================
// MetalChartRenderer
// =========================================================================

/// Reads geometry + bg color from the engine each frame. The bg color is
/// pulled via `getStyleFloats` only when `styleRevision` changes; the rest
/// of the per-frame work is the same VBO upload + draw as before. NO state
/// is pushed in from Swift — the engine is the single source of truth.
final class MetalChartRenderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipelineState: MTLRenderPipelineState
  private let engine: ChartEngineBridge

  private var vertexBuffer: MTLBuffer?
  private var vertexBufferCapacityFloats: Int = 0

  private var passes: [PassEntry] = []
  private var lastSeenGeneration: Int = -1
  private var lastSeenStyleRevision: Int64 = -1
  private var lastSeenViewportRevision: Int64 = -2
  private var currentClearColor: MTLClearColor =
    MTLClearColorMake(11.0 / 255.0, 14.0 / 255.0, 20.0 / 255.0, 1.0)
  private var styleFloats = [Float](repeating: 0, count: 54)

  init(device: MTLDevice,
       colorPixelFormat: MTLPixelFormat,
       engine: ChartEngineBridge) {
    self.device = device
    self.engine = engine

    guard let queue = device.makeCommandQueue() else {
      fatalError("MetalChartRenderer: failed to create MTLCommandQueue")
    }
    self.commandQueue = queue

    // Shaders: `Classes/Shaders.metal` is compiled at **build** time into the
    // default library (requires Xcode Metal Toolchain). No runtime MSL compile.
    let library: MTLLibrary
    let frameworkBundle = Bundle(for: MetalChartRenderer.self)
    if let frameworkLib = try? device.makeDefaultLibrary(bundle: frameworkBundle) {
      library = frameworkLib
    } else if let defaultLib = device.makeDefaultLibrary() {
      library = defaultLib
    } else {
      fatalError(
        "MetalChartRenderer: no default Metal library. "
          + "Compile `Shaders.metal` with the Metal Toolchain (Xcode → Settings → Components), "
          + "ensure the podspec includes `*.metal`, then run `pod install`.",
      )
    }

    guard let vertexFunction = library.makeFunction(name: "chart_vertex_main"),
          let fragmentFunction = library.makeFunction(name: "chart_fragment_main") else {
      fatalError("MetalChartRenderer: chart_vertex_main / chart_fragment_main not found")
    }

    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat

    let attachment = pipelineDescriptor.colorAttachments[0]
    attachment?.isBlendingEnabled = true
    attachment?.rgbBlendOperation = .add
    attachment?.alphaBlendOperation = .add
    attachment?.sourceRGBBlendFactor = .sourceAlpha
    attachment?.sourceAlphaBlendFactor = .sourceAlpha
    attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
    attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha

    do {
      self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    } catch {
      fatalError("MetalChartRenderer: failed to create pipeline state: \(error)")
    }

    super.init()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    let styleRev = Int64(engine.styleRevision())
    if styleRev != lastSeenStyleRevision {
      lastSeenStyleRevision = styleRev
      styleFloats.withUnsafeMutableBufferPointer { buf in
        engine.getStyleFloats(buf.baseAddress!, floatCount: Int32(buf.count))
      }
      currentClearColor = MTLClearColorMake(
        Double(styleFloats[0]),
        Double(styleFloats[1]),
        Double(styleFloats[2]),
        Double(styleFloats[3])
      )
    }
    view.clearColor = currentClearColor
    guard let drawable = view.currentDrawable,
          let descriptor = view.currentRenderPassDescriptor else {
      return
    }
    descriptor.colorAttachments[0].loadAction = .clear
    descriptor.colorAttachments[0].storeAction = .store

    let vpRev = engine.viewportRevision()
    if vpRev != lastSeenViewportRevision {
      lastSeenViewportRevision = vpRev
      engine.rebuildGeometryForViewport()
    }

    let gen = Int(engine.generation())
    if gen != lastSeenGeneration {
      syncGeometryFromEngine()
      lastSeenGeneration = gen
    }

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
      return
    }

    encoder.setRenderPipelineState(pipelineState)

    var totalVertices = 0
    for p in passes { totalVertices += p.vertexCount }

    if let buffer = vertexBuffer, totalVertices > 0 {
      encoder.setVertexBuffer(buffer, offset: 0, index: 0)

      var raw = [Float](repeating: 0, count: 16)
      raw.withUnsafeMutableBufferPointer { ptr in
        guard let base = ptr.baseAddress else { return }
        ViewportEngineBridge(handle: engine.viewportHandle, owns: false).getProjectionMatrix(base)
      }
      var uniforms = ChartUniforms(projection: simd_float4x4(columnMajor: raw))
      encoder.setVertexBytes(&uniforms,
                             length: MemoryLayout<ChartUniforms>.stride,
                             index: 1)

      var offset = 0
      for p in passes where p.vertexCount > 0 {
        encoder.drawPrimitives(type: p.primitive.metal,
                               vertexStart: offset,
                               vertexCount: p.vertexCount)
        offset += p.vertexCount
      }
    }

    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func syncGeometryFromEngine() {
    let passCount = Int(engine.passCount())
    while passes.count < passCount {
      passes.append(PassEntry())
    }
    var totalFloats = 0
    for i in 0..<passCount {
      let count = readPass(i, into: &passes[i])
      passes[i].vertexCount = count
      totalFloats += count * 6
    }
    for i in passCount..<passes.count {
      passes[i].vertexCount = 0
    }
    if totalFloats == 0 { return }
    ensureVertexBuffer(capacityFloats: totalFloats)
    guard let buffer = vertexBuffer else { return }
    let dst = buffer.contents().bindMemory(to: Float.self, capacity: totalFloats)
    var written = 0
    for p in passes where p.vertexCount > 0 {
      let n = p.vertexCount * 6
      p.vertices.withUnsafeBufferPointer { src in
        dst.advanced(by: written).assign(from: src.baseAddress!, count: n)
      }
      written += n
    }
  }

  private func readPass(_ pass: Int, into entry: inout PassEntry) -> Int {
    var primRaw: Int32 = 0
    let needed = withUnsafeMutablePointer(to: &primRaw) { primPtr -> Int in
      Int(engine.readPass(Int32(pass),
                          outPrimitive: primPtr,
                          outVertices: nil,
                          capacity: 0))
    }
    if needed <= 0 { return 0 }
    let requiredFloats = needed * 6
    if entry.vertices.count < requiredFloats {
      entry.vertices = [Float](repeating: 0, count: requiredFloats + 256)
    }
    let count = entry.vertices.withUnsafeMutableBufferPointer { buf -> Int in
      withUnsafeMutablePointer(to: &primRaw) { primPtr -> Int in
        Int(engine.readPass(Int32(pass),
                            outPrimitive: primPtr,
                            outVertices: buf.baseAddress!,
                            capacity: Int32(buf.count)))
      }
    }
    entry.primitive = ChartPrimitive(rawValue: Int(primRaw)) ?? .triangles
    return count
  }

  private func ensureVertexBuffer(capacityFloats: Int) {
    if let _ = vertexBuffer, vertexBufferCapacityFloats >= capacityFloats { return }
    let newCap = max(capacityFloats + 1024, 1024)
    vertexBuffer = device.makeBuffer(
      length: newCap * MemoryLayout<Float>.size,
      options: [.storageModeShared],
    )
    vertexBufferCapacityFloats = newCap
  }
}

// =========================================================================
// ChartOverlayView — native (UIKit) layer for axis labels, legend, tooltip
//
// Pulls all visual state directly from the engine via the Obj-C bridge.
// Repaint is driven by polling `styleRevision`, `viewportRevision`,
// `generation`, and `hover` on each CADisplayLink tick. No MethodChannel
// is involved past the initial handle handshake.
// =========================================================================

final class ChartOverlayView: UIView {
  private let engine: ChartEngineBridge
  private var displayLink: CADisplayLink?

  private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss"
    return f
  }()

  private let dateFormatterMs: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss.SSS"
    return f
  }()

  private var dynamicYDecimals: Int = 2
  private var useMsForX: Bool = false

  private var xTicks: [Double] = []
  private var yTicks: [Double] = []
  private var hover: Int = -1
  private var hoverCandle: [Double] = [0, 0, 0, 0, 0, 0]
  private var hoverValid: Bool = false

  private var lastGeneration: Int = -2
  private var lastViewportRevision: Int64 = -1
  private var lastStyleRevision: Int64 = -1
  private var lastHover: Int = -2

  private var styleFloats = [Float](repeating: 0, count: 58)
  private var styleInts = [Int32](repeating: 0, count: 15)

  /** While true, tooltip + marker use [scrubPoint] (finger scrub when x-pan locked). */
  private var scrubActive = false
  private var scrubPoint = CGPoint.zero

  // Style state mirrored from the engine.
  private var showGrid = true
  private var showXAxis = true
  private var showYAxis = true
  private var showCrosshair = true
  private var showTooltip = true
  private var showLegend = true
  private var yDecimals: Int = 2
  private var xIsTimestampMs: Bool = true
  private var seriesLabel: String = "CANDLE"
  private var showCurrentPriceLine: Bool = true

  /// Plot area matching the MTKView; labels + axis frame align to this. Set by `ChartHostView`.
  var plotContentFrame: CGRect = .zero

  private var axisTextColor: UIColor = UIColor(white: 0.55, alpha: 1.0)
  private var gridLineColor: UIColor = UIColor(white: 0.35, alpha: 0.45)
  private var legendTextColor: UIColor = UIColor(red: 0.486, green: 1.0, blue: 0.698, alpha: 1.0)
  private var tooltipBg: UIColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 0.95)
  private var tooltipText: UIColor = .white
  private var crosshair: UIColor = UIColor(red: 1.0, green: 0.85, blue: 0.40, alpha: 1.0)
  private var currentPriceLineColor: UIColor = UIColor(red: 0.486, green: 1.0, blue: 0.698, alpha: 0.75)

  init(frame: CGRect, engine: ChartEngineBridge) {
    self.engine = engine
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
    clipsToBounds = false
    contentMode = .redraw
  }

  required init?(coder: NSCoder) { fatalError() }

  func setScrubAnchor(active: Bool, x: CGFloat, y: CGFloat) {
    scrubActive = active
    scrubPoint = CGPoint(x: x, y: y)
    setNeedsDisplay()
  }

  func clearScrubAnchor() {
    setScrubAnchor(active: false, x: 0, y: 0)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      pullStyleFromEngine()
      refreshTicks()
      let link = CADisplayLink(target: self, selector: #selector(tick))
      link.add(to: .main, forMode: .common)
      displayLink = link
    } else {
      displayLink?.invalidate()
      displayLink = nil
    }
  }

  @objc private func tick() {
    let gen = Int(engine.generation())
    let rev = Int64(engine.viewportRevision())
    let styleRev = Int64(engine.styleRevision())
    let hov = Int(engine.hover())
    var changed = false
    if styleRev != lastStyleRevision {
      lastStyleRevision = styleRev
      pullStyleFromEngine()
      refreshTicks()
      changed = true
    }
    if gen != lastGeneration || rev != lastViewportRevision || hov != lastHover {
      lastGeneration = gen
      lastViewportRevision = rev
      lastHover = hov
      hover = hov
      if hov >= 0 {
        var c: [Double] = [0, 0, 0, 0, 0, 0]
        let ok = c.withUnsafeMutableBufferPointer { buf -> Int32 in
          engine.getCandle(Int32(hov), out6: buf.baseAddress!)
        }
        hoverValid = ok == 1
        hoverCandle = c
      } else {
        hoverValid = false
      }
      refreshTicks()
      changed = true
    }
    if changed { setNeedsDisplay() }
  }

  /// Pulls the engine's current style and mirrors the fields we render here.
  /// Replaces the previous MethodChannel-driven `applyStyle` flow.
  private func pullStyleFromEngine() {
    styleFloats.withUnsafeMutableBufferPointer { buf in
      engine.getStyleFloats(buf.baseAddress!, floatCount: Int32(buf.count))
    }
    styleInts.withUnsafeMutableBufferPointer { buf in
      engine.getStyleInts(buf.baseAddress!, intCount: Int32(buf.count))
    }
    showGrid = styleInts[0] != 0
    showXAxis = styleInts[1] != 0
    showYAxis = styleInts[2] != 0
    showCrosshair = styleInts[3] != 0
    showTooltip = styleInts[4] != 0
    showLegend = styleInts[5] != 0
    yDecimals = Int(styleInts[8])
    xIsTimestampMs = styleInts[9] != 0
    showCurrentPriceLine = styleInts[14] != 0
    seriesLabel = engine.seriesLabel()
    if seriesLabel.isEmpty { seriesLabel = "SERIES" }

    axisTextColor = colorFromRgba(offset: 8)
    gridLineColor = colorFromRgba(offset: 4)
    crosshair = colorFromRgba(offset: 32)
    tooltipBg = colorFromRgba(offset: 36)
    tooltipText = colorFromRgba(offset: 40)
    legendTextColor = colorFromRgba(offset: 44)
    currentPriceLineColor = colorFromRgba(offset: 54)
  }

  private func colorFromRgba(offset: Int) -> UIColor {
    let r = CGFloat(styleFloats[offset])
    let g = CGFloat(styleFloats[offset + 1])
    let b = CGFloat(styleFloats[offset + 2])
    let a = CGFloat(styleFloats[offset + 3])
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }

  private func refreshTicks() {
    let xCount = Int(engine.getXTicks(nil, maxCount: 0))
    let yCount = Int(engine.getYTicks(nil, maxCount: 0))
    if xCount > 0 {
      xTicks = [Double](repeating: 0, count: xCount)
      _ = xTicks.withUnsafeMutableBufferPointer { buf -> Int32 in
        engine.getXTicks(buf.baseAddress, maxCount: Int32(buf.count))
      }
    } else {
      xTicks.removeAll()
    }
    if yCount > 0 {
      yTicks = [Double](repeating: 0, count: yCount)
      _ = yTicks.withUnsafeMutableBufferPointer { buf -> Int32 in
        engine.getYTicks(buf.baseAddress, maxCount: Int32(buf.count))
      }
    } else {
      yTicks.removeAll()
    }

    dynamicYDecimals = yDecimals
    if yTicks.count > 1 {
      let step = abs(yTicks[1] - yTicks[0])
      if step > 0 {
        let req = Int(ceil(-log10(step)))
        dynamicYDecimals = max(yDecimals, req)
      }
    }

    useMsForX = false
    if xTicks.count > 1 {
      let step = abs(xTicks[1] - xTicks[0])
      if step < 1000.0 {
        useMsForX = true
      }
    }
  }

  private static let ndcTol = 1.0e-5

  /// True when projected NDC is inside the clip (allows tiny FP drift at edges).
  private func ndcOnChartPlane(_ v: Double) -> Bool {
    v >= -1.0 - Self.ndcTol && v <= 1.0 + Self.ndcTol
  }

  override func draw(_ rect: CGRect) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }
    let w = bounds.width
    let h = bounds.height
    if w <= 0 || h <= 0 { return }
    let plot = (plotContentFrame.width >= 8 && plotContentFrame.height >= 8) ? plotContentFrame : bounds
    let pw = plot.width
    let ph = plot.height

    let axisAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: axisTextColor,
    ]
    let tooltipAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: tooltipText,
    ]
    let legendAttrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 11, weight: .heavy),
      .foregroundColor: legendTextColor,
    ]

    if (showXAxis || showYAxis) && plot.width > 0 && plot.height > 0 {
      ctx.saveGState()
      ctx.setStrokeColor(gridLineColor.cgColor)
      ctx.setLineWidth(1.0 / max(contentScaleFactor, 1.0))
      if showXAxis {
        ctx.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        ctx.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
      }
      if showYAxis {
        ctx.move(to: CGPoint(x: plot.minX, y: plot.minY))
        ctx.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
      }
      ctx.strokePath()
      ctx.restoreGState()
    }

    if showXAxis && !xTicks.isEmpty {
      let axisFont = axisAttrs[.font] as? UIFont ?? UIFont.systemFont(ofSize: 11, weight: .medium)
      var ndc = [Double](repeating: 0, count: xTicks.count)
      xTicks.withUnsafeBufferPointer { src in
        ndc.withUnsafeMutableBufferPointer { dst in
          guard let s = src.baseAddress, let d = dst.baseAddress else { return }
          engine.projectX(s, count: Int32(xTicks.count), outNdc: d)
        }
      }
      let gutter: CGFloat = 4
      var xBaseline = plot.maxY + gutter + axisFont.ascender
      xBaseline = min(xBaseline, h - gutter + axisFont.descender)
      var lastRight = CGFloat(-CGFloat.greatestFiniteMagnitude)
      let minGap: CGFloat = 8
      for (i, value) in ndc.enumerated() {
        if !ndcOnChartPlane(value) { continue }
        let px = plot.minX + CGFloat((value + 1.0) * 0.5) * pw
        let label = formatX(xTicks[i]) as NSString
        let tw = label.size(withAttributes: axisAttrs).width
        let tx = min(max(gutter, px - tw / 2), w - tw - gutter)
        if tx < lastRight + minGap {
          continue
        }
        label.draw(at: CGPoint(x: tx, y: xBaseline), withAttributes: axisAttrs)
        lastRight = tx + tw
      }
    }

    if showYAxis && !yTicks.isEmpty {
      let axisFont = axisAttrs[.font] as? UIFont ?? UIFont.systemFont(ofSize: 11, weight: .medium)
      var ndc = [Double](repeating: 0, count: yTicks.count)
      yTicks.withUnsafeBufferPointer { src in
        ndc.withUnsafeMutableBufferPointer { dst in
          guard let s = src.baseAddress, let d = dst.baseAddress else { return }
          engine.projectY(s, count: Int32(yTicks.count), outNdc: d)
        }
      }

      struct YRow {
        var py: CGFloat
        var baselineY: CGFloat
        var label: NSString
      }

      var rows = [YRow]()
      rows.reserveCapacity(yTicks.count)
      for (i, value) in ndc.enumerated() where ndcOnChartPlane(value) {
        let py = plot.minY + CGFloat(1.0 - (value + 1.0) * 0.5) * ph
        let baselineY = py + (axisFont.ascender + axisFont.descender) / 2
        rows.append(YRow(py: py, baselineY: baselineY, label: formatY(yTicks[i]) as NSString))
      }
      rows.sort { $0.py < $1.py }

      let minYGap: CGFloat = 9
      var lastInkBottom: CGFloat?
      let gutter: CGFloat = 4

      for item in rows {
        let tw = item.label.size(withAttributes: axisAttrs).width
        let tx = max(gutter, plot.minX - gutter - tw)
        let textTop = item.baselineY - axisFont.ascender
        if let lb = lastInkBottom, textTop < lb + minYGap {
          continue
        }
        item.label.draw(at: CGPoint(x: tx, y: item.baselineY), withAttributes: axisAttrs)
        lastInkBottom = item.baselineY - axisFont.descender
      }
    }

    if showCurrentPriceLine {
      let count = Int(engine.candleCount())
      if count > 0 {
        var c = [Double](repeating: 0, count: 6)
        let ok = c.withUnsafeMutableBufferPointer { buf -> Int32 in
          engine.getCandle(Int32(count - 1), out6: buf.baseAddress!)
        }
        if ok == 1 {
          let closePrice = c[4]
          var yIn = [closePrice]
          var yOut = [0.0]
          yIn.withUnsafeBufferPointer { src in
            yOut.withUnsafeMutableBufferPointer { dst in
              engine.projectY(src.baseAddress!, count: 1, outNdc: dst.baseAddress!)
            }
          }
          if ndcOnChartPlane(yOut[0]) {
            let py = plot.minY + CGFloat(1.0 - (yOut[0] + 1.0) * 0.5) * ph
            let label = formatY(closePrice) as NSString
            let badgeFont = tooltipAttrs[.font] as? UIFont ?? UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
              .font: badgeFont,
              .foregroundColor: tooltipText,
            ]
            let size = label.size(withAttributes: badgeAttrs)
            let gutter: CGFloat = 4
            let padX: CGFloat = 4
            let padY: CGFloat = 2
            let badgeRect = CGRect(x: plot.minX - gutter - size.width - padX * 2,
                                   y: py - size.height / 2 - padY,
                                   width: size.width + padX * 2,
                                   height: size.height + padY * 2)
            
            ctx.saveGState()
            ctx.setFillColor(currentPriceLineColor.cgColor)
            let path = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4)
            path.fill()
            ctx.restoreGState()
            
            label.draw(at: CGPoint(x: badgeRect.minX + padX, y: badgeRect.minY + padY), withAttributes: badgeAttrs)
          }
        }
      }
    }

    if showLegend {
      let count = Int(engine.candleCount())
      let txt = "\(seriesLabel)  ·  \(count)" as NSString
      let size = txt.size(withAttributes: legendAttrs)
      let padX: CGFloat = 10
      let padY: CGFloat = 6
      let bgRect = CGRect(x: 12, y: 12, width: size.width + padX * 2, height: size.height + padY * 2)
      ctx.saveGState()
      ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
      let path = UIBezierPath(roundedRect: bgRect, cornerRadius: 6)
      path.fill()
      ctx.restoreGState()
      txt.draw(at: CGPoint(x: bgRect.minX + padX, y: bgRect.minY + padY),
               withAttributes: legendAttrs)
    }

    if showTooltip && hoverValid {
      drawTooltip(in: ctx,
                  width: w, height: h,
                  plot: plot,
                  tooltipAttrs: tooltipAttrs)
    }
  }

  private func drawTooltip(in ctx: CGContext,
                           width w: CGFloat, height h: CGFloat,
                           plot: CGRect,
                           tooltipAttrs: [NSAttributedString.Key: Any]) {
    let ts = hoverCandle[0]
    let o = hoverCandle[1]
    let hi = hoverCandle[2]
    let lo = hoverCandle[3]
    let cl = hoverCandle[4]
    let vol = hoverCandle[5]

    var tsIn = [ts]
    var tsOut = [0.0]
    tsIn.withUnsafeBufferPointer { src in
      tsOut.withUnsafeMutableBufferPointer { dst in
        guard let s = src.baseAddress, let d = dst.baseAddress else { return }
        engine.projectX(s, count: 1, outNdc: d)
      }
    }
    let pw = max(plot.width, 1)
    let ph = max(plot.height, 1)
    let snapMarkerX = plot.minX + CGFloat((tsOut[0] + 1.0) * 0.5) * pw

    var yIn = [cl]
    var yOut = [0.0]
    yIn.withUnsafeBufferPointer { src in
      yOut.withUnsafeMutableBufferPointer { dst in
        guard let s = src.baseAddress, let d = dst.baseAddress else { return }
        engine.projectY(s, count: 1, outNdc: d)
      }
    }
    let snapMarkerY = plot.minY + CGFloat(1.0 - (yOut[0] + 1.0) * 0.5) * ph

    let markerX = scrubActive
      ? min(max(scrubPoint.x, plot.minX), plot.maxX)
      : snapMarkerX
    let markerY = scrubActive
      ? min(max(scrubPoint.y, plot.minY), plot.maxY)
      : snapMarkerY

    if markerX >= plot.minX && markerX <= plot.maxX && markerY >= plot.minY && markerY <= plot.maxY {
      ctx.saveGState()
      ctx.setFillColor(crosshair.cgColor)
      ctx.addEllipse(in: CGRect(x: markerX - 4, y: markerY - 4, width: 8, height: 8))
      ctx.fillPath()
      ctx.restoreGState()
    }

    let lines = [
      "TIME  \(formatX(ts))",
      "O     \(formatY(o))",
      "H     \(formatY(hi))",
      "L     \(formatY(lo))",
      "C     \(formatY(cl))",
      "VOL   \(formatVol(vol))",
    ]
    var maxW: CGFloat = 0
    for l in lines {
      let s = l as NSString
      maxW = max(maxW, s.size(withAttributes: tooltipAttrs).width)
    }
    let pad: CGFloat = 10
    let lineH: CGFloat = 16
    let boxW = maxW + pad * 2
    let boxH = lineH * CGFloat(lines.count) + pad * 2
    let placeOnLeft = markerX > w * 0.5
    let boxX: CGFloat = placeOnLeft
      ? max(6, markerX - 16 - boxW)
      : min(w - boxW - 6, markerX + 16)
    // Tooltip reads like a HUD: pin to plot top so it does not bob with close price on Y—only shifts on X with the bar.
    let topAnchor = plot.minY + 6
    let boxY = min(max(topAnchor, 6), h - boxH - 6)
    let box = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)

    ctx.saveGState()
    ctx.setFillColor(tooltipBg.cgColor)
    let path = UIBezierPath(roundedRect: box, cornerRadius: 8)
    path.fill()
    ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
    path.lineWidth = 1
    path.stroke()
    ctx.restoreGState()

    var y = box.minY + pad
    for line in lines {
      (line as NSString).draw(at: CGPoint(x: box.minX + pad, y: y),
                               withAttributes: tooltipAttrs)
      y += lineH
    }
  }

  private func formatX(_ v: Double) -> String {
    if xIsTimestampMs {
      let fmt = useMsForX ? dateFormatterMs : dateFormatter
      return fmt.string(from: Date(timeIntervalSince1970: v / 1000.0))
    }
    return formatY(v)
  }

  private func formatY(_ v: Double) -> String {
    String(format: "%.\(max(0, dynamicYDecimals))f", v)
  }

  private func formatVol(_ v: Double) -> String {
    if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
    return String(Int64(v))
  }
}

// =========================================================================
// ChartHostView — UIView that owns MTKView, overlay, gestures
// =========================================================================

final class ChartHostView: UIView, UIGestureRecognizerDelegate {

  /// Margins around the Metal plot: left for Y-axis labels; top for legend; bottom for X labels; tight right edge.
  private struct PlotMargins {
    static let top: CGFloat = 36
    static let left: CGFloat = 54
    static let bottom: CGFloat = 26
    static let right: CGFloat = 4
  }

  /// Visible plot rect (series + grid + crosshair) so pan/zoom use the same box as the axes.
  static func plotContentRect(for hostBounds: CGRect) -> CGRect {
    let r = hostBounds.inset(
      by: UIEdgeInsets(
        top: PlotMargins.top,
        left: PlotMargins.left,
        bottom: PlotMargins.bottom,
        right: PlotMargins.right
      )
    )
    if r.width < 48 || r.height < 48 {
      return hostBounds.insetBy(dx: 6, dy: 28)
    }
    return r
  }

  let mtkView: MTKView
  let viewportBridge: ViewportEngineBridge
  let engine: ChartEngineBridge
  let overlay: ChartOverlayView

  /// Locked at pinch start: wider horizontal finger span ⇒ zoom X; else zoom Y.
  private var pinchZoomsHorizontalAxis = true

  private var interactionStyleInts = [Int32](repeating: 0, count: 16)

  init(frame: CGRect,
       mtkView: MTKView,
       engine: ChartEngineBridge,
       viewportBridge: ViewportEngineBridge,
       overlay: ChartOverlayView) {
    self.mtkView = mtkView
    self.viewportBridge = viewportBridge
    self.engine = engine
    self.overlay = overlay
    super.init(frame: frame)

    clipsToBounds = false

    mtkView.frame = Self.plotContentRect(for: bounds)
    mtkView.autoresizingMask = []
    addSubview(mtkView)

    overlay.frame = bounds
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(overlay)

    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    pan.delegate = self
    pan.maximumNumberOfTouches = 1
    addGestureRecognizer(pan)

    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    pinch.delegate = self
    addGestureRecognizer(pinch)

    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
    doubleTap.numberOfTapsRequired = 2
    addGestureRecognizer(doubleTap)

    let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
    singleTap.numberOfTapsRequired = 1
    singleTap.delegate = self
    singleTap.require(toFail: doubleTap)
    addGestureRecognizer(singleTap)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    let plot = Self.plotContentRect(for: bounds)
    mtkView.frame = plot
    overlay.frame = bounds
    overlay.plotContentFrame = plot
  }

  private func plotRectForGestures() -> CGRect {
    Self.plotContentRect(for: bounds)
  }

  /// Maps a touch in this view to NDC matching the MTKView plot (clamped to plot edges).
  private func touchToNDC(_ p: CGPoint) -> (x: Double, y: Double) {
    let r = plotRectForGestures()
    let rw = max(Double(r.width), 1.0)
    let rh = max(Double(r.height), 1.0)
    let nx = min(max((Double(p.x) - Double(r.minX)) / rw, 0.0), 1.0)
    let ny = min(max((Double(p.y) - Double(r.minY)) / rh, 0.0), 1.0)
    let xNDC = 2.0 * nx - 1.0
    let yNDC = 1.0 - 2.0 * ny
    return (xNDC, yNDC)
  }

  private func pullInteractionFlags() -> (allowPanX: Bool, allowPanY: Bool, allowZoomX: Bool, allowZoomY: Bool) {
    interactionStyleInts.withUnsafeMutableBufferPointer { buf in
      engine.getStyleInts(buf.baseAddress!, intCount: Int32(buf.count))
    }
    return (
      interactionStyleInts[10] != 0,
      interactionStyleInts[11] != 0,
      interactionStyleInts[12] != 0,
      interactionStyleInts[13] != 0
    )
  }

  private func scrubHover(at locationInHost: CGPoint) {
    let plot = plotRectForGestures()
    guard plot.contains(locationInHost) else {
      engine.setHover(-1)
      overlay.clearScrubAnchor()
      return
    }
    let xNDC = touchToNDC(locationInHost).x
    var xMin = 0.0
    var xMax = 0.0
    viewportBridge.getVisibleDomain(&xMin, xMax: &xMax)
    let xData = xMin + (xNDC + 1.0) * 0.5 * (xMax - xMin)
    let idx = engine.hitTest(xData)
    if idx >= 0 {
      engine.setHover(Int32(idx))
      overlay.setScrubAnchor(active: true, x: locationInHost.x, y: locationInHost.y)
    } else {
      engine.setHover(-1)
      overlay.clearScrubAnchor()
    }
  }

  @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
    if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
      overlay.clearScrubAnchor()
      let ia = pullInteractionFlags()
      if !ia.allowPanX {
        engine.setHover(-1)
      }
      return
    }
    guard recognizer.state == .began || recognizer.state == .changed else { return }
    let ia = pullInteractionFlags()
    let t = recognizer.translation(in: self)
    recognizer.setTranslation(.zero, in: self)
    let r = plotRectForGestures()
    let rw = max(Double(r.width), 1.0)
    let rh = max(Double(r.height), 1.0)
    let dxNDC = 2.0 * Double(t.x) / rw
    let dyNDC = 2.0 * Double(t.y) / rh
    let panXAmt = ia.allowPanX ? dxNDC : 0.0
    let panYAmt = ia.allowPanY ? dyNDC : 0.0
    if panXAmt != 0.0 || panYAmt != 0.0 {
      viewportBridge.panNDC(withDx: panXAmt, dy: panYAmt)
    }
    if !ia.allowPanX {
      let loc = recognizer.location(in: self)
      scrubHover(at: loc)
    } else if engine.hover() >= 0 {
      engine.setHover(-1)
    }
  }

  @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
    if recognizer.state == .began {
      if recognizer.numberOfTouches >= 2 {
        let p0 = recognizer.location(ofTouch: 0, in: self)
        let p1 = recognizer.location(ofTouch: 1, in: self)
        pinchZoomsHorizontalAxis = abs(p0.x - p1.x) >= abs(p0.y - p1.y)
      }
      return
    }
    guard recognizer.state == .changed else { return }
    let ia = pullInteractionFlags()
    let scale = Double(recognizer.scale)
    recognizer.scale = 1.0
    let focus = recognizer.location(in: self)
    let ndc = touchToNDC(focus)
    if pinchZoomsHorizontalAxis {
      guard ia.allowZoomX else { return }
      viewportBridge.zoomNDC(withScaleX: scale, scaleY: 1.0, focusX: ndc.x, focusY: 0)
    } else {
      guard ia.allowZoomY else { return }
      viewportBridge.zoomNDC(withScaleX: 1.0, scaleY: scale, focusX: 0, focusY: ndc.y)
    }
    if engine.hover() >= 0 {
      engine.setHover(-1)
    }
    overlay.clearScrubAnchor()
  }

  @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
    interactionStyleInts.withUnsafeMutableBufferPointer { buf in
      engine.getStyleInts(buf.baseAddress!, intCount: Int32(buf.count))
    }
    let allowDoubleTapReset = interactionStyleInts[15] != 0
    if allowDoubleTapReset {
      viewportBridge.reset()
    }
    engine.setHover(-1)
    overlay.clearScrubAnchor()
  }

  @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
    overlay.clearScrubAnchor()
    let loc = recognizer.location(in: self)
    let plot = plotRectForGestures()
    if !plot.contains(loc) {
      engine.setHover(-1)
      return
    }
    let xNDC = touchToNDC(loc).x
    var xMin = 0.0
    var xMax = 0.0
    viewportBridge.getVisibleDomain(&xMin, xMax: &xMax)
    let xData = xMin + (xNDC + 1.0) * 0.5 * (xMax - xMin)
    let idx = Int(engine.hitTest(xData))
    if idx >= 0 {
      let current = Int(engine.hover())
      engine.setHover(current == idx ? -1 : Int32(idx))
    } else {
      engine.setHover(-1)
    }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    true
  }
}

// =========================================================================
// ChartPlatformView — Flutter PlatformView wrapper
//
// The MethodChannel exposes exactly ONE method: `getEngineHandle`.
// That hands the engine pointer to Dart so all data + style updates can
// flow over FFI. After the handshake, Flutter's main isolate is uninvolved
// in any chart interaction.
// =========================================================================

class ChartPlatformView: NSObject, FlutterPlatformView {
  private let hostView: ChartHostView
  private let renderer: MetalChartRenderer
  private let engine: ChartEngineBridge
  private let viewportBridge: ViewportEngineBridge
  private let overlay: ChartOverlayView
  private let methodChannel: FlutterMethodChannel

  init(frame: CGRect,
       viewIdentifier viewId: Int64,
       arguments args: Any?,
       messenger: FlutterBinaryMessenger) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      fatalError("ChartPlatformView: Metal is not available on this device")
    }

    let mtkView = MTKView(frame: frame, device: device)
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.framebufferOnly = true
    mtkView.clearColor = MTLClearColorMake(11.0 / 255.0, 14.0 / 255.0, 20.0 / 255.0, 1.0)
    mtkView.isPaused = false
    mtkView.enableSetNeedsDisplay = false

    let engine = ChartEngineBridge()
    self.engine = engine
    let viewport = ViewportEngineBridge(handle: engine.viewportHandle, owns: false)
    self.viewportBridge = viewport

    let renderer = MetalChartRenderer(device: device,
                                      colorPixelFormat: mtkView.colorPixelFormat,
                                      engine: engine)
    self.renderer = renderer
    mtkView.delegate = renderer

    let overlay = ChartOverlayView(frame: frame, engine: engine)
    self.overlay = overlay

    self.hostView = ChartHostView(frame: frame,
                                  mtkView: mtkView,
                                  engine: engine,
                                  viewportBridge: viewport,
                                  overlay: overlay)

    self.methodChannel = FlutterMethodChannel(
      name: "\(kChannelPrefix)/\(viewId)",
      binaryMessenger: messenger,
    )

    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable",
                            message: "view deallocated",
                            details: nil))
        return
      }
      switch call.method {
      case "getEngineHandle":
        result(NSNumber(value: Int64(self.engine.handle)))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    methodChannel.setMethodCallHandler(nil)
  }

  func view() -> UIView { hostView }
}

class ChartPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect,
              viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    ChartPlatformView(frame: frame,
                      viewIdentifier: viewId,
                      arguments: args,
                      messenger: messenger)
  }
}
