import Foundation

/// HSL 颜色（h: 0~360, s/l: 0~1）
struct HSL: Equatable {
    var h: Double
    var s: Double
    var l: Double

    var hslStr: String {
        "hsl(\(Int(h)),\(Int((s * 100).rounded())),\(Int((l * 100).rounded()))%)"
    }
    var hex: String {
        let (r, g, b) = hsl2rgb(h, s, l)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    var uiColorText: String { hslStr }
}

func rgb2hsl(_ r: Double, _ g: Double, _ b: Double) -> HSL {
    let r = r / 255, g = g / 255, b = b / 255
    let mx = max(r, g, b), mn = min(r, g, b)
    var h = 0.0, s = 0.0
    let l = (mx + mn) / 2
    if mx != mn {
        let d = mx - mn
        s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
    }
    return HSL(h: h, s: s, l: l)
}

func rgb2hsv(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
    let r = r / 255, g = g / 255, b = b / 255
    let mx = max(r, g, b), mn = min(r, g, b)
    let d = mx - mn
    var h = 0.0
    if d != 0 {
        switch mx {
        case r: h = (g - b) / d + (g < b ? 6 : 0)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
    }
    return (h, mx == 0 ? 0 : d / mx, mx)
}

func hsl2rgb(_ hIn: Double, _ s: Double, _ l: Double) -> (Int, Int, Int) {
    let h = ((hIn.truncatingRemainder(dividingBy: 360)) + 360)
        .truncatingRemainder(dividingBy: 360)
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    let rgb: (Double, Double, Double)
    if h < 60 { rgb = (c, x, 0) }
    else if h < 120 { rgb = (x, c, 0) }
    else if h < 180 { rgb = (0, c, x) }
    else if h < 240 { rgb = (0, x, c) }
    else if h < 300 { rgb = (x, 0, c) }
    else { rgb = (c, 0, x) }
    return (Int(((rgb.0 + m) * 255).rounded()),
            Int(((rgb.1 + m) * 255).rounded()),
            Int(((rgb.2 + m) * 255).rounded()))
}

/// 色名判定：与网页端 colorName 逻辑逐行对齐（含近黑兜底、蓝族 9 档、酒红、米白）
func colorName(_ h: Double, _ s: Double, _ l: Double) -> String {
    if s < 0.12 || (s < 0.15 && l >= 0.70) || (s < 0.22 && l >= 0.82) || l >= 0.90 {
        if l < 0.18 { return "黑色" }
        if l < 0.42 { return "深灰" }
        if l < 0.66 { return "灰色" }
        if l < 0.88 { return "浅灰" }
        return (h >= 20 && h <= 70) ? "米白" : "白色"
    }
    /* 近黑兜底：黑布拍照常带蓝偏，不兜底会被算成藏青 */
    if l < 0.16 && s < 0.45 { return "黑色" }
    if h >= 38 && h < 62 && s < 0.5 && l >= 0.8 { return "浅黄" }
    /* 蓝族细拆：黑衣蓝衣不再挤「藏青」一档 */
    if h >= 195 && h < 255 && s >= 0.12 {
        if l < 0.21 { return s < 0.38 ? "黑色" : "墨蓝" }
        if l < 0.32 { return s >= 0.52 ? "深蓝" : "藏青" }
        if l < 0.62 {
            if s < 0.26 { return "灰蓝" }
            if h >= 250 { return "蓝紫" }
            if l < 0.45 && s >= 0.52 { return "深蓝" }
            return s < 0.62 ? "牛仔蓝" : "宝蓝"
        }
        if l < 0.80 { return s < 0.55 ? "雾霾蓝" : "天蓝" }
        return "浅蓝"
    }
    /* 暗红按明度归酒红 */
    if h < 12 && s < 0.6 && l < 0.40 { return "酒红" }
    if h >= 12 && h < 38 && s >= 0.30 && l < 0.35 { return "深咖" }
    if h >= 30 && h < 58 && s >= 0.20 && s < 0.50 && l >= 0.45 && l < 0.75 {
        return l >= 0.62 ? "卡其" : "驼色"
    }
    let hueNames: [(maxH: Double, stops: [(maxS: Double, name: String)], fallback: String)] = [
        (12,  [(0.35, "酒红"), (0.55, "砖红"), (9, "正红")], "红"),
        (38,  [(0.3, "深咖"), (0.45, "驼色"), (0.6, "卡其")], "棕"),
        (62,  [(0.7, "姜黄"), (1, "黄色")], "黄"),
        (95,  [(0.35, "橄榄绿"), (0.55, "草绿"), (1, "绿色")], "绿"),
        (150, [(0.3, "墨绿"), (0.55, "湖绿"), (1, "青绿")], "绿"),
        (195, [(0.3, "墨绿"), (0.55, "湖绿"), (1, "青绿")], "青"),
        (250, [(0.3, "藏青"), (0.55, "宝蓝"), (1, "蓝色")], "蓝"),
        (285, [(0.35, "香芋紫"), (0.6, "紫色")], "紫"),
        (315, [(0.35, "紫红"), (0.6, "玫红")], "紫红"),
        (346, [(0.5, "粉色"), (1, "玫粉")], "粉"),
    ]
    for (maxH, stops, fallback) in hueNames where h < maxH {
        for (maxS, name) in stops where s < maxS { return name }
        return fallback
    }
    return "玫粉"
}

func colorName(_ color: HSL) -> String { colorName(color.h, color.s, color.l) }

/// 肤色判定：HSV 色相 5~40 + 饱和度上限挡住正红/砖红/卡其衣料
func isSkin(_ h: Double, _ s: Double, _ v: Double) -> Bool {
    (h >= 5 && h <= 40) && s >= 0.10 && s <= 0.68 && v >= 0.35
}

func colorDist(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Double {
    let dr = Double(a.0 - b.0), dg = Double(a.1 - b.1), db = Double(a.2 - b.2)
    return (dr * dr + dg * dg + db * db).squareRoot()
}
