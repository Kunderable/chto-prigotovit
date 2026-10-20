// Тесты логики без интерфейса: норма КБЖУ, цены, подбор блюд, дневник, остатки.
// Запуск: node build.mjs && node --test tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const html = readFileSync(new URL("../chto-prigotovit.html", import.meta.url), "utf8");
const script = html.slice(html.indexOf("<script>") + 8, html.lastIndexOf("</script>"));
const logic = script.slice(0, script.indexOf("/* ===== 08-motion.js ===== */"));

/** Свежий экземпляр логики приложения с заглушками вместо браузера. */
function app() {
  const ctx = vm.createContext({
    console,
    localStorage: { getItem: () => null, setItem: () => {} },
    window: {}, document: {}, navigator: {},
    render: () => {}, toast: () => {}, flash: () => {},
  });
  vm.runInContext(`${logic}
    globalThis.api = {
      get S() { return S; }, set S(v) { S = v; }, get UI() { return UI; },
      RECIPES, MEALS, dailyNorm, bodyError, parseCustomFood, portionCost, buyCost, unitPrice,
      ensureDay, replanKeepingDone, pickDish, fitsGoal, shoppingRows, toggleEaten, putMeal, cookDone, diaryFor, byId, rngFrom, dayKey,
    };`, ctx);
  return ctx.api;
}

const BODY = { sex: "f", age: 30, height: 165, weight: 65, activity: 1.375 };

test("норма: дефицит при похудении и БЖУ сходятся с калориями", () => {
  const a = app();
  const lose = a.dailyNorm(BODY, "lose");
  const normal = a.dailyNorm(BODY, "normal");
  assert.ok(lose.kcal < normal.kcal);
  assert.ok(Math.abs(lose.p * 4 + lose.f * 9 + lose.c * 4 - lose.kcal) < 30);
  assert.equal(a.dailyNorm(BODY, "lowcarb").c, 80);
  assert.equal(a.dailyNorm({ ...BODY, weight: 80 }, "protein").p, 160);
});

test("норма: проверка ввода", () => {
  const a = app();
  assert.ok(a.bodyError({ ...BODY, age: "" }));
  assert.ok(a.bodyError({ ...BODY, height: 300 }));
  assert.equal(a.bodyError({ sex: "m", age: "30", height: "180", weight: "80,5" }), null);
});

test("дневник: калории считаются из БЖУ, если не указаны", () => {
  const a = app();
  assert.equal(a.parseCustomFood({ name: "Яблоко", kcal: "", p: "0", f: "0", c: "20" }).entry.kcal, 80);
  assert.ok(a.parseCustomFood({ name: "", kcal: "100" }).error);
  assert.ok(a.parseCustomFood({ name: "Чай", kcal: "-5" }).error);
});

test("цены: у каждого рецепта есть стоимость порции", () => {
  const a = app();
  const missing = a.RECIPES.filter((r) => !a.portionCost(r)).map((r) => r.name);
  assert.equal(missing.length, 0, missing.join(", "));
  assert.equal(a.unitPrice("Картофель", "шт"), 9); // 60 ₽ за кг, 150 г в штуке
});

test("покупки: стоимость учитывает целые упаковки", () => {
  const a = app();
  const rub = a.buyCost([{ n: "Пармезан", u: "г", a: 50, toBuy: 50, pack: 150, packs: 1, have: false }]);
  assert.equal(rub, 450);
});

test("план дня: три приёма пищи нужного типа, без повторов", () => {
  const a = app();
  a.S = { ...a.S, onboarded: true, body: BODY };
  a.ensureDay();
  const meals = a.S.day.meals;
  const ids = a.MEALS.map(({ key }) => meals[key].id);
  assert.equal(new Set(ids).size, 3);
  for (const { key } of a.MEALS) assert.ok(a.byId(meals[key].id).meal.includes(key), key);
});

test("подбор: цель «мало углеводов» соблюдается для всех приёмов пищи", () => {
  const a = app();
  a.S = { ...a.S, body: BODY, prefs: { ...a.S.prefs, goal: "lowcarb", cuisines: [] } };
  for (let day = 0; day < 20; day++) {
    for (const { key } of a.MEALS) {
      const r = a.pickDish(key, a.rngFrom(`d${day}${key}`), new Set());
      assert.ok(r.c <= 20, `${key}: ${r.name} — ${r.c} г углеводов`);
    }
  }
});

test("подбор: ограничения «не ем» не нарушаются", () => {
  const a = app();
  a.S = { ...a.S, prefs: { ...a.S.prefs, avoid: ["meat", "fish"], cuisines: [] } };
  for (let i = 0; i < 40; i++) {
    const r = a.pickDish("dinner", a.rngFrom(`v${i}`), new Set());
    assert.ok(!r.tags.includes("meat") && !r.tags.includes("fish"), r.name);
  }
});

test("«съел»: запись появляется и исчезает, замена блюда её не стирает", () => {
  const a = app();
  a.S = { ...a.S, onboarded: true };
  a.ensureDay();
  a.toggleEaten("lunch");
  assert.equal(a.diaryFor().length, 1);
  a.toggleEaten("lunch");
  assert.equal(a.diaryFor().length, 0);
  a.toggleEaten("lunch");
  const other = a.RECIPES.find((r) => r.meal.includes("lunch") && r.id !== a.S.day.meals.lunch.id);
  a.putMeal("lunch", other.id);
  assert.equal(a.diaryFor().length, 1);
  assert.equal(a.S.day.meals.lunch.eaten, false);
});

test("«приготовил»: остаток упаковки уходит в холодильник", () => {
  const a = app();
  a.S = { ...a.S, onboarded: true };
  a.ensureDay();
  const carbonara = a.RECIPES.find((r) => r.name === "Паста карбонара");
  a.putMeal("dinner", carbonara.id);
  a.cookDone(carbonara, "dinner");
  const parmesan = a.S.fridge.find((f) => f.n === "Пармезан");
  assert.ok(parmesan, "пармезан должен остаться");
  assert.equal(parmesan.a, 100); // упаковка 150 г, на 2 порции нужно 50 г
});

test("смена цели: съеденное остаётся в плане, остальное подбирается заново", () => {
  const a = app();
  a.S = { ...a.S, onboarded: true, body: BODY };
  a.ensureDay();
  const breakfast = a.S.day.meals.breakfast.id;
  a.toggleEaten("breakfast");
  a.S = { ...a.S, prefs: { ...a.S.prefs, goal: "lowcarb" }, day: a.replanKeepingDone() };
  a.ensureDay();
  assert.equal(a.S.day.meals.breakfast.id, breakfast);
  assert.equal(a.S.day.meals.breakfast.eaten, true);
  assert.ok(a.byId(a.S.day.meals.dinner.id).c <= 20);
});
