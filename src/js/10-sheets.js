// Нижние шторки: всё второстепенное открывается поверх экрана, а не растягивает его.

function sheetFrame(title, body, footer = null) {
  return h("div", { class: `sheet-layer${fx("sheet") ? " opening" : ""}` },
    h("div", { class: "sheet-backdrop", onclick: closeSheet }),
    h("section", { class: "sheet", role: "dialog", "aria-modal": "true", "aria-labelledby": "sheet-title", tabindex: "-1" },
      h("div", { class: "grabber", "aria-hidden": "true" }),
      h("header", { class: "sheet-head" }, h("h2", { id: "sheet-title" }, title), iconButton(ICON.close, "Закрыть", closeSheet, { class: "soft" })),
      h("div", { class: "sheet-body" }, body),
      footer ? h("footer", { class: "sheet-foot" }, footer) : null));
}

function diarySheet() {
  const items = diaryFor();
  const total = sumMacros(items);
  const draft = UI.foodDraft || { name: "", kcal: "", p: "", f: "", c: "" };
  const setField = (k) => (e) => { UI.foodDraft = { ...(UI.foodDraft || draft), [k]: e.target.value }; };
  const submit = (e) => {
    e.preventDefault();
    const { entry, error } = parseCustomFood(UI.foodDraft || draft);
    if (error) { toast(error); return; }
    UI.foodDraft = null;
    commit({ ...S, diary: addDiaryEntry(entry) });
    toast(`${entry.name}: +${entry.kcal} ккал`);
  };
  const numField = (k, ph, label) => h("input", { class: "field", id: `food-${k}`, inputmode: "decimal", placeholder: ph, "aria-label": label, value: draft[k], oninput: setField(k) });
  return sheetFrame("Дневник", [
    items.length ? h("p", { class: "sheet-sub" }, `${total.kcal} ккал · Б ${total.p} · Ж ${total.f} · У ${total.c}`) : null,
    h("div", { class: "group" }, items.length ? items.map((x) => h("div", { class: "row-item" },
      h("span", { class: "row-main" }, h("span", { class: "row-title" }, x.name),
        h("span", { class: "row-sub" }, `${x.meal ? `${mealInfo(x.meal).label} · ` : ""}Б ${x.p} · Ж ${x.f} · У ${x.c}`)),
      h("span", { class: "row-value" }, `${x.kcal} ккал`),
      iconButton(ICON.close, `Убрать ${x.name}`, () => removeFromDiary(x), { class: "soft small" })))
      : h("p", { class: "empty" }, "Пока пусто. Отметь блюдо из плана или добавь перекус.")),
    h("form", { class: "food-form", onsubmit: submit },
      h("span", { class: "group-h" }, h("span", {}, "Добавить перекус")),
      h("input", { class: "field", id: "food-name", placeholder: "Яблоко, кофе с молоком…", "aria-label": "Что съел", value: draft.name, oninput: setField("name") }),
      h("div", { class: "num-row" }, numField("kcal", "ккал", "Калории"), numField("p", "Б", "Белки, г"), numField("f", "Ж", "Жиры, г"), numField("c", "У", "Углеводы, г")),
      h("button", { class: "btn tinted", type: "submit" }, svg(ICON.plus, 18), "Добавить")),
  ]);
}

function removeFromDiary(x) {
  // если блюдо всё ещё стоит в плане, снимаем у него отметку «съедено»
  const key = x.meal && S.day?.meals[x.meal]?.id === x.recipeId ? x.meal : null;
  const day = S.day;
  const meals = key ? { ...day.meals, [key]: { ...day.meals[key], eaten: false } } : day?.meals;
  commit({ ...S, diary: removeDiaryEntry(x.key), day: day ? { ...day, meals } : day });
}

function shoppingSheet() {
  const rows = dayShoppingRows();
  const total = buyCost(rows);
  return sheetFrame("Покупки на сегодня", [
    h("p", { class: "sheet-sub" }, rows.length ? `${rows.length} ${plural(rows.length, "продукт", "продукта", "продуктов")}${total ? ` · ≈ ${fmtRub(total)}` : ""}` : "Всё нужное уже есть дома."),
    rows.length ? h("div", { class: "group" }, rows.map((x) => h("div", { class: "row-item" },
      h("span", { class: "row-main" }, h("span", { class: "row-title" }, x.n),
        x.packs ? h("span", { class: "row-sub" }, `${x.packs} уп. по ${fmtAmount(x.pack, x.u)}`) : null),
      h("span", { class: "row-value" }, fmtAmount(x.toBuy || x.a, x.u))))) : null,
  ], rows.length ? h("button", { class: "btn primary", onclick: () => copyText(dayListText(), "Список скопирован") }, svg(ICON.copy, 18), "Скопировать список") : null);
}

function filtersSheet() {
  const c = UI.cat;
  const set = (patch) => { UI.cat = { ...UI.cat, ...patch, shown: CATALOG_PAGE }; render(); };
  const count = catalogMatches().length;
  return sheetFrame("Фильтры", [
    h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Цель")),
      chipRow("Цель", [["", "Любая"], ["lose", "Похудеть"], ["lowcarb", "Мало углеводов"], ["protein", "Больше белка"]], c.goal, (v) => set({ goal: v }))),
    h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Цена порции")),
      chipRow("Цена порции", [[0, "Любая"], ...PRICE_STEPS.map((p) => [p, `до ${p} ₽`])], c.price, (v) => set({ price: v }))),
    h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Время")),
      segmented(TIMES.map((t) => [t.v, t.v >= 999 ? "любое" : t.l]), c.time, (v) => set({ time: v }), "Время")),
    h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Кухня")),
      h("select", { class: "field", id: "cat-cuisine", "aria-label": "Кухня", onchange: (e) => set({ cuisine: e.target.value }) },
        h("option", { value: "" }, "Все кухни"),
        CUISINES.map((x) => h("option", { value: x.id, selected: c.cuisine === x.id }, cap(x.id))))),
  ], [
    h("button", { class: "btn plain", onclick: () => set({ goal: "", price: 0, time: 999, cuisine: "" }) }, "Сбросить"),
    h("button", { class: "btn primary", onclick: closeSheet }, `Показать ${count}`),
  ]);
}

function bodySheet() {
  const submit = (e) => {
    e.preventDefault();
    const d = bodyDraft();
    const error = bodyError(d);
    if (error) { toast(error); return; }
    UI.bodyDraft = null;
    commit({ ...S, body: normalizeBody(d), day: replanKeepingDone() });
    closeSheet();
    toast("Норма посчитана, план обновлён");
  };
  return sheetFrame("Мои данные", h("form", { class: "sheet-form", onsubmit: submit },
    h("p", { class: "sheet-sub" }, "Нужны, чтобы посчитать норму калорий и подбирать блюда под неё."),
    bodyFields(bodyDraft(), setBodyDraft),
    h("button", { class: "btn primary", type: "submit" }, "Сохранить"),
    S.body ? h("button", { class: "btn plain danger", type: "button", onclick: () => { UI.bodyDraft = null; commit({ ...S, body: null }); closeSheet(); } }, "Удалить мои данные") : null));
}

const PREF_SHEETS = {
  cuisines: ["Кухни", cuisinePicker],
  avoid: ["Ограничения", avoidPicker],
  goal: ["Цель", goalPicker],
  time: ["Время у плиты", timePicker],
  portions: ["Порции", portionsPicker],
};

function prefSheet(field) {
  const [title, picker] = PREF_SHEETS[field];
  // смена цели меняет норму и подбор: несъеденные блюда на сегодня подбираются заново
  const onChange = (next) => commit({ ...S, prefs: next, day: next.goal !== S.prefs.goal ? replanKeepingDone() : S.day });
  return sheetFrame(title, picker(S.prefs, onChange));
}

function renderSheet() {
  const name = UI.sheet;
  if (!name) return null;
  if (name.startsWith("pref:")) return prefSheet(name.slice(5));
  return ({ diary: diarySheet, shopping: shoppingSheet, filters: filtersSheet, body: bodySheet })[name]?.() || null;
}
