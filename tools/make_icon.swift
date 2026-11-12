// 生成 1024×1024 应用图标：蓝色圆角方块 + 白色四角星
// 用法：swiftc -O tools/make_icon.swift -o tools/make-icon && ./tools/make-icon design/icon-1024.png
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/icon-1024.png"
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("无法创建绘图上下文\n".data(using: .utf8)!)
    exit(1)
}

ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

let inset: CGFloat = 64
let rect = CGRect(x: inset, y: inset,
                  width: CGFloat(size) - inset * 2,
                  height: CGFloat(size) - inset * 2)
let radius: CGFloat = 198
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// 投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 46,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
ctx.addPath(squircle)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// 主体渐变
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let base = [CGColor(red: 0.28, green: 0.64, blue: 1.00, alpha: 1),
            CGColor(red: 0.00, green: 0.33, blue: 0.84, alpha: 1)] as CFArray
if let g = CGGradient(colorsSpace: cs, colors: base, locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(size)),
                           end: CGPoint(x: 0, y: 0), options: [])
}

// 顶部高光
let hl = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.24),
          CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
if let g = CGGradient(colorsSpace: cs, colors: hl, locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(size)),
                           end: CGPoint(x: 0, y: CGFloat(size) * 0.52), options: [])
}
ctx.restoreGState()

// 四角星
let c = CGPoint(x: 512, y: 512)
let R: CGFloat = 252
let k = R * 0.28
let star = [
    CGPoint(x: c.x, y: c.y + R),
    CGPoint(x: c.x + k, y: c.y + k),
    CGPoint(x: c.x + R, y: c.y),
    CGPoint(x: c.x + k, y: c.y - k),
    CGPoint(x: c.x, y: c.y - R),
    CGPoint(x: c.x - k, y: c.y - k),
    CGPoint(x: c.x - R, y: c.y),
    CGPoint(x: c.x - k, y: c.y + k)
]
ctx.addLines(between: star)
ctx.closePath()
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillPath()

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("已生成 \(outPath)")
