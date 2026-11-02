import UIKit
import CoreGraphics

/// 下采样后的 RGBA 像素缓冲，行序自顶向下（与网页 canvas.getImageData 一致）
struct PixelData {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }
}

struct RegionResult {
    var rgb: (Int, Int, Int)
    var coverage: Double
    var hsl: HSL { rgb2hsl(Double(rgb.0), Double(rgb.1), Double(rgb.2)) }
}

struct AnalysisResult {
    var top: RegionResult
    var bottom: RegionResult
    var bgAvg: (Int, Int, Int)
}

enum Analyzer {
    /// 归一化：方向转正 + 强制 scale 1（相机照片可能带屏幕 scale），size 即像素尺寸
    static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up || image.scale != 1 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * image.scale,
                          height: image.size.height * image.scale)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// 下采样到最长边 maxEdge，返回自顶向下的 RGBA 缓冲
    static func pixelData(_ image: UIImage, maxEdge: Int) -> PixelData {
        let cg = normalized(image).cgImage!
        let scale = min(1.0, Double(maxEdge) / Double(max(cg.width, cg.height)))
        let w = max(1, Int((Double(cg.width) * scale).rounded()))
        let hgt = max(1, Int((Double(cg.height) * scale).rounded()))
        var raw = [UInt8](repeating: 0, count: w * hgt * 4)
        raw.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: hgt,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: hgt))
        }
        // CGContext 内存行序自底向上，翻成自顶向下
        var bytes = [UInt8](repeating: 0, count: raw.count)
        for y in 0..<hgt {
            let src = (hgt - 1 - y) * w * 4
            let dst = y * w * 4
            for i in 0..<(w * 4) { bytes[dst + i] = raw[src + i] }
        }
        return PixelData(width: w, height: hgt, bytes: bytes)
    }

    /// 网页 analyzeImage 1:1 移植：边缘框定背景色 → 上下半身分簇取主色
    static func analyzeImage(_ image: UIImage, boundary: Double) -> AnalysisResult {
        let pd = pixelData(image, maxEdge: 260)
        let w = pd.width, hgt = pd.height

        /* 背景色：边缘 4px 框的主色（最大簇均值） */
        var border: [(Int, Int, Int)] = []
        let ys = [0, 1, 2, 3, hgt - 4, hgt - 3, hgt - 2, hgt - 1].filter { $0 >= 0 && $0 < hgt }
        let xs = [0, 1, 2, 3, w - 4, w - 3, w - 2, w - 1].filter { $0 >= 0 && $0 < w }
        for x in 0..<w { for y in ys { border.append(pd.px(x, y)) } }
        for y in 0..<hgt { for x in xs { border.append(pd.px(x, y)) } }
        var bgBins: [String: [(Int, Int, Int)]] = [:]
        var bgOrder: [String] = []
        for p in border {
            let key = "\(p.0 >> 5)_\(p.1 >> 5)_\(p.2 >> 5)"
            if bgBins[key] == nil { bgBins[key] = []; bgOrder.append(key) }
            bgBins[key]!.append(p)
        }
        var bgKey = "", bgBest = -1
        for k in bgOrder where bgBins[k]!.count > bgBest { bgBest = bgBins[k]!.count; bgKey = k }
        let bgList = bgBins[bgKey] ?? []
        func avgOf(_ arr: [(Int, Int, Int)]) -> (Int, Int, Int) {
            guard !arr.isEmpty else { return (128, 128, 128) }
            let s0 = arr.reduce(0) { $0 + $1.0 }, s1 = arr.reduce(0) { $0 + $1.1 }, s2 = arr.reduce(0) { $0 + $1.2 }
            return (Int((Double(s0) / Double(arr.count)).rounded()),
                    Int((Double(s1) / Double(arr.count)).rounded()),
                    Int((Double(s2) / Double(arr.count)).rounded()))
        }
        let bgAvg = avgOf(bgList)

        func regionColor(_ y0: Double, _ y1: Double, _ bgThresh: Double) -> RegionResult {
            var bins: [String: [(Int, Int, Int)]] = [:]
            var order: [String] = []
            var total = 0
            let yStart = Int(Double(hgt) * y0), yEnd = Int(Double(hgt) * y1)
            let xStart = Int(Double(w) * 0.24), xEnd = Int(Double(w) * 0.76)
            if yStart < yEnd && xStart < xEnd {
                for y in yStart..<yEnd {
                    for x in xStart..<xEnd {
                        let p = pd.px(x, y)
                        let hsv = rgb2hsv(Double(p.0), Double(p.1), Double(p.2))
                        total += 1
                        if colorDist(p, bgAvg) < bgThresh { continue }
                        if isSkin(hsv.h, hsv.s, hsv.v) { continue }
                        let key = "\(Int(hsv.h / 20))_\(Int(hsv.s * 4))_\(Int(hsv.v * 4))"
                        if bins[key] == nil { bins[key] = []; order.append(key) }
                        bins[key]!.append(p)
                    }
                }
            }
            var bestKey: String?, bestCount = 0
            for k in order where bins[k]!.count > bestCount { bestCount = bins[k]!.count; bestKey = k }
            guard let bk = bestKey else { return RegionResult(rgb: (128, 128, 128), coverage: 0) }
            return RegionResult(rgb: avgOf(bins[bk]!), coverage: Double(bestCount) / Double(max(1, total)))
        }

        let topY1 = max(0.3, boundary - 0.04)
        let botY0 = min(0.9, boundary + 0.04)
        var top = regionColor(0.22, topY1, 46)
        var bottom = regionColor(botY0, 0.88, 46)
        /* 浅色衣料可能贴着浅背景（RGB 距离小于背景阈值），首轮全被当背景时放宽重试 */
        if top.coverage < 0.05 { top = regionColor(0.22, topY1, 18) }
        if bottom.coverage < 0.05 { bottom = regionColor(botY0, 0.88, 18) }
        return AnalysisResult(top: top, bottom: bottom, bgAvg: bgAvg)
    }

    /// 照片上取色：7x7 小块平均，容忍压缩噪点。fx/fy 为图片比例坐标 0~1
    static func pickColor(_ sample: PixelData, fx: Double, fy: Double) -> (HSL, CGPoint)? {
        guard fx >= 0, fx <= 1, fy >= 0, fy <= 1 else { return nil }
        let r = 3
        let x = Int((fx * Double(sample.width)).rounded())
        let y = Int((fy * Double(sample.height)).rounded())
        let x0 = max(0, x - r), y0 = max(0, y - r)
        let x1 = min(sample.width - 1, x + r), y1 = min(sample.height - 1, y + r)
        var s0 = 0, s1 = 0, s2 = 0, n = 0
        for yy in y0...y1 {
            for xx in x0...x1 {
                let i = (yy * sample.width + xx) * 4
                s0 += Int(sample.bytes[i]); s1 += Int(sample.bytes[i + 1]); s2 += Int(sample.bytes[i + 2])
                n += 1
            }
        }
        guard n > 0 else { return nil }
        let hsl = rgb2hsl(Double(s0) / Double(n), Double(s1) / Double(n), Double(s2) / Double(n))
        return (hsl, CGPoint(x: fx, y: fy))
    }

    static func cropImage(_ image: UIImage, rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: max(1, rect.width), height: max(1, rect.height))
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.origin.x, y: -rect.origin.y))
        }
    }

    static func resized(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 裁剪视口 → 源图坐标（与网页 btnCropDone 一致），输出最长边 1600
    static func cropOutput(source: UIImage, viewW: Double, viewH: Double,
                           scale: Double, ox: Double, oy: Double) -> UIImage {
        let srcW = source.size.width, srcH = source.size.height
        let vx0 = max(0, ox), vy0 = max(0, oy)
        let vx1 = min(viewW, ox + srcW * scale), vy1 = min(viewH, oy + srcH * scale)
        let sx = (vx0 - ox) / scale, sy = (vy0 - oy) / scale
        let sw = (vx1 - vx0) / scale, sh = (vy1 - vy0) / scale
        let outScale = min(1.0, 1600.0 / max(sw, sh))
        let outW = max(1, Int((sw * outScale).rounded()))
        let outH = max(1, Int((sh * outScale).rounded()))
        let cropped = cropImage(source, rect: CGRect(x: sx, y: sy, width: sw, height: sh))
        return resized(cropped, to: CGSize(width: outW, height: outH))
    }

    /// 上传前压缩：最长边 1280、质量 0.72，返回 dataURL（Worker 只认这个格式）
    static func compressToDataUrl(_ image: UIImage) -> String {
        let cg = normalized(image).cgImage!
        let scale = min(1.0, 1280.0 / Double(max(cg.width, cg.height)))
        let w = max(1, Int((Double(cg.width) * scale).rounded()))
        let hgt = max(1, Int((Double(cg.height) * scale).rounded()))
        let small = resized(normalized(image), to: CGSize(width: w, height: hgt))
        let jpeg = small.jpegData(compressionQuality: 0.72) ?? Data()
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
