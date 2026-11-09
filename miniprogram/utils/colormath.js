// HSL 颜色数学 + 中文色名
// h: 0~360, s/l: 0~1

function rgb2hsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (mx + mn) / 2;
  if (mx !== mn) {
    const d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (mx === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
  }
  return { h, s, l };
}

function rgb2hsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
  const d = mx - mn;
  let h = 0;
  if (d !== 0) {
    if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (mx === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
  }
  return { h, s: mx === 0 ? 0 : d / mx, v: mx };
}

function hsl2rgb(hIn, s, l) {
  const h = (((hIn % 360) + 360) % 360);
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = l - c / 2;
  let r, g, b;
  if (h < 60) { r = c; g = x; b = 0; }
  else if (h < 120) { r = x; g = c; b = 0; }
  else if (h < 180) { r = 0; g = c; b = x; }
  else if (h < 240) { r = 0; g = x; b = c; }
  else if (h < 300) { r = x; g = 0; b = c; }
  else { r = c; g = 0; b = x; }
  return [
    Math.round((r + m) * 255),
    Math.round((g + m) * 255),
    Math.round((b + m) * 255),
  ];
}

function hslStr(c) {
  return `hsl(${Math.round(c.h)},${Math.round(c.s * 100)},${Math.round(c.l * 100)}%)`;
}

function hexStr(c) {
  const [r, g, b] = hsl2rgb(c.h, c.s, c.l);
  const p = (v) => v.toString(16).toUpperCase().padStart(2, "0");
  return `#${p(r)}${p(g)}${p(b)}`;
}

function isLight(l) { return l > 0.55; }

// 色名判定：与网页端 colorName 逻辑逐行对齐（含近黑兜底、蓝族 9 档、酒红、米白）
function colorName(h, s, l) {
  if (s < 0.12 || (s < 0.15 && l >= 0.70) || (s < 0.22 && l >= 0.82) || l >= 0.90) {
    if (l < 0.18) return "黑色";
    if (l < 0.42) return "深灰";
    if (l < 0.66) return "灰色";
    if (l < 0.88) return "浅灰";
    return (h >= 20 && h <= 70) ? "米白" : "白色";
  }
  // 近黑兜底：黑布拍照常带蓝偏，不兜底会被算成藏青
  if (l < 0.16 && s < 0.45) return "黑色";
  if (h >= 38 && h < 62 && s < 0.5 && l >= 0.8) return "浅黄";
  // 蓝族细拆：黑衣蓝衣不再挤「藏青」一档
  if (h >= 195 && h < 255 && s >= 0.12) {
    if (l < 0.21) return s < 0.38 ? "黑色" : "墨蓝";
    if (l < 0.32) return s >= 0.52 ? "深蓝" : "藏青";
    if (l < 0.62) {
      if (s < 0.26) return "灰蓝";
      if (h >= 250) return "蓝紫";
      if (l < 0.45 && s >= 0.52) return "深蓝";
      return s < 0.62 ? "牛仔蓝" : "宝蓝";
    }
    if (l < 0.80) return s < 0.55 ? "雾霾蓝" : "天蓝";
    return "浅蓝";
  }
  // 暗红按明度归酒红
  if (h < 12 && s < 0.6 && l < 0.40) return "酒红";
  if (h >= 12 && h < 38 && s >= 0.30 && l < 0.35) return "深咖";
  if (h >= 30 && h < 58 && s >= 0.20 && s < 0.50 && l >= 0.45 && l < 0.75) {
    return l >= 0.62 ? "卡其" : "驼色";
  }
  const hueNames = [
    [12,  [[0.35, "酒红"], [0.55, "砖红"], [9, "正红"]], "红"],
    [38,  [[0.3, "深咖"], [0.45, "驼色"], [0.6, "卡其"]], "棕"],
    [62,  [[0.7, "姜黄"], [1, "黄色"]], "黄"],
    [95,  [[0.35, "橄榄绿"], [0.55, "草绿"], [1, "绿色"]], "绿"],
    [150, [[0.3, "墨绿"], [0.55, "湖绿"], [1, "青绿"]], "绿"],
    [195, [[0.3, "墨绿"], [0.55, "湖绿"], [1, "青绿"]], "青"],
    [250, [[0.3, "藏青"], [0.55, "宝蓝"], [1, "蓝色"]], "蓝"],
    [285, [[0.35, "香芋紫"], [0.6, "紫色"]], "紫"],
    [315, [[0.35, "紫红"], [0.6, "玫红"]], "紫红"],
    [346, [[0.5, "粉色"], [1, "玫粉"]], "粉"],
  ];
  for (const [maxH, stops, fallback] of hueNames) {
    if (h < maxH) {
      for (const [maxS, name] of stops) {
        if (s < maxS) return name;
      }
      return fallback;
    }
  }
  return "玫粉";
}

// 肤色判定：HSV 色相 5~40 + 饱和度上限挡住正红/砖红/卡其衣料
function isSkin(h, s, v) {
  return h >= 5 && h <= 40 && s >= 0.10 && s <= 0.68 && v >= 0.35;
}

function colorDist(a, b) {
  const dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
  return Math.sqrt(dr * dr + dg * dg + db * db);
}

module.exports = { rgb2hsl, rgb2hsv, hsl2rgb, hslStr, hexStr, isLight, colorName, isSkin, colorDist };
