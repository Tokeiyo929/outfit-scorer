// 天气定位与查询
// 定位链：wx.getLocation → IP 定位兜底（ipwho.is → ipinfo.io → api.ip.sb，国内可直连）

function fetchJson(url, timeout) {
  return new Promise((resolve, reject) => {
    wx.request({
      url,
      timeout: timeout * 1000,
      success(res) {
        if (res.statusCode >= 200 && res.statusCode < 300 && res.data && typeof res.data === "object") {
          resolve(res.data);
        } else {
          reject(new Error("请求异常"));
        }
      },
      fail() { reject(new Error("请求异常")); },
    });
  });
}

function wxLocation(timeout) {
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    wx.getLocation({
      type: "wgs84",
      success: (r) => finish({ pos: { lat: r.latitude, lon: r.longitude, city: "" } }),
      fail: (e) => {
        // 接口权限未开通/隐私指引未声明/用户拒绝，errMsg 各不相同，打出来才好定位
        console.error("[weather] getLocation fail:", e && e.errMsg);
        finish(null);
      },
    });
    setTimeout(() => finish(null), timeout * 1000);
  });
}

async function ipLocate() {
  try {
    const d = await fetchJson("https://ipwho.is/", 6);
    if (typeof d.latitude === "number" && typeof d.longitude === "number") {
      return { lat: d.latitude, lon: d.longitude, city: d.city || d.region || "" };
    }
  } catch (e) {}
  try {
    const d = await fetchJson("https://ipinfo.io/json", 6);
    if (typeof d.loc === "string") {
      const xy = d.loc.split(",").map(Number).filter((v) => !isNaN(v));
      if (xy.length === 2) return { lat: xy[0], lon: xy[1], city: d.city || d.region || "" };
    }
  } catch (e) {}
  try {
    const d = await fetchJson("https://api.ip.sb/geoip", 6);
    if (typeof d.latitude === "number" && typeof d.longitude === "number") {
      return { lat: d.latitude, lon: d.longitude, city: d.city || d.region || "" };
    }
  } catch (e) {}
  return null;
}

async function geoLocate() {
  const gps = await wxLocation(8);
  return (gps && gps.pos) || (await ipLocate());
}

async function cityToPos(name) {
  const enc = encodeURIComponent(name);
  const d = await fetchJson(`https://geocoding-api.open-meteo.com/v1/search?name=${enc}&count=1&language=zh`, 8);
  const r = d.results && d.results[0];
  if (!r || typeof r.latitude !== "number") throw new Error("找不到城市");
  return { lat: r.latitude, lon: r.longitude, city: r.name || name };
}

const wmoText = {
  0: "☀️ 晴", 1: "🌤 基本晴", 2: "⛅ 多云", 3: "☁️ 阴",
  45: "🌫 有雾", 48: "🌫 冻雾",
  51: "🌦 毛毛雨", 53: "🌦 毛毛雨", 55: "🌧 密毛毛雨", 56: "🌧 冻毛毛雨", 57: "🌧 冻毛毛雨",
  61: "🌦 小雨", 63: "🌧 中雨", 65: "🌧 大雨", 66: "🌧 冻雨", 67: "🌧 冻雨",
  71: "🌨 小雪", 73: "🌨 中雪", 75: "❄️ 大雪", 77: "🌨 米雪",
  80: "🌦 阵雨", 81: "🌧 强阵雨", 82: "⛈ 暴雨", 85: "🌨 阵雪", 86: "❄️ 强阵雪",
  95: "⛈ 雷阵雨", 96: "⛈ 雷雨冰雹", 99: "⛈ 雷雨冰雹",
};

function wmo(code) {
  const s = wmoText[code] || "🌤 未知";
  const idx = s.indexOf(" ");
  return idx < 0 ? [s, ""] : [s.slice(0, idx), s.slice(idx + 1)];
}

function dressHint(temp, code) {
  let h = temp < 0 ? "严寒：厚羽绒服、保暖内搭"
    : temp < 8 ? "冷：大衣或厚外套"
    : temp < 15 ? "凉：夹克、薄外套"
    : temp < 22 ? "舒适：长袖或薄外套"
    : temp < 28 ? "暖：短袖或薄长袖"
    : "热：透气短袖";
  if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95) h += " · 有雨记得带伞";
  else if ((code >= 71 && code <= 77) || code === 85 || code === 86) h += " · 有雪注意防滑";
  return h;
}

// 每次打开自动获取：手动城市优先，否则 GPS→IP
async function loadWeather(cityName) {
  const isManual = !!(cityName && cityName.length);
  try {
    let pos;
    if (isManual) {
      pos = await cityToPos(cityName);
    } else {
      const p = await geoLocate();
      if (!p) throw new Error("定位失败");
      pos = p;
    }
    let city = pos.city;
    if (!city) {
      try {
        const r = await fetchJson(`https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${pos.lat}&longitude=${pos.lon}&localityLanguage=zh`, 6);
        city = r.city || r.locality || r.principalSubdivision || "";
      } catch (e) {}
    }
    const w = await fetchJson(`https://api.open-meteo.com/v1/forecast?latitude=${pos.lat}&longitude=${pos.lon}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m&timezone=auto`, 8);
    const cur = w.current;
    if (!cur || typeof cur.temperature_2m !== "number" || typeof cur.weather_code !== "number") {
      throw new Error("天气数据异常");
    }
    const temp = cur.temperature_2m;
    const feels = typeof cur.apparent_temperature === "number" ? cur.apparent_temperature : temp;
    const hum = typeof cur.relative_humidity_2m === "number" ? Math.round(cur.relative_humidity_2m) : 0;
    const wind = typeof cur.wind_speed_10m === "number" ? cur.wind_speed_10m : 0;
    const [icon, text] = wmo(cur.weather_code);
    return {
      ok: true,
      weather: {
        icon, text, city,
        temp: Math.round(temp), feels: Math.round(feels),
        humidity: hum, wind: Math.round(wind),
        hint: dressHint(feels, cur.weather_code),
      },
    };
  } catch (e) {
    const msg = isManual ? "找不到城市，换个名字试试" : "定位失败，手动输城市查询";
    return { ok: false, error: e && e.message === "找不到城市" ? e.message : msg };
  }
}

module.exports = { loadWeather };
