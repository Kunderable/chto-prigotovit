// Компоненты интерфейса, из которых собраны экраны.

const todayLabel = () => new Date().toLocaleDateString("ru-RU", { weekday: "long", day: "numeric", month: "long" });

/** Крупный заголовок экрана: дата мелко, название крупно. */
function pageHead(title, aside = null) {
  return h("header", { class: "page-head" },
    h("span", { class: "eyebrow" }, todayLabel()),
    h("div", { class: "title-row" }, h("h1", {}, title), aside));
}

function iconButton(icon, label, onClick, extra = {}) {
  return h("button", { class: `icon-btn ${extra.class || ""}`, "aria-label": label, title: label, onclick: onClick, disabled: extra.disabled }, svg(icon, 20));
}

/** Верхняя панель вложенного экрана: «‹ Назад» слева, круглые кнопки справа. */
function navBar(backLabel, onBack, actions = []) {
  return h("div", { class: "navbar" },
    h("button", { class: "back", onclick: onBack }, svg(ICON.back, 22), backLabel),
    h("div", { class: "navbar-actions" }, actions));
}

function tile(r, size = "") {
  return h("span", { class: `tile ${size}`, style: `--h:${hueOf(r.cuisine)}`, "aria-hidden": "true" }, r.emoji);
}

/** Три кольца как в «Фитнесе»: белки, жиры, углеводы относительно нормы. */
function rings(eaten, norm, size = 78) {
  const NS = "http://www.w3.org/2000/svg";
  const stroke = 9, gap = 2.5;
  const el = (tag, attrs) => {
    const node = document.createElementNS(NS, tag);
    Object.entries(attrs).forEach(([k, v]) => node.setAttribute(k, v));
    return node;
  };
  const root = el("svg", { viewBox: `0 0 ${size} ${size}`, width: size, height: size, class: "rings", role: "img",
    "aria-label": `Белки ${eaten.p} из ${norm.p} г, жиры ${eaten.f} из ${norm.f} г, углеводы ${eaten.c} из ${norm.c} г` });
  [["p", "--kbju-p"], ["f", "--kbju-f"], ["c", "--kbju-c"]].forEach(([k, color], i) => {
    const r = size / 2 - stroke / 2 - i * (stroke + gap);
    const len = 2 * Math.PI * r;
    const frac = norm[k] ? Math.min(1, eaten[k] / norm[k]) : 0;
    const base = { cx: size / 2, cy: size / 2, r, fill: "none", "stroke-width": stroke };
    root.append(el("circle", { ...base, stroke: `var(${color})`, opacity: "0.18" }));
    if (frac > 0) {
      root.append(el("circle", { ...base, class: fx("enter") ? "arc grow" : "arc", stroke: `var(${color})`, "stroke-linecap": "round",
        "stroke-dasharray": `${len * frac} ${len}`, style: `--len:${len}`, transform: `rotate(-90 ${size / 2} ${size / 2})` }));
    }
  });
  return root;
}

function progress(value, max) {
  const pct = max ? Math.min(100, (value / max) * 100) : 0;
  return h("div", { class: `progress${max && value > max * 1.05 ? " over" : ""}`, role: "progressbar",
    "aria-valuenow": String(Math.round(value)), "aria-valuemin": "0", "aria-valuemax": String(Math.round(max || 0)) },
    h("span", { class: fx("enter") ? "grow" : "", style: `--to:${pct / 100}` }));
}

/** Калории и БЖУ блюда — четыре цифры в ряд. */
function statGrid(r) {
  const cell = (value, unit, label, color) => h("div", { class: "stat" },
    h("span", { class: "stat-v" }, String(value), h("small", {}, unit)),
    h("span", { class: "stat-l" }, color ? h("span", { class: "dot", style: `background:var(${color})` }) : null, label));
  return h("div", { class: "stats", "aria-label": "На одну порцию" },
    cell(r.kcal, "", "ккал"), cell(r.p, "г", "белки", "--kbju-p"), cell(r.f, "г", "жиры", "--kbju-f"), cell(r.c, "г", "углеводы", "--kbju-c"));
}

function segmented(options, value, onPick, label) {
  return h("div", { class: "seg", role: "tablist", "aria-label": label, style: `--n:${options.length};--i:${Math.max(0, options.findIndex(([v]) => v === value))}` },
    h("span", { class: "seg-thumb", "aria-hidden": "true" }),
    options.map(([v, l]) => h("button", { role: "tab", "aria-selected": String(v === value), onclick: () => onPick(v) }, l)));
}

function chipRow(label, options, current, onPick) {
  return h("div", { class: "chips-scroll", role: "group", "aria-label": label },
    options.map(([v, l]) => h("button", { class: "tog", "aria-pressed": String(current === v), onclick: () => onPick(v) }, l)));
}

/** Строка списка в стиле «Настроек»: название, значение, шеврон. */
function listRow(title, detail, onClick) {
  return h("button", { class: "list-row", onclick: onClick },
    h("span", { class: "list-title" }, title),
    h("span", { class: "list-detail" }, detail),
    svg(ICON.next, 16));
}

function goalLabels(r) {
  return [GOAL_TEST.lose(r) && "до 500 ккал", GOAL_TEST.lowcarb(r) && "мало углеводов", GOAL_TEST.protein(r) && "много белка"].filter(Boolean);
}

/* Редакторы предпочтений: используются в первом запуске и в шторках профиля. */
function cuisinePicker(p, onChange) {
  const all = p.cuisines.length === CUISINES.length;
  return h("div", { class: "pref-group" },
    h("div", { class: "group-h" }, h("span", {}, "Кухни"),
      h("button", { class: "linkish", onclick: () => onChange({ ...p, cuisines: all ? [] : CUISINES.map((c) => c.id) }) }, all ? "Снять все" : "Выбрать все")),
    h("div", { class: "toggles" }, CUISINES.map((c) => h("button", {
      class: "tog", "aria-pressed": String(p.cuisines.includes(c.id)), onclick: () => onChange({ ...p, cuisines: toggleList(p.cuisines, c.id) }),
    }, cap(c.id)))));
}

function avoidPicker(p, onChange) {
  return h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Не ем")),
    h("div", { class: "toggles" }, AVOID.map((a) => h("button", {
      class: "tog no", "aria-pressed": String(p.avoid.includes(a.id)), onclick: () => onChange({ ...p, avoid: toggleList(p.avoid, a.id) }),
    }, a.label))));
}

function goalPicker(p, onChange) {
  return h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Цель")),
    h("div", { class: "choice-list" }, GOALS.map((g) => h("button", {
      class: "choice", "aria-pressed": String(p.goal === g.v), onclick: () => onChange({ ...p, goal: g.v }),
    }, h("span", {}, g.l), svg(ICON.check, 18)))));
}

function timePicker(p, onChange) {
  return h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Время у плиты")),
    segmented(TIMES.map((t) => [t.v, t.l]), p.time, (v) => onChange({ ...p, time: v }), "Время у плиты"));
}

function portionsPicker(p, onChange) {
  return h("div", { class: "pref-group" }, h("div", { class: "group-h" }, h("span", {}, "Готовлю на")),
    segmented([1, 2, 3, 4].map((n) => [n, n === 4 ? "4+" : String(n)]), p.portions, (v) => onChange({ ...p, portions: v }), "Сколько персон"));
}

/** Пол, возраст, рост, вес, активность. Поля ввода пишут в черновик без перерисовки, чтобы не терялся фокус. */
function bodyFields(draft, setDraft) {
  const num = (k, label, unit, ph) => h("label", { class: "field-wrap" },
    h("span", {}, label),
    h("span", { class: "unit-field" },
      h("input", { class: "field", id: `body-${k}`, inputmode: "decimal", placeholder: ph, value: draft[k] ?? "",
        oninput: (e) => setDraft({ [k]: e.target.value }, false) }),
      h("span", { class: "unit" }, unit)));
  return h("div", { class: "body-fields" },
    segmented(SEXES.map((s) => [s.v, s.l]), draft.sex, (v) => setDraft({ sex: v }, true), "Пол"),
    h("div", { class: "form-grid" }, num("age", "Возраст", "лет", "30"), num("height", "Рост", "см", "170"), num("weight", "Вес", "кг", "70")),
    h("label", { class: "field-wrap" }, h("span", {}, "Активность"),
      h("select", { class: "field", id: "body-activity", onchange: (e) => setDraft({ activity: Number(e.target.value) }, false) },
        ACTIVITY.map((a) => h("option", { value: String(a.v), selected: Number(draft.activity) === a.v }, a.l)))));
}
