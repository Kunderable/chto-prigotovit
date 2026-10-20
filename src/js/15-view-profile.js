// Профиль: норма КБЖУ и предпочтения в виде списка настроек; правка — в шторках.

const emptyBody = () => ({ sex: "f", age: "", height: "", weight: "", activity: 1.375 });
const bodyDraft = () => UI.bodyDraft || (S.body ? { ...S.body } : emptyBody());

function setBodyDraft(patch, rerender) {
  UI.bodyDraft = { ...bodyDraft(), ...patch };
  if (rerender) render();
}

const GOAL_NOTE = {
  normal: "Поддержание веса",
  lose: "Похудение: минус 17% калорий",
  protein: "Больше белка: 2 г на кг веса",
  lowcarb: `Мало углеводов: до ${LOWCARB_DAY_CARBS} г в день`,
};

function normCard() {
  const norm = dailyNorm();
  if (!norm) {
    return h("button", { class: "card cta", onclick: () => openSheet("body") },
      h("span", { class: "cta-text" }, h("span", { class: "cta-title" }, "Посчитать норму КБЖУ"),
        h("span", { class: "row-sub" }, "Блюда будут подбираться под неё, а «Сегодня» покажет прогресс")),
      svg(ICON.next, 18));
  }
  const b = S.body;
  return h("section", { class: "card norm" },
    h("div", { class: "norm-head" },
      h("span", { class: "kicker" }, "Норма в день"),
      h("button", { class: "linkish", onclick: () => openSheet("body") }, "Изменить")),
    h("div", { class: "norm-kcal" }, h("b", {}, String(norm.kcal)), " ккал"),
    h("div", { class: "stats compact" },
      [["белки", norm.p, "--kbju-p"], ["жиры", norm.f, "--kbju-f"], ["углеводы", norm.c, "--kbju-c"]].map(([l, v, c]) =>
        h("div", { class: "stat" }, h("span", { class: "stat-v" }, String(v), h("small", {}, "г")),
          h("span", { class: "stat-l" }, h("span", { class: "dot", style: `background:var(${c})` }), l)))),
    h("p", { class: "footnote" }, `${GOAL_NOTE[S.prefs.goal]}. ${b.sex === "m" ? "Мужчина" : "Женщина"}, ${b.age} лет, ${b.height} см, ${b.weight} кг.`));
}

function renderProfile() {
  const p = S.prefs;
  const hist = [...S.history].reverse().slice(0, 5);
  const avoidText = p.avoid.length ? AVOID.filter((a) => p.avoid.includes(a.id)).map((a) => a.label.toLowerCase()).join(", ") : "нет";
  return [
    pageHead("Профиль"),
    normCard(),
    h("section", { class: "stack" },
      h("h2", { class: "group-title" }, "Предпочтения"),
      h("div", { class: "group" },
        listRow("Цель", (GOALS.find((g) => g.v === p.goal) || GOALS[0]).l, () => openSheet("pref:goal")),
        listRow("Кухни", p.cuisines.length === CUISINES.length ? "все" : `${p.cuisines.length} из ${CUISINES.length}`, () => openSheet("pref:cuisines")),
        listRow("Не ем", avoidText, () => openSheet("pref:avoid")),
        listRow("Время у плиты", (TIMES.find((t) => t.v === p.time) || TIMES[1]).l, () => openSheet("pref:time")),
        listRow("Готовлю на", `${p.portions} ${plural(p.portions, "персону", "персоны", "персон")}`, () => openSheet("pref:portions")))),
    hist.length ? h("section", { class: "stack" },
      h("h2", { class: "group-title" }, "Недавно готовил"),
      h("div", { class: "group" }, hist.map((x) => h("div", { class: "row-item" },
        h("span", { class: "row-title" }, x.name), h("span", { class: "row-value" }, x.date.split("-").reverse().slice(0, 2).join(".")))))) : null,
    S.disliked.length ? h("div", { class: "group" },
      h("button", { class: "list-row", onclick: () => { commit({ ...S, disliked: [] }); toast("Скрытые блюда вернулись в подборку"); } },
        h("span", { class: "list-title" }, "Вернуть скрытые блюда"), h("span", { class: "list-detail" }, String(S.disliked.length)))) : null,
    h("div", { class: "group" },
      h("button", { class: "list-row danger", onclick: resetAll }, h("span", { class: "list-title" }, UI.confirmReset ? "Нажми ещё раз, чтобы стереть всё" : "Сбросить все данные"))),
    h("p", { class: "footnote center" }, "Всё хранится только на этом устройстве."),
  ];
}

/** Сброс в два нажатия: первое просит подтвердить, второе стирает. */
function resetAll() {
  if (!UI.confirmReset) { UI.confirmReset = true; render(); setTimeout(() => { UI.confirmReset = false; render(); }, 4000); return; }
  UI = { ...UI, tab: "today", open: null, skipped: {}, confirmReset: false, onbStep: 0 };
  commit({ ...DEFAULT });
}
