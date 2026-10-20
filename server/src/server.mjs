import { createServer } from "node:http";
import { readFileSync } from "node:fs";
import { recognize } from "./recognize.mjs";

const MAX_BODY_BYTES = 4 * 1024 * 1024; // фото после сжатия в приложении весит 100–300 КБ
const HOUR_MS = 60 * 60 * 1000;

export function loadConfig(env = process.env) {
  return {
    port: Number(env.PORT || 8080),
    appToken: env.APP_TOKEN || "",
    mock: !env.MODEL_API_KEY,
    baseUrl: (env.MODEL_BASE_URL || "https://llm.api.cloud.yandex.net/v1").replace(/\/$/, ""),
    apiKey: env.MODEL_API_KEY || "",
    model: env.MODEL_NAME || "",
    extraHeaders: env.MODEL_EXTRA_HEADERS ? JSON.parse(env.MODEL_EXTRA_HEADERS) : {},
    timeoutMs: Number(env.MODEL_TIMEOUT_MS || 60_000),
    requestsPerHour: Number(env.REQUESTS_PER_HOUR || 30),
  };
}

/** Каждый запрос к модели платный, поэтому одному адресу — не больше N фото в час. */
function rateLimiter(limit) {
  const hits = new Map();
  return (ip) => {
    const now = Date.now();
    const recent = (hits.get(ip) || []).filter((time) => now - time < HOUR_MS);
    if (recent.length >= limit) return false;
    hits.set(ip, [...recent, now]);
    return true;
  };
}

function send(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(body));
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw Object.assign(new Error("Фото слишком большое"), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw Object.assign(new Error("Тело запроса — не JSON"), { status: 400 });
  }
}

export function createApp(config, products) {
  const allow = rateLimiter(config.requestsPerHour);

  return createServer(async (req, res) => {
    if (req.method === "GET" && req.url === "/health") return send(res, 200, { ok: true, mock: config.mock });
    if (req.method !== "POST" || req.url !== "/v1/fridge/recognize") return send(res, 404, { error: "Нет такого адреса" });
    if (config.appToken && req.headers["x-app-token"] !== config.appToken) return send(res, 401, { error: "Нет доступа" });

    // за Caddy настоящий адрес клиента приходит в X-Forwarded-For
    const ip = String(req.headers["x-forwarded-for"] || req.socket.remoteAddress).split(",")[0].trim();
    if (!allow(ip)) return send(res, 429, { error: "Слишком много фото подряд. Попробуй через час." });

    try {
      const { image } = await readJson(req);
      if (typeof image !== "string" || image.length < 100) return send(res, 400, { error: "В запросе нет фото" });
      const items = await recognize({ imageBase64: image, products, config });
      send(res, 200, { items });
    } catch (error) {
      if (error.status) return send(res, error.status, { error: error.message });
      console.error(new Date().toISOString(), "recognize failed:", error.message);
      send(res, 502, { error: "Не получилось распознать фото. Попробуй ещё раз." });
    }
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const config = loadConfig();
  const products = JSON.parse(readFileSync(new URL("../products.json", import.meta.url), "utf8"));
  if (!config.mock && !config.model) {
    console.error("Не задан MODEL_NAME");
    process.exit(1);
  }
  createApp(config, products).listen(config.port, () => {
    console.log(`Слушаю :${config.port}, ${config.mock ? "тестовый режим без модели" : `модель ${config.model}`}`);
  });
}
