// Outfit Worker - 穿搭打分记录 API（照片存腾讯 COS，数据存 Neon Postgres）
// 结构沿用 MyFood myfood-worker 的实现
import { neon } from "@neondatabase/serverless";

const CONFIG = {
  storage: { prefix: "outfit/", signature_expiry: 600, upload_signed_url_expiry: 3600, upload_timeout: 90000 },
  image: { max_upload_bytes: 8 * 1024 * 1024, signed_url_expiry: 604800 },
  records: { max_page_size: 100, default_page_size: 30 },
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const json = (v, status = 200) => new Response(JSON.stringify(v), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS_HEADERS },
});

let schemaPromise;
function ensureSchema(sql) {
  if (!schemaPromise) {
    schemaPromise = (async () => {
      await sql`CREATE TABLE IF NOT EXISTS outfit_records (
        id BIGSERIAL PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        photo_key VARCHAR(300) NOT NULL DEFAULT '',
        top_name VARCHAR(64) NOT NULL DEFAULT '',
        top_hex VARCHAR(8) NOT NULL DEFAULT '',
        top_hsl VARCHAR(64) NOT NULL DEFAULT '',
        bottom_name VARCHAR(64) NOT NULL DEFAULT '',
        bottom_hex VARCHAR(8) NOT NULL DEFAULT '',
        bottom_hsl VARCHAR(64) NOT NULL DEFAULT '',
        boundary REAL NOT NULL DEFAULT 0.52,
        score INT NOT NULL DEFAULT 0,
        grade VARCHAR(16) NOT NULL DEFAULT '',
        sub VARCHAR(200) NOT NULL DEFAULT '',
        comments TEXT NOT NULL DEFAULT '[]'
      )`;
      await sql`CREATE INDEX IF NOT EXISTS outfit_records_created_idx ON outfit_records (created_at DESC)`;
      await sql`ALTER TABLE outfit_records ADD COLUMN IF NOT EXISTS comment TEXT NOT NULL DEFAULT ''`;
      await sql`ALTER TABLE outfit_records ADD COLUMN IF NOT EXISTS top_bad BOOLEAN NOT NULL DEFAULT false`;
      await sql`ALTER TABLE outfit_records ADD COLUMN IF NOT EXISTS bottom_bad BOOLEAN NOT NULL DEFAULT false`;
      await sql`CREATE TABLE IF NOT EXISTS outfit_inspirations (
        id BIGSERIAL PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        photo_key VARCHAR(300) NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT ''
      )`;
      await sql`CREATE INDEX IF NOT EXISTS outfit_inspirations_created_idx ON outfit_inspirations (created_at DESC)`;
    })().catch(error => { schemaPromise = null; throw error; });
  }
  return schemaPromise;
}

/* ---------------- COS（与 myfood-worker 同一套签名实现） ---------------- */
function cosConfig(env) {
  const { COS_SECRET_ID: secretId, COS_SECRET_KEY: secretKey, COS_BUCKET: bucket, COS_REGION: region } = env;
  if (![secretId, secretKey, bucket, region].every(value => typeof value === "string" && value)) {
    throw new Error("COS configuration missing");
  }
  return { secretId, secretKey, host: `${bucket}.cos.${region}.myqcloud.com` };
}

async function sha1HexStr(data) {
  const buf = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(data));
  return hex(new Uint8Array(buf));
}
async function hmacSha1(data, key) {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(data));
  return hex(new Uint8Array(sig));
}
function hex(buf) { return [...buf].map(b => b.toString(16).padStart(2, "0")).join(""); }

function cosAuth(method, path, host, secretId, secretKey, expiry) {
  return (async () => {
    const formatStr = `${method}\n${path}\n\nhost=${host}\n`;
    const sha1Hex = await sha1HexStr(formatStr);
    const now = Math.floor(Date.now() / 1000) - 60;
    const end = now + expiry;
    const signTime = `${now};${end}`;
    const strToSign = `sha1\n${signTime}\n${sha1Hex}\n`;
    const signKey = await hmacSha1(signTime, secretKey);
    const signature = await hmacSha1(strToSign, signKey);
    return `q-sign-algorithm=sha1&q-ak=${secretId}&q-sign-time=${signTime}&q-key-time=${signTime}&q-header-list=host&q-url-param-list=&q-signature=${signature}`;
  })();
}

async function cosSignedUrl(env, key) {
  if (!key) return "";
  const { secretId, secretKey, host } = cosConfig(env);
  const q = await cosAuth("get", "/" + key, host, secretId, secretKey, CONFIG.image.signed_url_expiry);
  return `https://${host}/${key}?${q}`;
}

async function cosPut(env, key, body, contentType) {
  const { secretId, secretKey, host } = cosConfig(env);
  const auth = await cosAuth("put", "/" + key, host, secretId, secretKey, CONFIG.storage.upload_signed_url_expiry);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), CONFIG.storage.upload_timeout);
  try {
    const response = await fetch(`https://${host}/${encodeURI(key)}`, {
      method: "PUT",
      headers: { Authorization: auth, "Content-Type": contentType },
      body,
      signal: controller.signal,
    });
    if (!response.ok) throw new Error("COS upload failed: " + response.status);
  } catch (e) {
    if (e.name === "AbortError") throw new Error("COS upload timeout");
    throw e;
  } finally {
    clearTimeout(timeout);
  }
}

async function cosDeleteObject(env, key) {
  if (!key.startsWith(CONFIG.storage.prefix)) return false;
  const { secretId, secretKey, host } = cosConfig(env);
  const auth = await cosAuth("delete", "/" + key, host, secretId, secretKey, CONFIG.storage.signature_expiry);
  const res = await fetch(`https://${host}/${encodeURI(key)}?${auth}`, { method: "DELETE", headers: { "User-Agent": "outfit-worker" } });
  return res.ok;
}

/* ---------------- 记录 ---------------- */
async function signRecords(env, rows) {
  return Promise.all(rows.map(async r => {
    const out = {
      id: r.id,
      created_at: r.created_at,
      top: { name: r.top_name, hex: r.top_hex, hsl: r.top_hsl },
      bottom: { name: r.bottom_name, hex: r.bottom_hex, hsl: r.bottom_hsl },
      boundary: r.boundary,
      score: r.score,
      comment: r.comment || "",
      top_bad: !!r.top_bad,
      bottom_bad: !!r.bottom_bad,
    };
    if (r.photo_key) out.photo_url = await cosSignedUrl(env, r.photo_key);
    return out;
  }));
}

function todayStamp() {
  return new Date().toISOString().slice(0, 10).replace(/-/g, "");
}

/* 照片数据URL解析：{buf, contentType, ext} / {error} / null（没传） */
function parsePhoto(photo) {
  if (typeof photo !== "string" || !photo.startsWith("data:image/")) return null;
  const commaIdx = photo.indexOf(",");
  const meta = photo.slice(5, commaIdx); // image/jpeg;base64
  const b64 = photo.slice(commaIdx + 1);
  const buf = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  if (buf.byteLength > CONFIG.image.max_upload_bytes) {
    return { error: `照片太大：${(buf.byteLength / 1024 / 1024).toFixed(1)}MB 上限 8MB` };
  }
  const contentType = meta.includes("png") ? "image/png" : "image/jpeg";
  const ext = contentType === "image/png" ? "png" : "jpg";
  return { buf, contentType, ext };
}
async function storePhoto(env, parsed) {
  const key = `${CONFIG.storage.prefix}${todayStamp()}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${parsed.ext}`;
  await cosPut(env, key, parsed.buf, parsed.contentType);
  return key;
}

async function saveRecord(env, body) {
  const rec = body && body.record;
  const parsed = parsePhoto(body && body.photo);
  if (!parsed) {
    return json({ error: "photo 数据URL缺失或格式不对" }, 400);
  }
  if (parsed.error) return json({ error: parsed.error }, 413);
  const key = await storePhoto(env, parsed);

  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const t = (rec && rec.top) || {}, b = (rec && rec.bottom) || {};
  const rows = await sql`
    INSERT INTO outfit_records
      (photo_key, top_name, top_hex, top_hsl, bottom_name, bottom_hex, bottom_hsl,
       boundary, score, comment, top_bad, bottom_bad)
    VALUES
      (${key}, ${String(t.name || "")}, ${String(t.hex || "")}, ${String(t.hsl || "")},
       ${String(b.name || "")}, ${String(b.hex || "")}, ${String(b.hsl || "")},
       ${Number(rec && rec.boundary) || 0.52},
       ${Math.max(0, Math.min(100, Math.round(Number(rec && rec.score) || 0)))},
       ${String((rec && rec.comment) || "")},
       ${!!(rec && rec.top_bad)}, ${!!(rec && rec.bottom_bad)})
    RETURNING id, created_at`;
  const photoUrl = await cosSignedUrl(env, key);
  return json({ ok: true, id: rows[0].id, created_at: rows[0].created_at, photo_key: key, photo_url: photoUrl });
}

/* 编辑历史记录：评分/点评/雷点，可选换照片（传了就传 COS 新key、删旧图） */
async function updateRecord(env, id, body) {
  const rec = body || {};
  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const rows = await sql`SELECT id, photo_key FROM outfit_records WHERE id = ${id}`;
  if (!rows.length) return json({ error: "记录不存在" }, 404);

  const parsed = parsePhoto(rec.photo);
  if (parsed && parsed.error) return json({ error: parsed.error }, 413);
  let photoKey = rows[0].photo_key;
  if (parsed) {
    const newKey = await storePhoto(env, parsed);
    await cosDeleteObject(env, photoKey); // 删旧照片，失败不阻塞编辑
    photoKey = newKey;
  }

  await sql`
    UPDATE outfit_records SET
      score = ${Math.max(0, Math.min(100, Math.round(Number(rec.score) || 0)))},
      comment = ${String(rec.comment || "")},
      top_bad = ${!!rec.top_bad},
      bottom_bad = ${!!rec.bottom_bad},
      photo_key = ${photoKey}
    WHERE id = ${id}`;
  const photoUrl = photoKey ? await cosSignedUrl(env, photoKey) : "";
  return json({ ok: true, id, photo_url: photoUrl });
}

async function listRecords(env, url) {
  const limit = Math.min(Number(url.searchParams.get("limit")) || CONFIG.records.default_page_size, CONFIG.records.max_page_size);
  const offset = Math.max(Number(url.searchParams.get("offset")) || 0, 0);
  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const rows = await sql`SELECT * FROM outfit_records ORDER BY created_at DESC, id DESC LIMIT ${limit} OFFSET ${offset}`;
  const records = await signRecords(env, rows);
  return json({ records, has_more: rows.length === limit });
}

async function deleteRecord(env, id) {
  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const rows = await sql`SELECT photo_key FROM outfit_records WHERE id = ${id}`;
  if (!rows.length) return json({ error: "记录不存在" }, 404);
  let photo_deleted = false;
  if (rows[0].photo_key) photo_deleted = await cosDeleteObject(env, rows[0].photo_key);
  await sql`DELETE FROM outfit_records WHERE id = ${id}`;
  return json({ ok: true, photo_deleted });
}

/* ---------------- 灵感收藏（喜欢的别人穿搭图） ---------------- */
async function signInspirations(env, rows) {
  return Promise.all(rows.map(async r => {
    const out = { id: r.id, created_at: r.created_at, note: r.note || "" };
    if (r.photo_key) out.photo_url = await cosSignedUrl(env, r.photo_key);
    return out;
  }));
}

async function listInspirations(env, url) {
  const limit = Math.min(Number(url.searchParams.get("limit")) || CONFIG.records.default_page_size, CONFIG.records.max_page_size);
  const offset = Math.max(Number(url.searchParams.get("offset")) || 0, 0);
  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const rows = await sql`SELECT * FROM outfit_inspirations ORDER BY created_at DESC, id DESC LIMIT ${limit} OFFSET ${offset}`;
  const inspirations = await signInspirations(env, rows);
  return json({ inspirations, has_more: rows.length === limit });
}

async function saveInspiration(env, body) {
  const parsed = parsePhoto(body && body.photo);
  if (!parsed) return json({ error: "photo 数据URL缺失或格式不对" }, 400);
  if (parsed.error) return json({ error: parsed.error }, 413);
  const key = await storePhoto(env, parsed);
  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const rows = await sql`
    INSERT INTO outfit_inspirations (photo_key, note)
    VALUES (${key}, ${String((body && body.note) || "").slice(0, 200)})
    RETURNING id, created_at`;
  const photoUrl = await cosSignedUrl(env, key);
  return json({ ok: true, id: rows[0].id, created_at: rows[0].created_at, photo_key: key, photo_url: photoUrl });
}

async function deleteInspiration(env, id) {
  const sql = neon(env.DATABASE_URL);
  await ensureSchema(sql);
  const rows = await sql`SELECT photo_key FROM outfit_inspirations WHERE id = ${id}`;
  if (!rows.length) return json({ error: "收藏不存在" }, 404);
  let photo_deleted = false;
  if (rows[0].photo_key) photo_deleted = await cosDeleteObject(env, rows[0].photo_key);
  await sql`DELETE FROM outfit_inspirations WHERE id = ${id}`;
  return json({ ok: true, photo_deleted });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
    try {
      if (path === "/api/health") return json({ ok: true, ts: Date.now() });
      if (path === "/api/records" && request.method === "GET") return await listRecords(env, url);
      if (path === "/api/records" && request.method === "POST") return await saveRecord(env, await request.json());
      if (path.startsWith("/api/records/") && request.method === "PUT") {
        const id = Number(path.slice("/api/records/".length));
        if (!Number.isInteger(id) || id <= 0) return json({ error: "非法 id" }, 400);
        return await updateRecord(env, id, await request.json());
      }
      if (path.startsWith("/api/records/") && request.method === "DELETE") {
        const id = Number(path.slice("/api/records/".length));
        if (!Number.isInteger(id) || id <= 0) return json({ error: "非法 id" }, 400);
        return await deleteRecord(env, id);
      }
      if (path === "/api/inspirations" && request.method === "GET") return await listInspirations(env, url);
      if (path === "/api/inspirations" && request.method === "POST") return await saveInspiration(env, await request.json());
      if (path.startsWith("/api/inspirations/") && request.method === "DELETE") {
        const id = Number(path.slice("/api/inspirations/".length));
        if (!Number.isInteger(id) || id <= 0) return json({ error: "非法 id" }, 400);
        return await deleteInspiration(env, id);
      }
      return json({ error: "not found" }, 404);
    } catch (error) {
      console.error("[outfit-worker]", path, error && error.message);
      return json({ error: error && error.message || "internal error" }, 500);
    }
  },
};
