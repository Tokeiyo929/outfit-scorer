// 识别算法：analyzeImage/pickColor
// 输入是 utils/img.js 产出的像素缓冲 {width, height, data(RGBA, 自顶向下)}
const cm = require("./colormath");

function px(pd, x, y) {
  const i = (y * pd.width + x) * 4;
  return [pd.data[i], pd.data[i + 1], pd.data[i + 2]];
}

function avgOf(arr) {
  if (!arr.length) return [128, 128, 128];
  let s0 = 0, s1 = 0, s2 = 0;
  for (const p of arr) { s0 += p[0]; s1 += p[1]; s2 += p[2]; }
  const n = arr.length;
  return [Math.round(s0 / n), Math.round(s1 / n), Math.round(s2 / n)];
}

// 边缘框定背景色 → 上下半身分簇取主色（与网页端 analyzeImage 一致）
function analyzeImage(pd, boundary) {
  const w = pd.width, h = pd.height;

  /* 背景色：边缘 4px 框的主色（最大簇均值） */
  const ys = [0, 1, 2, 3, h - 4, h - 3, h - 2, h - 1].filter((v) => v >= 0 && v < h);
  const xs = [0, 1, 2, 3, w - 4, w - 3, w - 2, w - 1].filter((v) => v >= 0 && v < w);
  const bgBins = new Map();
  for (let x = 0; x < w; x++) for (const y of ys) addBin(bgBins, px(pd, x, y));
  for (let y = 0; y < h; y++) for (const x of xs) addBin(bgBins, px(pd, x, y));
  let bgKey = "", bgBest = -1;
  for (const [k, list] of bgBins) {
    if (list.length > bgBest) { bgBest = list.length; bgKey = k; }
  }
  const bgAvg = avgOf(bgBins.get(bgKey) || []);

  function regionColor(y0, y1, bgThresh) {
    const bins = new Map();
    let total = 0;
    const yStart = Math.trunc(h * y0), yEnd = Math.trunc(h * y1);
    const xStart = Math.trunc(w * 0.24), xEnd = Math.trunc(w * 0.76);
    if (yStart < yEnd && xStart < xEnd) {
      for (let y = yStart; y < yEnd; y++) {
        for (let x = xStart; x < xEnd; x++) {
          const p = px(pd, x, y);
          const hsv = cm.rgb2hsv(p[0], p[1], p[2]);
          total++;
          if (cm.colorDist(p, bgAvg) < bgThresh) continue;
          if (cm.isSkin(hsv.h, hsv.s, hsv.v)) continue;
          const key = `${Math.trunc(hsv.h / 20)}_${Math.trunc(hsv.s * 4)}_${Math.trunc(hsv.v * 4)}`;
          let list = bins.get(key);
          if (!list) { list = []; bins.set(key, list); }
          list.push(p);
        }
      }
    }
    let bestKey = "", bestCount = 0;
    for (const [k, list] of bins) {
      if (list.length > bestCount) { bestCount = list.length; bestKey = k; }
    }
    if (!bestKey) return { rgb: [128, 128, 128], coverage: 0 };
    return { rgb: avgOf(bins.get(bestKey)), coverage: bestCount / Math.max(1, total) };
  }

  // 分界线可拖 0.15~0.85，采样带保底 0.06 高（否则贴边时上下装采样区会消失）
  const topY1 = Math.max(0.28, boundary - 0.04);
  const botY0 = Math.min(0.82, boundary + 0.04);
  let top = regionColor(0.22, topY1, 46);
  let bottom = regionColor(botY0, 0.88, 46);
  /* 浅色衣料可能贴着浅背景（RGB 距离小于背景阈值），首轮全被当背景时放宽重试 */
  if (top.coverage < 0.05) top = regionColor(0.22, topY1, 18);
  if (bottom.coverage < 0.05) bottom = regionColor(botY0, 0.88, 18);
  return { top, bottom, bgAvg };
}

function addBin(bins, p) {
  const key = `${p[0] >> 5}_${p[1] >> 5}_${p[2] >> 5}`;
  let list = bins.get(key);
  if (!list) { list = []; bins.set(key, list); }
  list.push(p);
}

// 照片上取色：7x7 小块平均，容忍压缩噪点。fx/fy 为图片比例坐标 0~1
function pickColor(pd, fx, fy) {
  if (!(fx >= 0 && fx <= 1 && fy >= 0 && fy <= 1)) return null;
  const r = 3;
  const x = Math.round(fx * pd.width);
  const y = Math.round(fy * pd.height);
  const x0 = Math.max(0, x - r), y0 = Math.max(0, y - r);
  const x1 = Math.min(pd.width - 1, x + r), y1 = Math.min(pd.height - 1, y + r);
  let s0 = 0, s1 = 0, s2 = 0, n = 0;
  for (let yy = y0; yy <= y1; yy++) {
    for (let xx = x0; xx <= x1; xx++) {
      const i = (yy * pd.width + xx) * 4;
      s0 += pd.data[i]; s1 += pd.data[i + 1]; s2 += pd.data[i + 2];
      n++;
    }
  }
  if (n <= 0) return null;
  const hsl = cm.rgb2hsl(s0 / n, s1 / n, s2 / n);
  return { hsl, pos: { x: fx, y: fy } };
}

module.exports = { analyzeImage, pickColor };
