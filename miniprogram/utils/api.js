// 记录 API —— 与 Worker 端契约零改动复用
// 国内直连自定义域（workers.dev 整域被墙，弃用）
const BASE = "https://outfit.tuqingyu.xyz";

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    wx.request({
      url: BASE + path,
      method,
      data: body,
      timeout: 30000,
      header: body ? { "Content-Type": "application/json" } : {},
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.data);
        } else {
          const msg = (res.data && res.data.error) || `请求失败：${res.statusCode}`;
          reject(new Error(msg));
        }
      },
      fail() {
        reject(new Error("网络异常，检查网络后重试"));
      },
    });
  });
}

// Postgres int8 经 postgres.js 出来是字符串（"10"），id 直接按 string 用
function listRecords(limit = 30) {
  return request("GET", `/api/records?limit=${limit}`);
}

function saveRecord(photo, record) {
  return request("POST", "/api/records", { photo, record });
}

function updateRecord(id, body) {
  return request("PUT", `/api/records/${id}`, body);
}

function deleteRecord(id) {
  return request("DELETE", `/api/records/${id}`);
}

// ---------------- 灵感收藏 ----------------
function listInspirations(limit = 60) {
  return request("GET", `/api/inspirations?limit=${limit}`);
}

function saveInspiration(photo, note) {
  return request("POST", "/api/inspirations", { photo, note });
}

function deleteInspiration(id) {
  return request("DELETE", `/api/inspirations/${id}`);
}

// "M月d日 HH:mm"，与网页端一致
function dateText(iso) {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `${d.getMonth() + 1}月${d.getDate()}日 ${hh}:${mm}`;
}

module.exports = { listRecords, saveRecord, updateRecord, deleteRecord, listInspirations, saveInspiration, deleteInspiration, dateText };
