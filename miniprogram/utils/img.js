// 隐藏 canvas 帮手：像素采样 / 裁剪导出 / 压缩 dataURL 全走同一块画布
// 用法：页面放 <canvas type="2d" id="workCanvas" class="work-canvas"></canvas>，
//       onReady 里 const work = await img.bindPage('#workCanvas')
class WorkCanvas {
  constructor(node) {
    this.canvas = node;
    this.ctx = node.getContext("2d");
  }

  ensure(w, h) {
    if (this.canvas.width !== w) this.canvas.width = w;
    if (this.canvas.height !== h) this.canvas.height = h;
    return this.ctx;
  }

  loadImage(src) {
    return new Promise((resolve, reject) => {
      const img = this.canvas.createImage();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("图片加载失败"));
      img.src = src;
    });
  }

  // 导出当前画布内容为 jpg 临时文件
  exportJpg(quality) {
    return new Promise((resolve, reject) => {
      wx.canvasToTempFilePath({
        canvas: this.canvas,
        fileType: "jpg",
        quality,
        destWidth: this.canvas.width,
        destHeight: this.canvas.height,
        success: (r) => resolve(r.tempFilePath),
        fail: () => reject(new Error("画布导出失败")),
      });
    });
  }

  // 画到画布上并返回尺寸
  async drawScaled(src, maxEdge) {
    const img = await this.loadImage(src);
    const scale = Math.min(1, maxEdge / Math.max(img.width, img.height));
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));
    this.ensure(w, h);
    this.ctx.drawImage(img, 0, 0, w, h);
    return { w, h };
  }

  // 下采样后的 RGBA 像素（自顶向下，与网页 canvas.getImageData 一致）
  async pixels(src, maxEdge) {
    const { w, h } = await this.drawScaled(src, maxEdge);
    const data = this.ctx.getImageData(0, 0, w, h).data;
    return { width: w, height: h, data };
  }

  // 上传前压缩：最长边 maxEdge、quality，返回 dataURL（Worker 只认这个格式）
  async compressToDataUrl(src, maxEdge = 1280, quality = 0.72) {
    await this.drawScaled(src, maxEdge);
    const path = await this.exportJpg(quality);
    const b64 = wx.getFileSystemManager().readFileSync(path, "base64");
    return "data:image/jpeg;base64," + b64;
  }
}

// 从页面查询 canvas 节点并包成 WorkCanvas
function bindPage(canvasId) {
  return new Promise((resolve, reject) => {
    wx.createSelectorQuery()
      .select(canvasId)
      .fields({ node: true })
      .exec((res) => {
        if (res && res[0] && res[0].node) resolve(new WorkCanvas(res[0].node));
        else reject(new Error("canvas 节点未找到：" + canvasId));
      });
  });
}

module.exports = { bindPage };
