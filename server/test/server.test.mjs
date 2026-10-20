import { test } from "node:test";
import assert from "node:assert/strict";
import { createApp, loadConfig } from "../src/server.mjs";

async function withServer(env, run) {
  const app = createApp(loadConfig(env), ["Яйца", "Молоко", "Сыр", "Огурец"]);
  await new Promise((resolve) => app.listen(0, resolve));
  try {
    await run(`http://127.0.0.1:${app.address().port}`);
  } finally {
    app.close();
  }
}

const photo = JSON.stringify({ image: "A".repeat(200) });

test("без ключа модели сервер в тестовом режиме отдаёт заготовку", async () => {
  await withServer({ APP_TOKEN: "secret" }, async (url) => {
    const health = await (await fetch(`${url}/health`)).json();
    assert.deepEqual(health, { ok: true, mock: true });

    const res = await fetch(`${url}/v1/fridge/recognize`, { method: "POST", headers: { "X-App-Token": "secret" }, body: photo });
    assert.equal(res.status, 200);
    const { items } = await res.json();
    assert.ok(items.some((item) => item.name === "Молоко" && item.known));
  });
});

test("без токена приложения — 401, без фото — 400", async () => {
  await withServer({ APP_TOKEN: "secret" }, async (url) => {
    assert.equal((await fetch(`${url}/v1/fridge/recognize`, { method: "POST", body: photo })).status, 401);
    const empty = await fetch(`${url}/v1/fridge/recognize`, { method: "POST", headers: { "X-App-Token": "secret" }, body: "{}" });
    assert.equal(empty.status, 400);
  });
});

test("лимит фото в час на один адрес", async () => {
  await withServer({ REQUESTS_PER_HOUR: "2" }, async (url) => {
    const post = () => fetch(`${url}/v1/fridge/recognize`, { method: "POST", body: photo });
    assert.equal((await post()).status, 200);
    assert.equal((await post()).status, 200);
    assert.equal((await post()).status, 429);
  });
});
