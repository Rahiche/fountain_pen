// cjk_glyphs.swift: a CJK font's glyphs for their strokes to be traced
// (strokes_cjk.py). Fonts built from overlapping strokes keep each stroke
// (or a few) as its own outline: each outline, with any holes it has, is
// rasterised on its own, so strokes that cross never tangle.
//   swift cjk_glyphs.swift <font> <chars.txt> <out dir> [weight]
// → <out dir>/shapes.bin (one bit a pixel) and meta.json: per glyph its
// advance and, per outline, its raster's size, where the glyph's origin is
// in it (rows from the top) and where its bits start.
import CoreGraphics
import CoreText
import Foundation

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1])
let chars = Array(try! String(contentsOfFile: args[2], encoding: .utf8).filter { !$0.isWhitespace })
let out = URL(fileURLWithPath: args[3])
var desc = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor])[0]
if args.count > 4, let w = Double(args[4]) {
  desc = CTFontDescriptorCreateCopyWithVariation(desc, NSNumber(value: 0x7767_6874), CGFloat(w))  // 'wght'
}
let S: CGFloat = 256  // px per em
let pad: CGFloat = 6
let font = CTFontCreateWithFontDescriptor(desc, S, nil)

struct Outline {
  let path = CGMutablePath()
  var pts: [CGPoint] = []
  var area: CGFloat = 0
  var box: CGRect { path.boundingBoxOfPath }
}

func mix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { mix(mix(a, c, t), mix(c, b, t), t) }
func cubic(_ a: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
  mix(quad(a, c1, c2, t), quad(c1, c2, b, t), t)
}

func outlines(_ path: CGPath) -> [Outline] {
  var res: [Outline] = []
  var last = CGPoint.zero
  path.applyWithBlock { e in
    let p = e.pointee
    switch p.type {
    case .moveToPoint:
      var o = Outline()
      o.path.move(to: p.points[0])
      o.pts = [p.points[0]]
      res.append(o)
      last = p.points[0]
    case .addLineToPoint:
      res[res.count - 1].path.addLine(to: p.points[0])
      res[res.count - 1].pts.append(p.points[0])
      last = p.points[0]
    case .addQuadCurveToPoint:
      res[res.count - 1].path.addQuadCurve(to: p.points[1], control: p.points[0])
      for i in 1...8 { res[res.count - 1].pts.append(quad(last, p.points[0], p.points[1], CGFloat(i) / 8)) }
      last = p.points[1]
    case .addCurveToPoint:
      res[res.count - 1].path.addCurve(to: p.points[2], control1: p.points[0], control2: p.points[1])
      for i in 1...12 { res[res.count - 1].pts.append(cubic(last, p.points[0], p.points[1], p.points[2], CGFloat(i) / 12)) }
      last = p.points[2]
    case .closeSubpath:
      res[res.count - 1].path.closeSubpath()
    @unknown default: break
    }
  }
  for i in res.indices {
    let q = res[i].pts
    var a: CGFloat = 0
    for k in q.indices { let p0 = q[k], p1 = q[(k + 1) % q.count]; a += p0.x * p1.y - p1.x * p0.y }
    res[i].area = a / 2
  }
  return res.filter { abs($0.area) > 0.5 }
}

var blob = Data()
var meta: [[String: Any]] = []
for ch in chars {
  var u = Array(String(ch).utf16), g = [CGGlyph](repeating: 0, count: u.count)
  guard CTFontGetGlyphsForCharacters(font, &u, &g, u.count), g[0] != 0 else { continue }
  var adv = CGSize.zero
  CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
  guard let path = CTFontCreatePathForGlyph(font, g[0], nil) else { continue }
  let os = outlines(path)
  // A hole: inside another outline and wound the other way.
  var holeOf = [Int?](repeating: nil, count: os.count)
  for i in os.indices {
    var best: Int? = nil
    for j in os.indices where j != i && abs(os[j].area) > abs(os[i].area) && (os[i].area > 0) != (os[j].area > 0) {
      guard os[j].box.insetBy(dx: -1, dy: -1).contains(os[i].box) else { continue }
      let step = max(1, os[i].pts.count / 8)
      let inside = stride(from: 0, to: os[i].pts.count, by: step).allSatisfy { os[j].path.contains(os[i].pts[$0], using: .winding) }
      if inside && (best == nil || abs(os[j].area) < abs(os[best!].area)) { best = j }
    }
    holeOf[i] = best
  }
  var shapes: [[String: Any]] = []
  for i in os.indices where holeOf[i] == nil {
    let holes = os.indices.filter { holeOf[$0] == i }
    let bb = os[i].box
    let w = Int(ceil(bb.width + 2 * pad)), h = Int(ceil(bb.height + 2 * pad))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: pad - bb.minX, y: pad - bb.minY)
    ctx.addPath(os[i].path)
    for k in holes { ctx.addPath(os[k].path) }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fillPath(using: .winding)
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    var bits = [UInt8](repeating: 0, count: (w * h + 7) / 8)
    for k in 0..<(w * h) where px[k] > 127 { bits[k >> 3] |= UInt8(0x80 >> (k & 7)) }
    shapes.append(["off": blob.count, "w": w, "h": h, "ox": Double(pad - bb.minX), "oy": Double(CGFloat(h) - (pad - bb.minY)),
                   "holes": holes.count])
    blob.append(contentsOf: bits)
  }
  meta.append(["code": Int(ch.unicodeScalars.first!.value), "char": String(ch), "adv": Double(adv.width / S), "shapes": shapes])
}
try! blob.write(to: out.appendingPathComponent("shapes.bin"))
let space = { () -> Double in
  var u: [UniChar] = [32], g: [CGGlyph] = [0], a = CGSize.zero
  CTFontGetGlyphsForCharacters(font, &u, &g, 1)
  CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &a, 1)
  return Double(a.width / S)
}()
let info: [String: Any] = ["S": Double(S), "ascent": Double(CTFontGetAscent(font) / S), "descent": Double(CTFontGetDescent(font) / S),
                           "xHeight": Double(CTFontGetXHeight(font) / S), "space": space, "glyphs": meta]
try! JSONSerialization.data(withJSONObject: info).write(to: out.appendingPathComponent("meta.json"))
print("glyphs: \(meta.count) of \(chars.count), outlines: \(meta.reduce(0) { $0 + ($1["shapes"] as! [Any]).count }), \(blob.count / 1024) KB")
