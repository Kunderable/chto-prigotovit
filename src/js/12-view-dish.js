// Экран блюда. Один и тот же для блюда из плана и для рецепта из каталога:
// сверху суть (КБЖУ, цена, порции, главное действие), ниже вкладки «Продукты» и «Приготовление».

function dishTop(r, kicker) {
  return h("header", { class: "dish-top" },
    tile(r, "hero"),
    h("span", { class: "kicker" }, kicker),
    h("h1", { class: "dish-title", id: "dish-name" }, r.name),
    h("p", { class: "dish-facts" }, [cap(r.cuisine), `${r.time} мин`, costLabel(r) && `${costLabel(r)} за порцию`].filter(Boolean).join(" · ")),
    leftoverHits(r).length ? h("span", { class: "badge-soft" }, `доедаем: ${leftoverHits(r).map((x) => x.n.toLowerCase()).join(", ")}`) : null);
}

function portionsRow(value, onChange) {
  return h("div", { class: "portions" },
    h("span", { class: "row-title" }, "Порций"),
    h("div", { class: "stepper" },
      h("button", { "aria-label": "Меньше порций", disabled: value <= 1, onclick: () => onChange(value - 1) }, "−"),
      h("output", { "aria-live": "polite" }, String(value)),
      h("button", { "aria-label": "Больше порций", disabled: value >= MAX_PORTIONS, onclick: () => onChange(value + 1) }, "+")));
}

function dishTabs() {
  return segmented([["ingredients", "Продукты"], ["steps", "Приготовление"]], UI.dishTab, (v) => { UI.dishTab = v; render(); }, "Раздел рецепта");
}

function noteFor(x) {
  if (x.f && x.fromFridge > 0 && x.toBuy > 0) return h("span", { class: "row-sub ok" }, `в холодильнике ${fmtAmount(x.fromFridge, x.u)}, докупить ${fmtAmount(x.toBuy, x.u)}`);
  if (x.f && x.toBuy === 0) return h("span", { class: "row-sub ok" }, "есть в холодильнике");
  if (x.packs && !x.have) return h("span", { class: "row-sub" }, `${x.packs} уп. по ${fmtAmount(x.pack, x.u)}${x.leftover >= (LEFTOVER_MIN[x.u] || 1) ? `, останется ${fmtAmount(x.leftover, x.u)}` : ""}`);
  return null;
}

function pantryNote(r, portions) {
  const pantry = scaled(r, portions).filter((i) => i.pantry);
  return pantry.length ? h("p", { class: "footnote" }, `Из запасов: ${pantry.map((i) => `${i.n.toLowerCase()}${i.a ? ` ${fmtAmount(i.a, i.u)}` : ""}`).join(", ")}`) : null;
}

function stepsList(r) {
  return h("ol", { class: "steps" }, r.steps.map((s) => h("li", {}, h("span", {}, s))));
}

/** Блюдо из плана: отмечаем, что есть дома, копируем список, готовим, отмечаем «съел». */
function renderMealDish(key) {
  const m = S.day?.meals[key];
  const r = m && byId(m.id);
  const back = () => go({ open: null }, "pop");
  if (!r) return [navBar("Сегодня", back), h("p", { class: "empty" }, "Блюдо не найдено.")];
  const rows = shoppingRows(r, m);
  const toBuy = rows.filter((x) => !x.have);
  const buyRub = buyCost(rows);
  const locked = m.eaten || m.cooked;

  const ingredients = [
    h("div", { class: "group" }, rows.map((x) => h("button", {
      class: "row-item check-row", role: "checkbox", "aria-checked": String(x.have),
      onclick: () => setMeal(key, { have: { ...m.have, [x.n]: !m.have[x.n] } }),
    }, h("span", { class: "box" }), h("span", { class: "row-main" }, h("span", { class: "row-title" }, x.n), noteFor(x)),
      h("span", { class: "row-value" }, fmtAmount(x.a, x.u))))),
    pantryNote(r, m.portions),
    m.cooked ? null : h("button", { class: "btn tinted", onclick: () => copyText(listText(r, m), "Список скопирован") },
      svg(ICON.copy, 18), toBuy.length ? `Скопировать список${buyRub ? ` · ≈ ${fmtRub(buyRub)}` : ""}` : "Всё есть дома"),
  ];

  const rating = m.rated ? h("p", { class: "footnote center" }, "Спасибо! Учту при следующих подборах.")
    : h("div", { class: "card rate" },
      h("span", { class: "row-title" }, "Как получилось?"),
      h("div", { class: "rate-btns" },
        h("button", { class: "btn tinted", onclick: () => rate(r, key, true) }, "Вкусно"),
        h("button", { class: "btn plain", onclick: () => rate(r, key, false) }, "Не моё")));

  const steps = [
    stepsList(r),
    m.cooked ? rating : h("button", { class: "btn tinted", onclick: () => cookDone(r, key) }, svg(ICON.check, 18), "Я приготовил"),
  ];

  return [
    navBar("Сегодня", back, [
      iconButton(ICON.dice, "Другое блюдо", () => { flash("enter"); rerollMeal(key); }, { class: "glass", disabled: locked }),
      iconButton(ICON.hide, "Больше не предлагать", () => neverAgainMeal(key), { class: "glass", disabled: locked }),
    ]),
    dishTop(r, mealInfo(key).label),
    statGrid(r),
    h("div", { class: "card controls" },
      portionsRow(m.portions, (n) => setMeal(key, { portions: Math.min(MAX_PORTIONS, Math.max(1, n)) })),
      h("button", { class: `btn ${m.eaten ? "done" : "primary"}${fx(`pop:${key}`) ? " pop" : ""}`, onclick: () => eatToggle(key) },
        svg(ICON.check, 18), m.eaten ? "Съедено" : "Съел порцию")),
    dishTabs(),
    h("div", { class: "tab-panel" }, UI.dishTab === "steps" ? steps : ingredients),
  ];
}

/** Рецепт из каталога: посмотреть и поставить в план. */
function renderPreview(id) {
  const r = byId(id);
  const back = () => go({ open: null }, "pop");
  if (!r) return [navBar("Рецепты", back), h("p", { class: "empty" }, "Рецепт не найден.")];
  const portions = UI.previewPortions || S.prefs.portions;
  const planTo = (key) => {
    ensureDay();
    putMeal(key, r.id);
    toast(`${mealInfo(key).label}: ${r.name}`);
    go({ tab: "today", open: { meal: key }, dishTab: "ingredients", previewPortions: null });
  };
  const rows = scaled(r, portions).filter((i) => !i.pantry);
  const ingredients = [
    h("div", { class: "group" }, rows.map((i) => h("div", { class: "row-item" },
      h("span", { class: "row-title" }, i.n), h("span", { class: "row-value" }, fmtAmount(i.a, i.u))))),
    pantryNote(r, portions),
  ];
  return [
    navBar("Рецепты", back),
    dishTop(r, r.meal.map((k) => mealInfo(k).label).join(" · ")),
    statGrid(r),
    h("div", { class: "card controls" },
      portionsRow(portions, (n) => { UI.previewPortions = Math.min(MAX_PORTIONS, Math.max(1, n)); render(); }),
      h("div", { class: "plan-to" },
        h("span", { class: "row-sub" }, "Готовить сегодня на"),
        h("div", { class: "plan-btns" }, MEALS.map(({ key, label }) => h("button", {
          class: `btn small ${r.meal.includes(key) ? "tinted" : "plain"}`, onclick: () => planTo(key) }, label))))),
    dishTabs(),
    h("div", { class: "tab-panel" }, UI.dishTab === "steps" ? stepsList(r) : ingredients),
  ];
}
