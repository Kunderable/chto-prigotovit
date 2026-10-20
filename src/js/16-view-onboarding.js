// Первый запуск: три коротких шага вместо одной длинной анкеты.

const ONB_STEPS = [
  { title: "Что ты любишь?", lead: "Выбери кухни — блюда будут из них." },
  { title: "Как ты ешь?", lead: "Цель, ограничения и сколько времени готов готовить." },
  { title: "Твоя норма", lead: "Вес, рост и возраст нужны для подсчёта КБЖУ. Можно пропустить." },
];

function finishOnboarding(withBody) {
  const draft = UI.draft || S.prefs;
  const body = bodyDraft();
  if (withBody) {
    const error = bodyError(body);
    if (error) { toast(error); return; }
  }
  S = { ...S, prefs: draft, onboarded: true, day: null, body: withBody ? normalizeBody(body) : S.body };
  save();
  go({ draft: null, bodyDraft: null, onbStep: 0, tab: "today", open: null }, "push");
}

function renderOnboarding() {
  const step = UI.onbStep || 0;
  const draft = UI.draft || S.prefs;
  const setDraft = (next) => { UI.draft = next; render(); };
  const toStep = (n, kind) => go({ onbStep: n, draft }, kind);
  const content = [
    () => cuisinePicker(draft, setDraft),
    () => [goalPicker(draft, setDraft), avoidPicker(draft, setDraft), timePicker(draft, setDraft), portionsPicker(draft, setDraft)],
    () => bodyFields(bodyDraft(), setBodyDraft),
  ][step]();
  const last = step === ONB_STEPS.length - 1;
  return h("main", { class: "app onboarding" },
    h("div", { class: "onb-top" },
      step ? h("button", { class: "back", onclick: () => toStep(step - 1, "pop") }, svg(ICON.back, 22), "Назад") : h("span", {}),
      h("div", { class: "dots", "aria-label": `Шаг ${step + 1} из ${ONB_STEPS.length}` },
        ONB_STEPS.map((_, i) => h("span", { class: i === step ? "on" : i < step ? "done" : "" }))),
      last ? h("button", { class: "linkish", onclick: () => finishOnboarding(false) }, "Пропустить") : h("span", {})),
    h("header", { class: "onb-head" }, h("h1", {}, ONB_STEPS[step].title), h("p", { class: "lead" }, ONB_STEPS[step].lead)),
    h("section", { class: "card onb-card" }, content),
    h("div", { class: "onb-foot" },
      last
        ? h("button", { class: "btn primary", onclick: () => finishOnboarding(true) }, "Готово")
        : h("button", { class: "btn primary", disabled: !draft.cuisines.length, onclick: () => toStep(step + 1, "push") },
          draft.cuisines.length ? "Далее" : "Выбери хотя бы одну кухню")));
}
