// Холодильник: остатки после готовки и то, что добавил сам.

function renderFridge() {
  const draft = UI.fridgeDraft || { n: "", a: "", u: "г" };
  const setDraft = (patch) => { UI.fridgeDraft = { ...(UI.fridgeDraft || draft), ...patch }; };
  const add = (e) => {
    e.preventDefault();
    const d = UI.fridgeDraft || draft;
    if (!d.n.trim()) { toast("Напиши название продукта"); return; }
    const a = toNum(d.a);
    const item = { n: d.n.trim().slice(0, 60), a: a > 0 ? a : null, u: a > 0 ? d.u : "" };
    UI.fridgeDraft = null;
    commit({ ...S, fridge: [...S.fridge.filter((f) => !same(f.n, item.n)), item] });
  };
  return [
    pageHead("Холодильник", h("span", { class: "eyebrow" }, S.fridge.length ? `${S.fridge.length} поз.` : "")),
    S.fridge.length
      ? h("div", { class: "group" }, S.fridge.map((f, i) => h("div", { class: "row-item" },
        h("span", { class: "row-title" }, f.n),
        h("span", { class: "row-value" }, f.a == null ? "есть" : fmtAmount(f.a, f.u)),
        iconButton(ICON.close, `Убрать ${f.n}`, () => commit({ ...S, fridge: S.fridge.filter((_, k) => k !== i) }), { class: "soft small" }))))
      : h("div", { class: "card empty-state" },
        h("span", { class: "empty-icon" }, svg(ICON.fridge, 28)),
        h("span", { class: "row-title" }, "Пока пусто"),
        h("span", { class: "row-sub" }, "Когда приготовишь блюдо, остатки упаковок появятся здесь сами. Блюда, где их можно доесть, будут попадаться чаще.")),
    h("form", { class: "add-row", onsubmit: add },
      h("input", { class: "field", id: "f-name", placeholder: "Добавить продукт", value: draft.n, "aria-label": "Продукт", oninput: (e) => setDraft({ n: e.target.value }) }),
      h("input", { class: "field", id: "f-amt", inputmode: "decimal", placeholder: "Кол-во", value: draft.a, "aria-label": "Количество", oninput: (e) => setDraft({ a: e.target.value }) }),
      h("select", { class: "field", id: "f-unit", "aria-label": "Единица", onchange: (e) => setDraft({ u: e.target.value }) },
        UNITS.map((u) => h("option", { value: u, selected: u === draft.u }, u))),
      h("button", { class: "icon-btn primary", type: "submit", "aria-label": "Добавить" }, svg(ICON.plus, 20))),
  ];
}
