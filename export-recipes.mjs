// Проверяет рецепты и цены из data/ и выгружает их в ресурсы iOS-приложения.
// Запуск: node export-recipes.mjs
import { readFileSync, writeFileSync, readdirSync, mkdirSync } from "node:fs";

const IOS_RESOURCES = "ios/WhatToCook/Resources";
const DATA_DIR = "data/recipes";
const SPOON_UNITS = ["ст.л.", "ч.л."];

/** Цены: { название: [₽ за 1 единицу, единица, вес 1 шт в г] }. */
function loadPrices() {
  const { items } = JSON.parse(readFileSync("data/prices.json", "utf8"));
  return Object.fromEntries(Object.entries(items).map(([n, [rub, qty, unit, gpp]]) => [n, [+(rub / qty).toFixed(4), unit, gpp || 0]]));
}

/** Можно ли посчитать стоимость ингредиента в его единицах (та же логика, что в ios/WhatToCook/Logic/Pricing.swift). */
function priceable(prices, n, u) {
  const p = prices[n];
  if (!p) return false;
  const [, pu, gpp] = p;
  return u === pu || (SPOON_UNITS.includes(u) && (pu === "г" || pu === "мл")) || (u === "шт" && pu === "г" && gpp > 0);
}

const UNITS = ["г", "мл", "шт", "зубч.", "ст.л.", "ч.л.", ""];
const TAGS = ["meat", "pork", "fish", "dairy", "gluten"];
const SOUP_RE = /суп|борщ|^щи |уха |уха$|солянка|рассольник|харчо|шурпа|мастава|мошхурда|чихиртма|^фо |том ям|том кха|гаспачо|чаудер|авголемоно|ччигэ|мугук|потахе|фасолада|минестроне|рамен|окрошка/i;
const GOALS = { lose: (r) => r.kcal <= 500, lowcarb: (r) => r.c <= 20, protein: (r) => r.p >= 35 };

/** Когда едят блюдо: w = "b" только завтрак, "bm" завтрак и основное, "m" (по умолчанию) обед/ужин; супы только на обед. */
function mealsFor(w, name) {
  if (w === "b") return ["breakfast"];
  if (w === "bm") return ["breakfast", "lunch", "dinner"];
  return SOUP_RE.test(name) ? ["lunch"] : ["lunch", "dinner"];
}

/**
 * Формат файла: { code, cuisine, w?, recipes: [...] }
 * Рецепт: { n, e, t, b?, w?, cu?, m: [Б, Ж, У] на порцию, g: теги, i: [[название, кол-во|null, ед., упаковка|0, 1 если запасы]], s: [шаги] }
 * Калории считаются из БЖУ: 4·Б + 9·Ж + 4·У.
 */
function expand(doc, raw, index, errors) {
  const where = `${doc.code}#${index + 1} «${raw.n}»`;
  const fail = (msg) => errors.push(`${where}: ${msg}`);
  if (typeof raw.n !== "string" || !raw.n.trim()) fail("нет названия");
  if (!Array.isArray(raw.m) || raw.m.length !== 3 || raw.m.some((x) => !Number.isFinite(x) || x < 0)) fail("m должно быть [Б, Ж, У]");
  if (!Number.isFinite(raw.t) || raw.t < 3 || raw.t > 300) fail("время вне 3–300 мин");
  if (!Array.isArray(raw.g) || raw.g.some((t) => !TAGS.includes(t))) fail(`теги только из ${TAGS.join(", ")}`);
  if (raw.g?.includes("pork") && !raw.g.includes("meat")) fail("pork без meat");
  if (!Array.isArray(raw.i) || raw.i.length < 2) fail("меньше 2 ингредиентов");
  if (!Array.isArray(raw.s) || raw.s.length < 3) fail("меньше 3 шагов");
  (raw.s || []).forEach((s, k) => { if (typeof s !== "string" || s.length < 15) fail(`шаг ${k + 1} слишком короткий`); });
  const w = raw.w || doc.w || "m";
  if (!["b", "bm", "m"].includes(w)) fail(`w «${w}»`);

  const ingredients = (raw.i || []).map((t, k) => {
    const [n, a, u, pack, pantry] = t;
    if (typeof n !== "string" || !n) fail(`ингредиент ${k + 1} без названия`);
    if (!UNITS.includes(u)) fail(`«${n}»: единица «${u}»`);
    if (a !== null && !(Number.isFinite(a) && a > 0)) fail(`«${n}»: количество ${a}`);
    if (a === null && !pantry) fail(`«${n}»: «по вкусу» только для запасов`);
    return { n, a, u, ...(pack ? { pack } : {}), ...(pantry ? { pantry: true } : {}) };
  });
  const [p, f, c] = raw.m || [0, 0, 0];
  return {
    id: `${doc.code}${String(index + 1).padStart(3, "0")}`,
    name: raw.n, emoji: raw.e || "🍲", cuisine: raw.cu || doc.cuisine, time: raw.t, base: raw.b || 2,
    meal: mealsFor(w, raw.n || ""),
    kcal: Math.round((4 * p + 9 * f + 4 * c) / 10) * 10, p, f, c,
    tags: raw.g || [], ingredients, steps: raw.s || [],
  };
}

function loadRecipes(errors) {
  const files = readdirSync(DATA_DIR).filter((f) => f.endsWith(".json")).sort();
  const recipes = files.flatMap((file) => {
    const doc = JSON.parse(readFileSync(`${DATA_DIR}/${file}`, "utf8"));
    return doc.recipes.map((r, i) => expand(doc, r, i, errors));
  });
  const seen = new Map();
  for (const r of recipes) {
    const key = r.name.toLowerCase();
    if (seen.has(key)) errors.push(`повтор названия «${r.name}»: ${seen.get(key)} и ${r.id}`);
    seen.set(key, r.id);
  }
  return recipes;
}

const errors = [];
const recipes = loadRecipes(errors);
const prices = loadPrices();
for (const r of recipes) {
  for (const i of r.ingredients) {
    if (!i.pantry && !priceable(prices, i.n, i.u)) errors.push(`${r.id} «${r.name}»: нет цены для «${i.n}» в «${i.u}» — добавь в data/prices.json`);
  }
}
if (errors.length) {
  console.error(`Ошибки в данных (${errors.length}):\n` + errors.join("\n"));
  process.exit(1);
}

mkdirSync(IOS_RESOURCES, { recursive: true });
writeFileSync(`${IOS_RESOURCES}/recipes.json`, JSON.stringify(recipes));
writeFileSync(`${IOS_RESOURCES}/prices.json`, JSON.stringify(Object.fromEntries(
  Object.entries(prices).map(([n, [rub, unit, gramsPerPiece]]) => [n, { rub, unit, gramsPerPiece }]))));

const table = {};
for (const r of recipes) {
  const row = (table[r.cuisine] ||= { всего: 0, завтрак: 0, похудеть: 0, "мало углеводов": 0, белок: 0 });
  row.всего++;
  if (r.meal.includes("breakfast")) row.завтрак++;
  if (GOALS.lose(r)) row.похудеть++;
  if (GOALS.lowcarb(r)) row["мало углеводов"]++;
  if (GOALS.protein(r)) row.белок++;
}
console.table(table);
console.log(`Итого ${recipes.length} рецептов, завтраков ${recipes.filter((r) => r.meal.includes("breakfast")).length} → ${IOS_RESOURCES}`);
