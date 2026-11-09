// 灵感收藏页：收藏喜欢的别人穿搭图，宫格浏览，长按可拿去打分或删除
const img = require("../../utils/img");
const api = require("../../utils/api");

Page({
  data: {
    list: [],
    busy: false,
    error: "",

    // 添加浮层
    addOpen: false,
    pendingPath: "",
    note: "",
    saveBusy: false,
  },

  work: null,

  noop() { /* 阻止浮层点击冒泡到遮罩 */ },

  async onReady() {
    try {
      this.work = await img.bindPage("#workCanvas");
    } catch (e) { /* 保存压缩时才会用到 */ }
  },

  onShow() {
    this.loadList(true);
  },

  onPullDownRefresh() {
    this.loadList(true).then(() => wx.stopPullDownRefresh());
  },

  async loadList(force) {
    if (this.data.busy) return;
    if (!force && this.data.list.length) return;
    this.setData({ busy: true, error: "" });
    try {
      const resp = await api.listInspirations(60);
      this.setData({
        busy: false,
        list: resp.inspirations.map((r) => ({ ...r, dateText: api.dateText(r.created_at) })),
      });
    } catch (e) {
      this.setData({ busy: false, error: "收藏加载失败，检查网络后重试" });
    }
  },

  // ---------------- 添加 ----------------
  addInspire() {
    wx.chooseMedia({
      count: 1,
      mediaType: ["image"],
      sourceType: ["album", "camera"],
      sizeType: ["original"],
      success: (res) => {
        const path = res.tempFiles && res.tempFiles[0] && res.tempFiles[0].tempFilePath;
        if (path) this.setData({ addOpen: true, pendingPath: path, note: "", error: "" });
      },
    });
  },

  onNoteInput(e) {
    this.setData({ note: e.detail.value });
  },

  cancelAdd() {
    this.setData({ addOpen: false, pendingPath: "", note: "" });
  },

  async saveInspire() {
    if (this.data.saveBusy || !this.data.pendingPath) return;
    this.setData({ saveBusy: true });
    try {
      if (!this.work) this.work = await img.bindPage("#workCanvas");
      const photo = await this.work.compressToDataUrl(this.data.pendingPath);
      await api.saveInspiration(photo, (this.data.note || "").trim());
      this.setData({ saveBusy: false });
      this.cancelAdd();
      this.loadList(true);
    } catch (e) {
      this.setData({ saveBusy: false, error: "保存失败：" + e.message });
    }
  },

  // ---------------- 长按操作 ----------------
  itemLongPress(e) {
    const id = e.currentTarget.dataset.id;
    const rec = this.data.list.find((r) => String(r.id) === String(id));
    if (!rec) return;
    wx.showActionSheet({
      itemList: ["拿去打分", "删除"],
      success: (res) => {
        if (res.tapIndex === 0) this.useForScore(rec);
        else if (res.tapIndex === 1) this.removeItem(rec);
      },
    });
  },

  // 下载原图 → 暂存全局 → 切到打分页自动进入裁剪
  useForScore(rec) {
    wx.showLoading({ title: "取图中" });
    wx.getImageInfo({
      src: rec.photo_url,
      success: (res) => {
        wx.hideLoading();
        const app = getApp();
        app.globalData.pendingScorePhoto = res.tempFilePath;
        wx.switchTab({ url: "/pages/index/index" });
      },
      fail: () => {
        wx.hideLoading();
        wx.showToast({ title: "取图失败，稍后再试", icon: "none" });
      },
    });
  },

  async removeItem(rec) {
    const confirm = await new Promise((resolve) =>
      wx.showModal({
        title: "删除这张收藏？",
        confirmText: "删除",
        confirmColor: "#d5442e",
        success: (r) => resolve(r.confirm),
        fail: () => resolve(false),
      }));
    if (!confirm) return;
    try {
      await api.deleteInspiration(rec.id);
      this.setData({ list: this.data.list.filter((r) => String(r.id) !== String(rec.id)) });
    } catch (e) { /* 删除失败静默 */ }
  },
});
