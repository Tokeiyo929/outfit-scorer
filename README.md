# 穿搭打分 · 微信小程序

拍一张全身照（或从相册选择），自动识别上衣和裤子的颜色，给出配色评分和建议；支持天气穿搭提示、历史记录管理。

- `miniprogram/` — 微信小程序（原生框架，无构建步骤）：打分（天气卡 → 拍照/选图 → 裁剪 → 拖分界线识别 → 点照取色 → 保存）+ 历史（编辑/删除/下拉刷新）
- `outfit-worker/` — Cloudflare Worker 后端：记录存 Neon Postgres，照片存腾讯 COS，绑 `outfit.tuqingyu.xyz`（workers.dev 被墙，弃用）
- `index.html` — 最初的纯前端网页版，识别算法的源头，仍可独立使用
- `ci/` — miniprogram-ci 自动上传：`main` 分支每次 commit 后自动把 `miniprogram/` 上传为微信后台开发版本

## 识别原理

canvas 缩样 → 边框主色判背景 → HSV 直方图主色聚类（排除背景与肤色）→ 中文色名 + HSL 配色规则评分。全部在端上本地完成（`miniprogram/utils/analyzer.js`），照片只在保存记录时才上传。

## 开发

1. 微信开发者工具打开 `miniprogram/` 目录（appid 见 `miniprogram/project.config.json`）
2. 详情 → 本地设置 → 勾选「不校验合法域名」（开发期直连第三方天气 API）
3. **正式发布前**需在 mp.weixin.qq.com → 开发管理 → 服务器域名，把以下域名加入 request 合法域名：
   - `outfit.tuqingyu.xyz`（自有后端）
   - `api.open-meteo.com`、`geocoding-api.open-meteo.com`（天气/地理编码）
   - `api.bigdatacloud.net`（逆地理解析城市名）
   - `ipwho.is`、`ipinfo.io`、`api.ip.sb`（IP 定位兜底）
4. `wx.getLocation` 属隐私接口，需在小程序后台「隐私保护指引」中申报位置信息用途

## 自动上传

`main` 分支 commit 后，post-commit hook 调 `ci/upload-miniprogram.js`（miniprogram-ci）把代码上传为开发版本，日志在 `ci/output/upload-on-commit.log`。上传私钥放 `ci/profiles/private.<appid>.key`（已 gitignore，不入库）。

手动上传：

```
node ci/upload-miniprogram.js --private-key-path ci/profiles/private.wxd40973d90aa34b31.key
```

## 后端部署

```
cd outfit-worker && npm run deploy
```
