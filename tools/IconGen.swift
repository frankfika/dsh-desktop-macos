// 图标生成器：绘制 1024x1024 PNG（深色渐变圆角 + 播放三角 + 提示符下划线）
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

@main
struct IconGen {
    static func main() {
        let w = 1024, h = 1024
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("no colorspace") }
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { fatalError("no context") }

        // 背景渐变
        let colors = [
            CGColor(srgbRed: 0.06, green: 0.08, blue: 0.19, alpha: 1),
            CGColor(srgbRed: 0.33, green: 0.17, blue: 0.68, alpha: 1),
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 1.0]) else { fatalError("no grad") }
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                           cornerWidth: 225, cornerHeight: 225, transform: nil))
        ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

        // 光晕圆
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.fillEllipse(in: CGRect(x: 262, y: 212, width: 500, height: 500))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18))
        ctx.fillEllipse(in: CGRect(x: 302, y: 252, width: 420, height: 420))

        // 播放三角（▶）
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: 396, y: 672))
        tri.addLine(to: CGPoint(x: 396, y: 332))
        tri.addLine(to: CGPoint(x: 716, y: 502))
        tri.closeSubpath()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(tri)
        ctx.fillPath()

        // 提示符下划线（_）
        ctx.addPath(CGPath(roundedRect: CGRect(x: 342, y: 232, width: 340, height: 52),
                           cornerWidth: 26, cornerHeight: 26, transform: nil))
        ctx.fillPath()

        guard let img = ctx.makeImage() else { fatalError("no image") }
        let outURL = URL(fileURLWithPath: ".build/icon-1024.png")
        try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL,
                                                         UTType.png.identifier as CFString, 1, nil)
        else { fatalError("no dest") }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("finalize failed") }
        print("icon written: \(outURL.path)")
    }
}
