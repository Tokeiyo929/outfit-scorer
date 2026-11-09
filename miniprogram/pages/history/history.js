// 历史页：列表 / 编辑 / 删除 / 下拉刷新
const img = require("../../utils/img");
const cm = require("../../utils/colormath");
const api = require("../../utils/api");

Page({
  data: {
    records: [],
    busy: false,
    error: "",

    // 编辑浮层
    editOpen: false,
    edit: null, // { id, score, comment, topBad, bottomBad, photoUrl, topName, bottomName }
    newPhotoPath: "",
    editBusy: false,
    editError: "",
  },

  work: null,

  noop() { /* 阻止浮层点击冒泡到遮罩 */ },

  async onReady() {
    try {
      this.work = await img.bindPage("#workCanvas");
    } catch (e) { /* 换照片压缩时才会用到 */ }
  },

  onShow() {
    this.loadHistory(true);
  },

  onPullDownRefresh() {
    this.loadHistory(true).then(() => wx.stopPullDownRefresh());
  },

  async loadHistory(force) {
    if (this.data.busy) return;
    if (!force && this.data.records.length) return;
    this.setData({ busy: true, error: "" });
    try {
      const resp = await api.listRecords(30);
      this.setData({
        busy: false,
        records: resp.records.map((r) => ({ ...r, dateText: api.dateText(r.created_at) })),
      });
    } catch (e) {
      this.setData({ busy: false, error: "记录加载失败，检查网络后重试" });
    }
  },

  async deleteRecord(e) {
    const id = e.currentTarget.dataset.id;
    const confirm = await new Promise((resolve) =>
      wx.showModal({
        title: "删除这条记录和照片？",
        confirmText: "删除",
        confirmColor: "#d5442e",
        success: (r) => resolve(r.confirm),
        fail: () => resolve(false),
      }));
    if (!confirm) return;
    try {
      await api.deleteRecord(id);
      this.setData({ records: this.data.records.filter((r) => String(r.id) !== String(id)) });
    } catch (err) { /* 删除失败静默 */ }
  },

  // ---------------- 编辑浮层 ----------------
  openEdit(e) {
    const id = e.currentTarget.dataset.id;
    const rec = this.data.records.find((r) => String(r.id) === String(id));
    if (!rec) return;
    this.setData({
      editOpen: true,
      editError: "",
      newPhotoPath: "",
      edit: {
        id: rec.id,
        score: rec.score,
        comment: rec.comment,
        topBad: rec.top_bad,
        bottomBad: rec.bottom_bad,
        photoUrl: rec.photo_url || "",
        topName: rec.top.name,
        bottomName: rec.bottom.name,
      },
    });
  },

  closeEdit() {
    this.setData({ editOpen: false, edit: null, newPhotoPath: "", editError: "" });
  },

  onEditScore(e) {
    this.setData({ "edit.score": e.detail.value });
  },

  onEditComment(e) {
    this.setData({ "edit.comment": e.detail.value });
  },

  toggleEditTopBad() {
    this.setData({ "edit.topBad": !this.data.edit.topBad });
  },

  toggleEditBottomBad() {
    this.setData({ "edit.bottomBad": !this.data.edit.bottomBad });
  },

  chooseEditPhoto() {
    wx.chooseMedia({
      count: 1,
      mediaType: ["image"],
      sourceType: ["album", "camera"],
      sizeType: ["original"],
      success: (res) => {
        const path = res.tempFiles && res.tempFiles[0] && res.tempFiles[0].tempFilePath;
        if (path) this.setData({ newPhotoPath: path });
      },
    });
  },

  async saveEdit() {
    if (this.data.editBusy || !this.data.edit) return;
    this.setData({ editBusy: true, editError: "" });
    try {
      let photo;
      if (this.data.newPhotoPath) {
        if (!this.work) this.work = await img.bindPage("#workCanvas");
        photo = await this.work.compressToDataUrl(this.data.newPhotoPath, 1280, 0.72);
      }
      const ed = this.data.edit;
      await api.updateRecord(ed.id, {
        score: Math.round(ed.score),
        comment: (ed.comment || "").trim(),
        topBad: ed.topBad,
        bottomBad: ed.bottomBad,
        photo,
      });
      this.setData({ editBusy: false });
      this.closeEdit();
      this.loadHistory(true);
    } catch (e) {
      this.setData({ editBusy: false, editError: "保存失败：" + e.message });
    }
  },

  async deleteFromEdit() {
    const ed = this.data.edit;
    if (!ed) return;
    const confirm = await new Promise((resolve) =>
      wx.showModal({
        title: "删除这条记录和照片？",
        confirmText: "删除",
        confirmColor: "#d5442e",
        success: (r) => resolve(r.confirm),
        fail: () => resolve(false),
      }));
    if (!confirm) return;
    try {
      await api.deleteRecord(ed.id);
    } catch (e) { /* 同列表删除，静默 */ }
    this.closeEdit();
    this.loadHistory(true);
  },
});
