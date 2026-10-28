// shaped_glyphs.swift: glyphs as a script's shaping gives them (Arabic's
// joined forms), rasterised for their strokes to be traced (strokes.py):
// the same raster/ and meta.json as glyphs.swift writes, each glyph kept
// under the code point the list gives it.
//   swift shaped_glyphs.swift <font.ttf> <list.tsv> <out dir>
// Each line of the list: a code point, a tab, the text to shape; the glyphs
// for its characters other than zero-width joiners are drawn together.
import CoreGraphics
import CoreText
import Foundation

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[3])
let S: CGFloat = 360  // px per em
let pad: CGFloat = 24
let desc = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor])[0]
let font = CTFontCreateWithFontDescriptor(desc, S, nil)
try? FileManager.default.createDirectory(at: out.appendingPathComponent("raster"), withIntermediateDirectories: true)
var meta: [[String: Any]] = []
for row in try! String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n") {
  let parts = row.split(separator: "\t", maxSplits: 1)
  guard parts.count == 2, let code = Int(parts[0]) else { continue }
  let text = String(parts[1])
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font]))
  let ns = text as NSString
  let path = CGMutablePath()
  var adv: CGFloat = 0
  for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
    var idx = [CFIndex](repeating: 0, count: n), advs = [CGSize](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
    CTRunGetStringIndices(run, CFRange(location: 0, length: n), &idx)
    CTRunGetAdvances(run, CFRange(location: 0, length: n), &advs)
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
    for k in 0..<n where ns.character(at: idx[k]) != 0x200D {
      var t = CGAffineTransform(translationX: pos[k].x, y: pos[k].y)
      if let g = CTFontCreatePathForGlyph(runFont, glyphs[k], &t) { path.addPath(g) }
      adv += advs[k].width
    }
  }
  guard !path.isEmpty else { continue }
  let bb = path.boundingBoxOfPath
  let w = Int(ceil(bb.width + 2 * pad)), h = Int(ceil(bb.height + 2 * pad))
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  ctx.setFillColor(gray: 0, alpha: 1)
  ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  ctx.translateBy(x: pad - bb.minX, y: pad - bb.minY)
  ctx.addPath(path)
  ctx.setFillColor(gray: 1, alpha: 1)
  ctx.fillPath()
  try! Data(bytes: ctx.data!, count: w * h).write(to: out.appendingPathComponent("raster/\(code).gray"))
  meta.append(["code": code, "char": String(UnicodeScalar(code)!), "w": w, "h": h, "ox": Double(pad - bb.minX),
               "oy": Double(CGFloat(h) - (pad - bb.minY)), "adv": Double(adv / S)])
}
let space = { () -> Double in
  var u: [UniChar] = [32], g: [CGGlyph] = [0], a = CGSize.zero
  CTFontGetGlyphsForCharacters(font, &u, &g, 1)
  CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &a, 1)
  return Double(a.width / S)
}()
let info: [String: Any] = ["S": Double(S), "ascent": Double(CTFontGetAscent(font) / S), "descent": Double(CTFontGetDescent(font) / S),
                           "xHeight": Double(CTFontGetXHeight(font) / S), "capHeight": Double(CTFontGetCapHeight(font) / S),
                           "space": space, "glyphs": meta]
try! JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]).write(to: out.appendingPathComponent("meta.json"))
print("glyphs: \(meta.count), space \(space), xHeight \(CTFontGetXHeight(font) / S)")
