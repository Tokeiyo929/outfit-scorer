// 打分页：天气卡 → 拍照/选图 → 裁剪 → 拖分界线 → 点照取色 → 保存
const img = require("../../utils/img");
const analyzer = require("../../utils/analyzer");
const cm = require("../../utils/colormath");
const api = require("../../utils/api");
const weather = require("../../utils/weather");

const MAX_CROP_EDGE = 1600;   // 裁剪输出最长边
const SAMPLE_EDGE = 260;      // 识别采样最长边

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

Page({
  data: {
    stage: "pick", // pick | crop | preview | result

    // 天气
    weather: null,
    weatherBusy: false,
    weatherError: "",
    manualCity: "",

    // 照片
    croppedPath: "",
    photoBoxH: 0,
    boundary: 0.52,

    // 结果
    pickMode: "top",
    topInfo: null,    // {hsl:{h,s,l}, hex, name, pos:{x,y}|null}
    bottomInfo: null,
    topBad: false,
    bottomBad: false,
    topLike: false,
    bottomLike: false,
    score: 70,
    comment: "",
    saveBusy: false,
    saveState: "",
  },

  // 非渲染状态
  work: null,          // 隐藏工作画布
  crop: null,          // 裁剪画布 { canvas, ctx, w, h }
  cropImg: null,       // 裁剪画布上的 Image
  srcW: 0, srcH: 0,    // 源图像素尺寸
  scale: 1, ox: 0, oy: 0,
  contain: 1, cover: 1,
  zoomSlider: 0,
  cropLastTouch: null,
  samplePd: null,      // 识别后的下采样像素缓冲
  photoRect: null,     // 照片显示区域（touchstart 时缓存）
  touchStart: null,    // 结果阶段区分 tap/滑动
  contentW: 0,

  onLoad() {
    const ww = wx.getSystemInfoSync().windowWidth;
    this.contentW = ww - 48; // wrap 24rpx + card 24rpx 内边距各两侧
    this.setData({
      cropBoxH: Math.round(this.contentW * 1.25),
    });
  },

  async onReady() {
    try {
      this.work = await img.bindPage("#workCanvas");
    } catch (e) {
      wx.showToast({ title: "画布初始化失败", icon: "none" });
    }
  },

  onShow() {
    // 灵感页「拿去打分」跳过来：先接住暂存图，直接进裁剪
    const app = getApp();
    const pending = app.globalData && app.globalData.pendingScorePhoto;
    if (pending) {
      app.globalData.pendingScorePhoto = "";
      this.startCrop(pending);
      return;
    }
    this.loadWeather();
  },

  // ---------------- 天气 ----------------
  async loadWeather(cityName) {
    if (this.data.weatherBusy) return;
    this.setData({ weatherBusy: true, weatherError: "" });
    const r = await weather.loadWeather(cityName);
    if (r.ok) {
      this.setData({ weatherBusy: false, weather: r.weather });
    } else {
      this.setData({ weatherBusy: false, weatherError: r.error });
    }
  },

  onManualCityInput(e) {
    this.setData({ manualCity: e.detail.value });
  },

  queryManualCity() {
    const name = (this.data.manualCity || "").trim();
    if (!name) return;
    this.loadWeather(name);
  },

  // ---------------- 选拍照/相册 ----------------
  chooseCamera() {
    this.pickImage(["camera"]);
  },

  chooseAlbum() {
    this.pickImage(["album"]);
  },

  pickImage(sourceType) {
    wx.chooseMedia({
      count: 1,
      mediaType: ["image"],
      sourceType,
      sizeType: ["original"],
      success: (res) => {
        const path = res.tempFiles && res.tempFiles[0] && res.tempFiles[0].tempFilePath;
        if (path) this.startCrop(path);
      },
    });
  },

  // ---------------- 裁剪 ----------------
  // 裁剪画布在 wx:if 里，先切 stage 挂载，再绑节点
  async bindCropCanvas() {
    this.setData({ stage: "crop" });
    const query = () => new Promise((resolve) =>
      wx.createSelectorQuery().select("#cropCanvas").fields({ node: true }).exec(
        (r) => resolve(r && r[0] && r[0].node)));
    let node = await query();
    for (let i = 0; i < 10 && !node; i++) {
      await new Promise((r) => setTimeout(r, 50));
      node = await query();
    }
    if (!node) throw new Error("裁剪画布未找到");
    const dpr = wx.getSystemInfoSync().pixelRatio || 2;
    const cssW = Math.round(this.contentW);
    const cssH = Math.round(this.data.cropBoxH);
    node.width = cssW * dpr;
    node.height = cssH * dpr;
    const ctx = node.getContext("2d");
    ctx.scale(dpr, dpr);
    this.crop = { canvas: node, ctx };
  },

  async startCrop(path) {
    try {
      if (!this.crop) await this.bindCropCanvas();
      const info = await new Promise((resolve, reject) =>
        wx.getImageInfo({ src: path, success: resolve, fail: reject }));
      const image = await this.crop.canvas.createImage();
      await new Promise((resolve, reject) => {
        image.onload = resolve;
        image.onerror = () => reject(new Error("图片加载失败"));
        image.src = path;
      });
      this.cropImg = image;
      this.sourcePath = path;
      this.srcW = info.width;
      this.srcH = info.height;
      const w = this.contentW, h = this.data.cropBoxH;
      this.contain = Math.min(w / info.width, h / info.height);
      this.cover = Math.max(w / info.width, h / info.height);
      this.scale = this.contain;
      this.ox = (w - info.width * this.contain) / 2;
      this.oy = (h - info.height * this.contain) / 2;
      this.setData({ stage: "crop", zoomSlider: 0 });
      this.drawCrop();
    } catch (e) {
      wx.showToast({ title: "照片加载失败", icon: "none" });
    }
  },

  drawCrop() {
    if (!this.crop || !this.cropImg) return;
    const { ctx } = this.crop;
    const w = this.contentW, h = this.data.cropBoxH;
    ctx.fillStyle = "#1c1b19";
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(this.cropImg, this.ox, this.oy, this.srcW * this.scale, this.srcH * this.scale);
  },

  clampPan() {
    const w = this.contentW, h = this.data.cropBoxH;
    const dw = this.srcW * this.scale, dh = this.srcH * this.scale;
    this.ox = dw <= w ? (w - dw) / 2 : clamp(this.ox, w - dw, 0);
    this.oy = dh <= h ? (h - dh) / 2 : clamp(this.oy, h - dh, 0);
  },

  cropTouchStart(e) {
    const t = e.touches[0];
    this.cropLastTouch = { x: t.clientX, y: t.clientY };
  },

  cropTouchMove(e) {
    if (!this.cropLastTouch) return;
    const t = e.touches[0];
    this.ox += t.clientX - this.cropLastTouch.x;
    this.oy += t.clientY - this.cropLastTouch.y;
    this.cropLastTouch = { x: t.clientX, y: t.clientY };
    this.clampPan();
    this.drawCrop();
  },

  cropTouchEnd() {
    this.cropLastTouch = null;
  },

  // 缩放围绕画布中心
  zoomChanging(e) {
    if (!this.crop || !this.cropImg) return;
    const v = e.detail.value;
    const w = this.contentW, h = this.data.cropBoxH;
    const old = this.scale;
    const minS = this.contain, maxS = this.cover * 4;
    const cx = (w / 2 - this.ox) / old;
    const cy = (h / 2 - this.oy) / old;
    this.scale = minS * Math.pow(maxS / minS, v / 100);
    this.ox = w / 2 - cx * this.scale;
    this.oy = h / 2 - cy * this.scale;
    this.clampPan();
    this.setData({ zoomSlider: v });
    this.drawCrop();
  },

  cancelPhoto() {
    this.crop = null;
    this.cropImg = null;
    this.sourcePath = null;
    this.samplePd = null;
    this.setData({
      stage: "pick",
      croppedPath: "",
      topInfo: null, bottomInfo: null,
      topBad: false, bottomBad: false,
      topLike: false, bottomLike: false,
      pickMode: "top", score: 70, comment: "",
      saveState: "", boundary: 0.52,
    });
  },

  // 裁剪完成 → 输出最长边 1600
  async onCropDone() {
    if (!this.cropImg || !this.work) return;
    const w = this.contentW, h = this.data.cropBoxH;
    const vx0 = Math.max(0, this.ox), vy0 = Math.max(0, this.oy);
    const vx1 = Math.min(w, this.ox + this.srcW * this.scale);
    const vy1 = Math.min(h, this.oy + this.srcH * this.scale);
    const sx = (vx0 - this.ox) / this.scale, sy = (vy0 - this.oy) / this.scale;
    const sw = (vx1 - vx0) / this.scale, sh = (vy1 - vy0) / this.scale;
    if (sw < 2 || sh < 2) {
      wx.showToast({ title: "裁剪区域太小", icon: "none" });
      return;
    }
    const outScale = Math.min(1, MAX_CROP_EDGE / Math.max(sw, sh));
    const outW = Math.max(1, Math.round(sw * outScale));
    const outH = Math.max(1, Math.round(sh * outScale));
    try {
      wx.showLoading({ title: "处理中" });
      // 直接从原图按源坐标重绘（不经裁剪画布，避免二次重采样）
      const srcImg = await this.work.loadImage(this.sourcePath);
      this.work.ensure(outW, outH);
      this.work.ctx.drawImage(srcImg, sx, sy, sw, sh, 0, 0, outW, outH);
      const croppedPath = await this.work.exportJpg(0.92);
      const info = await new Promise((resolve, reject) =>
        wx.getImageInfo({ src: croppedPath, success: resolve, fail: reject }));
      wx.hideLoading();
      this.setData({
        stage: "preview",
        croppedPath,
        photoBoxH: Math.round(this.contentW * info.height / info.width),
        boundary: 0.52,
        topInfo: null, bottomInfo: null,
        pickMode: "top", score: 70, comment: "",
        saveState: "", topBad: false, bottomBad: false,
        topLike: false, bottomLike: false,
      });
    } catch (e) {
      wx.hideLoading();
      wx.showToast({ title: "裁剪失败，重试一下", icon: "none" });
    }
  },

  // ---------------- 预览：拖分界线 ----------------
  noop() {},

  async boundaryTouchStart(e) {
    this.photoRect = await this.queryPhotoRect();
    this.applyBoundary(e.touches[0].clientY);
  },

  boundaryTouchMove(e) {
    this.applyBoundary(e.touches[0].clientY);
  },

  applyBoundary(clientY) {
    const r = this.photoRect;
    if (!r) return;
    const f = (clientY - r.top) / Math.max(1, r.height);
    this.setData({ boundary: clamp(f, 0.15, 0.85) });
  },

  queryPhotoRect() {
    return new Promise((resolve) => {
      wx.createSelectorQuery().select("#photoBox").boundingClientRect((rect) => {
        resolve(rect || null);
      }).exec();
    });
  },

  async reCrop() {
    if (!this.cropImg) { this.cancelPhoto(); return; }
    try {
      // 画布随 wx:if 卸载，重进裁剪需重新绑节点
      this.crop = null;
      await this.bindCropCanvas();
      this.drawCrop();
    } catch (e) {
      wx.showToast({ title: "画布初始化失败", icon: "none" });
    }
  },

  // ---------------- 识别 ----------------
  async analyze() {
    if (!this.work || !this.data.croppedPath) return;
    try {
      wx.showLoading({ title: "识别中" });
      const pd = await this.work.pixels(this.data.croppedPath, SAMPLE_EDGE);
      wx.hideLoading();
      const result = analyzer.analyzeImage(pd, this.data.boundary);
      this.samplePd = pd;
      this.setData({
        stage: "result",
        pickMode: "top",
        topInfo: this.infoOf(result.top),
        bottomInfo: result.bottom.coverage > 0 ? this.infoOf(result.bottom) : null,
      });
    } catch (e) {
      wx.hideLoading();
      wx.showToast({ title: "识别失败，重试一下", icon: "none" });
    }
  },

  infoOf(region) {
    const hsl = cm.rgb2hsl(region.rgb[0], region.rgb[1], region.rgb[2]);
    return { hsl, hex: cm.hexStr(hsl), name: cm.colorName(hsl.h, hsl.s, hsl.l), pos: null };
  },

  // ---------------- 结果：点照取色 ----------------
  async photoTouchStart(e) {
    this.photoRect = await this.queryPhotoRect();
    const t = e.touches[0];
    this.touchStart = { x: t.clientX, y: t.clientY, time: Date.now() };
  },

  photoTouchEnd(e) {
    if (!this.touchStart || !this.photoRect) return;
    const t = e.changedTouches[0];
    const moved = Math.abs(t.clientX - this.touchStart.x) + Math.abs(t.clientY - this.touchStart.y);
    const quick = Date.now() - this.touchStart.time < 600;
    this.touchStart = null;
    if (moved > 12 || !quick) return; // 滑动视页面，不算取色
    const r = this.photoRect;
    const fx = (t.clientX - r.left) / Math.max(1, r.width);
    const fy = (t.clientY - r.top) / Math.max(1, r.height);
    this.pickColorAt(fx, fy);
  },

  pickColorAt(fx, fy) {
    if (!this.samplePd) return;
    const hit = analyzer.pickColor(this.samplePd, fx, fy);
    if (!hit) return;
    const info = {
      hsl: hit.hsl, hex: cm.hexStr(hit.hsl), name: cm.colorName(hit.hsl.h, hit.hsl.s, hit.hsl.l),
      pos: hit.pos,
    };
    if (this.data.pickMode === "top") {
      this.setData({ topInfo: info, pickMode: "bottom" });
    } else {
      this.setData({ bottomInfo: info, pickMode: "top" });
    }
  },

  setPickMode(e) {
    this.setData({ pickMode: e.currentTarget.dataset.mode });
  },

  toggleTopBad() { this.setData({ topBad: !this.data.topBad, topLike: false }); },
  toggleBottomBad() { this.setData({ bottomBad: !this.data.bottomBad, bottomLike: false }); },
  // 雷点/喜欢互斥：标喜先清雷，标雷先清喜
  toggleTopLike() { this.setData({ topLike: !this.data.topLike, topBad: false }); },
  toggleBottomLike() { this.setData({ bottomLike: !this.data.bottomLike, bottomBad: false }); },

  onScoreChanging(e) {
    this.setData({ score: e.detail.value });
  },

  onCommentInput(e) {
    this.setData({ comment: e.detail.value });
  },

  // ---------------- 保存 ----------------
  canSave() {
    return !!this.data.topInfo && !this.data.saveBusy;
  },

  async save() {
    if (!this.canSave() || !this.work) return;
    this.setData({ saveBusy: true, saveState: "" });
    try {
      const photo = await this.work.compressToDataUrl(this.data.croppedPath);
      const t = this.data.topInfo, b = this.data.bottomInfo;
      const record = {
        top: { name: t.name, hex: t.hex, hsl: cm.hslStr(t.hsl) },
        bottom: b
          ? { name: b.name, hex: b.hex, hsl: cm.hslStr(b.hsl) }
          : { name: "", hex: "", hsl: "" },
        boundary: this.data.boundary,
        score: Math.round(this.data.score),
        comment: (this.data.comment || "").trim(),
        topBad: this.data.topBad,
        bottomBad: this.data.bottomBad,
        topLike: this.data.topLike,
        bottomLike: this.data.bottomLike,
      };
      await api.saveRecord(photo, record);
      this.setData({ saveBusy: false, saveState: "已保存" });
    } catch (e) {
      this.setData({ saveBusy: false, saveState: "保存失败：" + e.message });
    }
  },
});
