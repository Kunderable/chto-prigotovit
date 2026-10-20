// Примерная стоимость блюд и покупок.
// Цены подставляет build.mjs из data/prices.json: { название: [₽ за 1 единицу, единица, вес 1 шт в г] }
const PRICES = /*__PRICES__*/{};
const SPOON_ML = { "ст.л.": 15, "ч.л.": 5 };
const MIN_PRICE_COVERAGE = 0.7; // если цены известны меньше чем для 70% продуктов, стоимость не показываем
const PRICE_STEPS = [100, 200, 300];

/** ₽ за одну единицу `unit` или null, если цену не пересчитать. */
function unitPrice(name, unit) {
  const p = PRICES[name];
  if (!p) return null;
  const [rub, pu, gramsPerPiece] = p;
  if (unit === pu) return rub;
  if (SPOON_ML[unit] && (pu === "г" || pu === "мл")) return rub * SPOON_ML[unit];
  if (unit === "шт" && pu === "г" && gramsPerPiece) return rub * gramsPerPiece;
  return null;
}

const costCache = new Map();

/** Стоимость продуктов на одну порцию (без соли, масла и специй), округлённая до 10 ₽, или null. */
function portionCost(r) {
  if (costCache.has(r.id)) return costCache.get(r.id);
  const paid = r.ingredients.filter((i) => !i.pantry && i.a != null);
  let total = 0, known = 0;
  for (const i of paid) {
    const up = unitPrice(i.n, i.u);
    if (up == null) continue;
    total += up * i.a;
    known++;
  }
  const value = paid.length && known / paid.length >= MIN_PRICE_COVERAGE ? Math.max(10, round10(total / (r.base || 2))) : null;
  costCache.set(r.id, value);
  return value;
}

/** Сколько придётся потратить в магазине по строкам списка покупок (с учётом целых упаковок). */
function buyCost(rows) {
  return Math.round(rows.filter((x) => !x.have).reduce((sum, x) => {
    const up = unitPrice(x.n, x.u);
    if (up == null) return sum;
    return sum + up * (x.packs ? x.packs * x.pack : x.toBuy || x.a || 0);
  }, 0) / 10) * 10;
}

const fmtRub = (n) => `${String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ")} ₽`;
const costLabel = (r) => { const c = portionCost(r); return c ? `≈ ${fmtRub(c)}` : null; };
