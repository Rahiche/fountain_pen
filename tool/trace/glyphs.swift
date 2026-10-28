// glyphs.swift: a font's Basic Latin glyphs, rasterised for their
// strokes to be traced (strokes.py): a white glyph on black, S px to
// the em, its origin's pixel and its advance in meta.json.
//   swift glyphs.swift <font.ttf> <out dir>
import CoreGraphics
import CoreText
import Foundation

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let S: CGFloat = 360   // px per em
let pad: CGFloat = 24
let desc = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as! [CTFontDescriptor])[0]
let font = CTFontCreateWithFontDescriptor(desc, S, nil)
var meta: [[String: Any]] = []
let chars = (33...126).map { Character(UnicodeScalar($0)!) }
for ch in chars {
  var u = Array(String(ch).utf16), g = [CGGlyph](repeating: 0, count: u.count)
  guard CTFontGetGlyphsForCharacters(font, &u, &g, u.count), g[0] != 0 else { continue }
  var adv = CGSize.zero
  CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
  guard let path = CTFontCreatePathForGlyph(font, g[0], nil) else { continue }
  let bb = path.boundingBoxOfPath
  let w = Int(ceil(bb.width + 2 * pad)), h = Int(ceil(bb.height + 2 * pad))
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
  // (The glyph's box at pad from the bottom left; y up in the context.)
  ctx.translateBy(x: pad - bb.minX, y: pad - bb.minY)
  ctx.addPath(path); ctx.setFillColor(gray: 1, alpha: 1); ctx.fillPath()
  let data = Data(bytes: ctx.data!, count: w * h)
  let code = Int(ch.unicodeScalars.first!.value)
  try! data.write(to: out.appendingPathComponent("raster/\(code).gray"))
  // The origin in image pixels (rows from the top: the buffer's first row is
  // the context's top, its y highest).
  meta.append(["code": code, "char": String(ch), "w": w, "h": h, "ox": Double(pad - bb.minX), "oy": Double(CGFloat(h) - (pad - bb.minY)), "adv": Double(adv.width / S)])
}
let space = { () -> Double in var u: [UniChar] = [32], g: [CGGlyph] = [0]; CTFontGetGlyphsForCharacters(font, &u, &g, 1); var a = CGSize.zero; CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &a, 1); return Double(a.width / S) }()
let info: [String: Any] = ["S": Double(S), "ascent": Double(CTFontGetAscent(font) / S), "descent": Double(CTFontGetDescent(font) / S), "xHeight": Double(CTFontGetXHeight(font) / S), "capHeight": Double(CTFontGetCapHeight(font) / S), "space": space, "glyphs": meta]
try! JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]).write(to: out.appendingPathComponent("meta.json"))
print("glyphs: \(meta.count), space \(space), xHeight \(CTFontGetXHeight(font) / S)")
