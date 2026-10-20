import { test } from "node:test";
import assert from "node:assert/strict";
import { parseModelReply, normalizeItems, buildRequest } from "../src/recognize.mjs";

const products = ["Яйца", "Молоко", "Куриное филе", "Сыр", "Сметана", "Огурец"];

test("ответ модели в блоке ```json разбирается", () => {
  const reply = 'Вот что вижу:\n```json\n{"items":[{"name":"Молоко","amount":900,"unit":"мл"}]}\n```';
  assert.deepEqual(parseModelReply(reply), { items: [{ name: "Молоко", amount: 900, unit: "мл" }] });
});

test("ответ без JSON — понятная ошибка, а не падение", () => {
  assert.throws(() => parseModelReply("Не могу разобрать фото"), /не похож на JSON/);
});

test("названия приводятся к списку продуктов, без учёта регистра и ё", () => {
  const items = normalizeItems([{ name: "яйца", amount: 6, unit: "шт" }, { name: "СЫР", amount: 200, unit: "г" }], products);
  assert.deepEqual(items, [
    { name: "Яйца", amount: 6, unit: "шт", known: true },
    { name: "Сыр", amount: 200, unit: "г", known: true },
  ]);
});

test("неизвестный продукт остаётся, но помечен; мусор и повторы отбрасываются", () => {
  const items = normalizeItems([
    { name: "Кетчуп", amount: null, unit: null },
    { name: "", amount: 1, unit: "шт" },
    { name: "Молоко", amount: 900, unit: "мл" },
    { name: "молоко", amount: 500, unit: "мл" },
    { name: "Огурец", amount: -3, unit: "шт" },
    { name: "Сметана", amount: 200, unit: "кг" },
  ], products);
  assert.deepEqual(items, [
    { name: "Кетчуп", amount: null, unit: "", known: false },
    { name: "Молоко", amount: 900, unit: "мл", known: true },
    { name: "Огурец", amount: null, unit: "", known: true },
    { name: "Сметана", amount: null, unit: "", known: true },
  ]);
});

test("запрос к модели: фото в base64 и список продуктов в подсказке", () => {
  const body = buildRequest({ model: "test-model", imageBase64: "AAAA", products });
  assert.equal(body.model, "test-model");
  const content = body.messages.at(-1).content;
  assert.equal(content.find((part) => part.type === "image_url").image_url.url, "data:image/jpeg;base64,AAAA");
  assert.match(body.messages[0].content, /Куриное филе/);
});
