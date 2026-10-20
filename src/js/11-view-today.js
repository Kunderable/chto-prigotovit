// «Сегодня»: крупно то, что есть сейчас; остальное — одной строкой.

// До 11:00 — завтрак, до 16:00 — обед, дальше — ужин.
const MEAL_UNTIL_HOUR = { breakfast: 11, lunch: 16 };
const MEAL_NOW = { breakfast: "Сейчас завтрак", lunch: "Сейчас обед", dinner: "Сейчас ужин" };
const MEAL_NEXT = { breakfast: "Дальше завтрак", lunch: "Дальше обед", dinner: "Дальше ужин" };

const openMeal = (key) => go({ open: { meal: key }, dishTab: "ingredients" });

function mealByClock(now = new Date()) {
  const hour = now.getHours();
  if (hour < MEAL_UNTIL_HOUR.breakfast) return "breakfast";
  return hour < MEAL_UNTIL_HOUR.lunch ? "lunch" : "dinner";
}

/** Какой приём пищи показать крупно: текущий по часам, а если он уже съеден — следующий несъеденный. */
function focusMeal() {
  const now = mealByClock();
  const order = MEALS.map((m) => m.key);
  const next = order.slice(order.indexOf(now)).find((k) => S.day?.meals[k] && !S.day.meals[k].eaten);
  return { key: next || now, moved: Boolean(next && next !== now) };
}

function eatToggle(key) {
  flash(`pop:${key}`);
  toggleEaten(key);
}

function summaryCard() {
  const norm = dailyNorm();
  const eaten = sumMacros(diaryFor());
  if (!norm) {
    return h("button", { class: "card cta", onclick: () => openSheet("body") },
      h("span", { class: "cta-text" },
        h("span", { class: "cta-title" }, "Посчитать норму КБЖУ"),
        h("span", { class: "row-sub" }, eaten.kcal ? `Сегодня съедено ${eaten.kcal} ккал` : "Вес, рост и возраст — меньше минуты")),
      svg(ICON.next, 18));
  }
  const left = norm.kcal - eaten.kcal;
  return h("section", { class: "card summary", "aria-label": "КБЖУ за сегодня" },
    rings(eaten, norm),
    h("div", { class: "summary-body" },
      h("div", { class: "summary-top" },
        h("span", { class: "summary-kcal" }, h("b", {}, String(eaten.kcal)), ` из ${norm.kcal} ккал`),
        h("span", { class: `summary-left${left < 0 ? " over" : ""}` }, left >= 0 ? `ещё ${left}` : `+${-left}`)),
      progress(eaten.kcal, norm.kcal),
      h("div", { class: "summary-macros" },
        [["Б", "p", "--kbju-p"], ["Ж", "f", "--kbju-f"], ["У", "c", "--kbju-c"]].map(([l, k, c]) =>
          h("span", {}, h("span", { class: "dot", style: `background:var(${c})` }), h("b", {}, String(eaten[k])), ` / ${norm[k]} ${l}`)))));
}

function heroCard(key, moved) {
  const m = S.day?.meals[key];
  const r = m && byId(m.id);
  const label = moved ? MEAL_NEXT[key] : MEAL_NOW[key];
  if (!r) {
    return h("article", { class: "card hero" },
      h("span", { class: "kicker" }, label),
      h("p", { class: "empty" }, "Под твои фильтры ничего не нашлось."),
      h("button", { class: "btn tinted", onclick: () => rerollMeal(key) }, "Подобрать ещё раз"));
  }
  const target = mealTarget(key);
  const cost = costLabel(r);
  const facts = [`${r.kcal} ккал`, `${r.time} мин`, cost].filter(Boolean).join(" · ");
  return h("article", { class: `card hero${m.eaten ? " eaten" : ""}`, style: `--h:${hueOf(r.cuisine)}`, "aria-label": `${label}: ${r.name}` },
    h("div", { class: "hero-top" },
      h("span", { class: "kicker" }, label),
      target ? h("span", { class: "row-sub" }, `цель ≈ ${target} ккал`) : null),
    h("button", { class: "hero-main", onclick: () => openMeal(key) },
      tile(r, "xl"),
      h("span", { class: "hero-text" },
        h("span", { class: "hero-name" }, r.name),
        h("span", { class: "hero-facts" }, facts),
        leftoverHits(r).length ? h("span", { class: "badge-soft" }, "доедаем остатки") : null)),
    h("div", { class: "hero-actions" },
      h("button", { class: "btn primary", onclick: () => openMeal(key) }, "Готовить"),
      iconButton(ICON.dice, "Другое блюдо", () => rerollMeal(key), { class: "glass", disabled: m.eaten || m.cooked }),
      iconButton(ICON.check, m.eaten ? "Убрать из съеденного" : "Съел", () => eatToggle(key),
        { class: `glass${m.eaten ? " done" : ""}${fx(`pop:${key}`) ? " pop" : ""}` })));
}

function mealRow(key) {
  const info = mealInfo(key);
  const m = S.day?.meals[key];
  const r = m && byId(m.id);
  if (!r) return h("div", { class: "row-item" }, h("span", { class: "row-title" }, info.label), h("span", { class: "row-sub" }, "нет блюда"));
  return h("div", { class: `row-item meal-row${m.eaten ? " eaten" : ""}` },
    h("button", { class: "meal-open", onclick: () => openMeal(key) },
      tile(r, "sm"),
      h("span", { class: "row-main" },
        h("span", { class: "row-eyebrow" }, info.label),
        h("span", { class: "row-title" }, r.name)),
      h("span", { class: "row-value" }, `${r.kcal} ккал`)),
    h("button", { class: `check${m.eaten ? " on" : ""}${fx(`pop:${key}`) ? " pop" : ""}`, "aria-pressed": String(m.eaten),
      "aria-label": m.eaten ? `${info.label}: убрать из съеденного` : `${info.label}: съел`, onclick: () => eatToggle(key) }, svg(ICON.check, 16)));
}

function renderToday() {
  ensureDay();
  const { key, moved } = focusMeal();
  const others = MEALS.map((m) => m.key).filter((k) => k !== key);
  const rows = dayShoppingRows();
  const diaryCount = diaryFor().length;
  return [
    pageHead("Сегодня"),
    summaryCard(),
    heroCard(key, moved),
    h("div", { class: "group" }, others.map(mealRow)),
    h("div", { class: "quick" },
      h("button", { class: "quick-btn", onclick: () => openSheet("shopping") },
        svg(ICON.cart, 20), h("span", {}, h("b", {}, "Покупки"), h("small", {}, rows.length ? `${rows.length} ${plural(rows.length, "продукт", "продукта", "продуктов")}` : "всё есть"))),
      h("button", { class: "quick-btn", onclick: () => openSheet("diary") },
        svg(ICON.journal, 20), h("span", {}, h("b", {}, "Дневник"), h("small", {}, diaryCount ? `${diaryCount} ${plural(diaryCount, "запись", "записи", "записей")}` : "пусто")))),
  ];
}
