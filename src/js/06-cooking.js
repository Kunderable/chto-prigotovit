// Граммовка, списки покупок, «приготовил», «съел».
function scaled(r, portions) {
  const k = portions / (r.base || 2);
  return r.ingredients.map((i) => ({ ...i, a: i.a == null ? null : i.a * k }));
}

function shoppingRows(r, m) {
  return scaled(r, m.portions).filter((i) => !i.pantry).map((i) => {
    const f = S.fridge.find((x) => same(x.n, i.n) && (x.a == null || x.u === i.u));
    const fromFridge = f ? (f.a == null ? i.a : Math.min(f.a, i.a)) : 0;
    const toBuy = i.a == null ? 0 : Math.max(0, i.a - fromFridge);
    const have = !!m.have[i.n] || (f && toBuy === 0);
    const packs = i.pack && toBuy > 0 ? Math.ceil(toBuy / i.pack) : 0;
    const leftover = packs ? packs * i.pack - toBuy : 0;
    return { ...i, f, fromFridge, toBuy, have, packs, leftover };
  });
}

const listLine = (x) => `• ${x.n} — ${fmtAmount(x.toBuy || x.a, x.u)}${x.packs ? ` (${x.packs} уп. по ${fmtAmount(x.pack, x.u)})` : ""}`;

function listText(r, m) {
  const lines = shoppingRows(r, m).filter((x) => !x.have).map(listLine);
  return `Купить для «${r.name}», ${m.portions} порц.:\n${lines.join("\n") || "всё уже есть дома"}`;
}

/** Покупки на весь день: одинаковые продукты из разных блюд складываются. */
function dayShoppingRows() {
  const merged = new Map();
  for (const { key } of MEALS) {
    const m = S.day?.meals[key];
    const r = m && byId(m.id);
    if (!r || m.cooked) continue;
    for (const x of shoppingRows(r, m).filter((row) => !row.have)) {
      const k = `${x.n.toLowerCase()}|${x.u}`;
      const toBuy = (merged.get(k)?.toBuy || 0) + (x.toBuy || x.a || 0);
      merged.set(k, { ...x, toBuy, packs: x.pack ? Math.ceil(toBuy / x.pack) : 0 });
    }
  }
  return [...merged.values()];
}

function dayListText() {
  const lines = dayShoppingRows().map(listLine);
  return `Покупки на ${new Date().toLocaleDateString("ru-RU", { day: "numeric", month: "long" })}:\n${lines.join("\n") || "всё уже есть дома"}`;
}

function cookDone(r, key) {
  const m = S.day.meals[key];
  let fridge = S.fridge.map((x) => ({ ...x }));
  const added = [];
  for (const i of scaled(r, m.portions)) {
    if (i.pantry) continue;
    let need = i.a == null ? 0 : i.a;
    const idx = fridge.findIndex((x) => same(x.n, i.n) && (x.a == null || x.u === i.u));
    if (idx >= 0) {
      const f = fridge[idx];
      if (f.a == null) { fridge = fridge.filter((_, k) => k !== idx); need = 0; }
      else { const take = Math.min(f.a, need); need -= take; fridge = fridge.map((x, k) => (k === idx ? { ...x, a: x.a - take } : x)); }
    }
    if (m.have[i.n]) need = 0;
    if (need > 0 && i.pack) {
      const left = Math.ceil(need / i.pack) * i.pack - need;
      if (left >= (LEFTOVER_MIN[i.u] || 1)) { fridge = [...fridge, { n: i.n, a: left, u: i.u }]; added.push(`${i.n.toLowerCase()} ${fmtAmount(left, i.u)}`); }
    }
  }
  fridge = fridge.filter((x) => x.a == null || x.a >= (LEFTOVER_MIN[x.u] || 1) * 0.5);
  const day = S.day;
  commit({
    ...S, fridge,
    day: { ...day, meals: { ...day.meals, [key]: { ...m, cooked: true } } },
    history: [...S.history, { id: r.id, name: r.name, date: dayKey() }].slice(-60),
  });
  toast(added.length ? `В холодильник: ${added.join(", ")}` : "Отмечено. Остатков нет");
}

function rate(r, key, good) {
  const day = S.day;
  commit({
    ...S,
    liked: good ? [...new Set([...S.liked, r.id])] : S.liked.filter((x) => x !== r.id),
    disliked: good ? S.disliked : [...new Set([...S.disliked, r.id])],
    day: { ...day, meals: { ...day.meals, [key]: { ...day.meals[key], rated: true } } },
  });
  toast(good ? "Запомнил: буду предлагать похожее" : "Понял, больше не предложу");
}

/** «Съел»: добавляет одну порцию блюда в дневник или убирает её. */
function toggleEaten(key) {
  const m = S.day.meals[key];
  const r = m && byId(m.id);
  if (!r) return;
  const entryKey = `meal:${key}:${r.id}`;
  const diary = m.eaten
    ? removeDiaryEntry(entryKey)
    : addDiaryEntry({ key: entryKey, name: r.name, kcal: r.kcal, p: r.p, f: r.f, c: r.c, meal: key, recipeId: r.id });
  const day = S.day;
  commit({ ...S, diary, day: { ...day, meals: { ...day.meals, [key]: { ...m, eaten: !m.eaten } } } });
  if (!m.eaten) toast(`${mealInfo(key).label}: +${r.kcal} ккал`);
}
