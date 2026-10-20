// Подбор блюд на день.
const recentIds = (n) => S.history.slice(-n).map((x) => x.id);
const leftoverHits = (r) => r.ingredients.filter((i) => !i.pantry && S.fridge.some((f) => same(f.n, i.n)));
const likesCuisine = (r) => !S.prefs.cuisines.length || S.prefs.cuisines.some((c) => same(c, r.cuisine));

/** Подходит ли блюдо под цель для конкретного приёма пищи. */
function fitsGoal(r, goal, meal) {
  const breakfast = meal === "breakfast";
  if (goal === "lowcarb") return r.c <= LOW_CARB_MAX;
  if (goal === "protein") return r.p >= (breakfast ? BREAKFAST_PROTEIN_MIN : PROTEIN_MIN);
  if (goal === "lose") {
    const target = mealTarget(meal);
    return r.kcal <= (target ? target * 1.15 : breakfast ? BREAKFAST_LOSE_KCAL_MAX : LOSE_KCAL_MAX);
  }
  return true;
}

/** Вес блюда при случайном выборе: любимое, доедаем остатки, попадает в калории приёма пищи. */
function score(r, meal) {
  let s = 1;
  if (S.liked.includes(r.id)) s += 2;
  s += 4 * leftoverHits(r).length;
  const target = mealTarget(meal);
  if (target) s += 4 * Math.exp(-(((r.kcal - target) / (0.3 * target)) ** 2));
  return s;
}

function candidates(meal, relax, exclude) {
  const p = S.prefs;
  const skipped = UI.skipped[meal] || [];
  return allRecipes().filter((r) =>
    r.meal.includes(meal) &&
    !exclude.has(r.id) &&
    !S.disliked.includes(r.id) &&
    !(r.tags || []).some((t) => p.avoid.includes(t)) &&
    (relax >= 3 || !skipped.includes(r.id)) &&
    (relax >= 2 || fitsGoal(r, p.goal, meal)) &&
    (relax >= 1 || likesCuisine(r)) &&
    (relax >= 1 || r.time <= p.time) &&
    (relax >= 2 || !recentIds(6).includes(r.id)));
}

function pickDish(meal, rand, exclude) {
  for (let relax = 0; relax <= 3; relax++) {
    const list = candidates(meal, relax, exclude);
    if (!list.length) continue;
    const weights = list.map((r) => score(r, meal));
    let roll = rand() * weights.reduce((a, b) => a + b, 0);
    for (let i = 0; i < list.length; i++) { roll -= weights[i]; if (roll <= 0) return list[i]; }
    return list[list.length - 1];
  }
  return null;
}

const freshMeal = (id) => ({ id, portions: S.prefs.portions, have: {}, cooked: false, rated: false, eaten: false });
const otherMealIds = (day, key) => new Set(MEALS.filter((m) => m.key !== key).map((m) => day.meals[m.key]?.id).filter(Boolean));

/** Гарантирует план на сегодня: три приёма пищи, без повторов внутри дня. */
function ensureDay() {
  const date = dayKey();
  let day = S.day && S.day.date === date ? S.day : { date, meals: {} };
  let changed = day !== S.day;
  for (const { key } of MEALS) {
    const m = day.meals[key];
    const broken = !m || !byId(m.id) || (S.disliked.includes(m.id) && !m.cooked);
    if (!broken) continue;
    const dish = pickDish(key, rngFrom(date + key), otherMealIds(day, key));
    day = { ...day, meals: { ...day.meals, [key]: dish ? freshMeal(dish.id) : null } };
    changed = true;
  }
  if (changed) { S = { ...S, day }; save(); }
}

/** План под новые настройки: съеденное и приготовленное остаётся, остальное подберётся заново. */
function replanKeepingDone() {
  const day = S.day;
  if (!day || day.date !== dayKey()) return null;
  const kept = Object.fromEntries(Object.entries(day.meals).filter(([, m]) => m && (m.eaten || m.cooked)));
  return { ...day, meals: kept };
}

function setMeal(key, patch) {
  const day = S.day;
  commit({ ...S, day: { ...day, meals: { ...day.meals, [key]: { ...day.meals[key], ...patch } } } });
}

function putMeal(key, id, extra = {}) {
  // уже съеденное остаётся в дневнике, даже если блюдо в плане заменили
  const day = S.day && S.day.date === dayKey() ? S.day : { date: dayKey(), meals: {} };
  commit({ ...S, ...extra, day: { ...day, meals: { ...day.meals, [key]: freshMeal(id) } } });
}

function rerollMeal(key) {
  const cur = S.day.meals[key]?.id;
  UI.skipped = { ...UI.skipped, [key]: cur ? [...(UI.skipped[key] || []), cur] : UI.skipped[key] || [] };
  const exclude = new Set([...otherMealIds(S.day, key), cur].filter(Boolean));
  const dish = pickDish(key, Math.random, exclude);
  if (dish) putMeal(key, dish.id);
  else toast("Больше вариантов под твои фильтры нет");
}

function neverAgainMeal(key) {
  const cur = S.day.meals[key]?.id;
  if (!cur) return;
  S = { ...S, disliked: [...S.disliked, cur] };
  rerollMeal(key);
  toast("Больше не предложу это блюдо");
}

/** Сумма КБЖУ запланированных блюд на 1 порцию каждое. */
function plannedTotals() {
  const dishes = MEALS.map(({ key }) => S.day?.meals[key] && byId(S.day.meals[key].id)).filter(Boolean);
  return sumMacros(dishes);
}
