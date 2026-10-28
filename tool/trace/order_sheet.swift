// order_sheet.swift: a traced hand's strokes drawn to check them: each
// stroke numbered where it starts, in the order it's written, an arrow
// where it ends.
//   swift order_sheet.swift <strokes.json> "<characters>" <out.png> [columns]
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let hand = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
let glyphs = hand["glyphs"] as! [String: Any]
let chars = Array(args[2]).map(String.init)
let cols = args.count > 4 ? Int(args[4])! : 10
let cell = 200.0, em = 150.0
let rows = (chars.count + cols - 1) / cols
let W = Int(cell) * cols, H = Int(cell) * rows
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let label = CTFontCreateWithName("Helvetica-Bold" as CFString, 13, nil)
let small = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
func colour(_ i: Int, _ n: Int) -> CGColor {
  let t = n > 1 ? Double(i) / Double(n - 1) : 0
  return CGColor(red: 0.85 * (1 - t) + 0.1 * t, green: 0.25 + 0.3 * sin(t * .pi), blue: 0.15 + 0.75 * t, alpha: 1)
}
func text(_ s: String, _ f: CTFont, _ x: Double, _ y: Double, _ c: CGColor) {
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
    kCTFontAttributeName as NSAttributedString.Key: f, kCTForegroundColorAttributeName as NSAttributedString.Key: c]))
  ctx.textPosition = CGPoint(x: x, y: y)
  CTLineDraw(line, ctx)
}
for (k, ch) in chars.enumerated() {
  let ox = Double(k % cols) * cell + 25, oy = Double(rows - 1 - k / cols) * cell + 40
  ctx.setStrokeColor(CGColor(gray: 0.9, alpha: 1)); ctx.setLineWidth(1)
  ctx.stroke(CGRect(x: ox, y: oy - 0.12 * em, width: em, height: em))
  guard let g = glyphs[ch] as? [String: Any] else { text("\(ch) ?", label, ox, oy, CGColor(gray: 0, alpha: 1)); continue }
  let strokes = g["strokes"] as! [[String: Any]]
  text("\(ch) \(strokes.count)", small, ox - 18, oy - 32, CGColor(gray: 0.3, alpha: 1))
  for (i, s) in strokes.enumerated() {
    let v = (s["p"] as! [NSNumber]).map { $0.doubleValue }
    var pts: [CGPoint] = []
    var j = 0
    while j + 2 < v.count { pts.append(CGPoint(x: ox + v[j] * em, y: oy + v[j + 1] * em)); j += 3 }
    guard pts.count >= 2 else { continue }
    let c = colour(i, strokes.count)
    ctx.setStrokeColor(c); ctx.setLineWidth(4); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addLines(between: pts); ctx.strokePath()
    // Arrow at the end.
    let a = pts[pts.count - 1], b = pts[max(0, pts.count - 2)]
    let ang = atan2(a.y - b.y, a.x - b.x)
    ctx.setFillColor(c)
    ctx.move(to: a)
    ctx.addLine(to: CGPoint(x: a.x - 9 * cos(ang - 0.45), y: a.y - 9 * sin(ang - 0.45)))
    ctx.addLine(to: CGPoint(x: a.x - 9 * cos(ang + 0.45), y: a.y - 9 * sin(ang + 0.45)))
    ctx.closePath(); ctx.fillPath()
    // Its number where it starts.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.fillEllipse(in: CGRect(x: pts[0].x - 8, y: pts[0].y - 8, width: 16, height: 16))
    ctx.setStrokeColor(c); ctx.setLineWidth(1.5)
    ctx.strokeEllipse(in: CGRect(x: pts[0].x - 8, y: pts[0].y - 8, width: 16, height: 16))
    text("\(i + 1)", label, pts[0].x - (i >= 9 ? 7 : 4), pts[0].y - 4.5, c)
  }
}
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dst)
