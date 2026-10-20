// Каталог: поиск, приём пищи на виду, остальные фильтры — в шторке.

function catalogMatches() {
  const c = UI.cat;
  const q = c.q.trim().toLowerCase();
  return allRecipes().filter((r) =>
    !(r.tags || []).some((t) => S.prefs.avoid.includes(t)) &&
    (!c.goal || GOAL_TEST[c.goal](r)) &&
    (!c.meal || r.meal.includes(c.meal)) &&
    (!c.price || (portionCost(r) || Infinity) <= c.price) &&
    (!c.cuisine || same(r.cuisine, c.cuisine)) &&
    r.time <= c.time &&
    (!q || r.name.toLowerCase().includes(q) || r.ingredients.some((i) => i.n.toLowerCase().includes(q))));
}

const activeFilters = () => [UI.cat.goal, UI.cat.price, UI.cat.cuisine, UI.cat.time < 999].filter(Boolean).length;

function recipeRow(r) {
  const goals = goalLabels(r);
  return h("button", { class: "row-item recipe-row", onclick: () => go({ open: { recipe: r.id }, dishTab: "ingredients", previewPortions: null }) },
    tile(r, "md"),
    h("span", { class: "row-main" },
      h("span", { class: "row-title" }, r.name),
      h("span", { class: "row-sub" }, [`${r.kcal} ккал`, `${r.time} мин`, costLabel(r)].filter(Boolean).join(" · ")),
      goals.length ? h("span", { class: "tags" }, goals.map((g) => h("span", {}, g))) : null),
    svg(ICON.next, 16));
}

function fillCatalogList(box, countEl) {
  const all = catalogMatches();
  countEl.textContent = `${all.length} ${plural(all.length, "рецепт", "рецепта", "рецептов")}`;
  const shown = all.slice(0, UI.cat.shown);
  const more = all.length > shown.length
    ? [h("button", { class: "btn plain", onclick: () => { UI.cat = { ...UI.cat, shown: UI.cat.shown + CATALOG_PAGE }; fillCatalogList(box, countEl); } },
      `Показать ещё ${Math.min(CATALOG_PAGE, all.length - shown.length)}`)]
    : [];
  box.replaceChildren(
    shown.length ? h("div", { class: "group" }, shown.map(recipeRow)) : h("p", { class: "empty" }, "Ничего не нашлось. Попробуй убрать фильтры."),
    ...more);
}

function renderCatalog() {
  if (UI.open?.recipe) return renderPreview(UI.open.recipe);
  const c = UI.cat;
  const countEl = h("span", { class: "eyebrow" });
  const listBox = h("div", { class: "stack" });
  fillCatalogList(listBox, countEl);
  const n = activeFilters();
  return [
    pageHead("Рецепты", countEl),
    h("div", { class: "search" }, svg(ICON.search, 18),
      h("input", { class: "field", id: "cat-q", type: "search", placeholder: "Блюдо или продукт", value: c.q, "aria-label": "Поиск рецептов",
        oninput: (e) => { UI.cat = { ...UI.cat, q: e.target.value, shown: CATALOG_PAGE }; fillCatalogList(listBox, countEl); } })),
    h("div", { class: "filter-bar" },
      chipRow("Приём пищи", [["", "Всё"], ["breakfast", "Завтраки"], ["lunch", "Обеды"], ["dinner", "Ужины"]], c.meal,
        (v) => { UI.cat = { ...UI.cat, meal: v, shown: CATALOG_PAGE }; render(); }),
      h("button", { class: `tog filter-btn${n ? " active" : ""}`, onclick: () => openSheet("filters"), "aria-label": `Фильтры${n ? `, выбрано ${n}` : ""}` },
        svg(ICON.sliders, 16), n ? String(n) : null)),
    listBox,
  ];
}
