// Состояние приложения: сохраняемое (S) и экранное (UI).
const KEY = "chto-prigotovit.v1";
const DEFAULT = {
  prefs: { cuisines: ["русская", "итальянская", "грузинская", "японская"], avoid: [], time: 40, goal: "normal", portions: 2 },
  body: null, // { sex: "m"|"f", age, height, weight, activity }
  onboarded: false, day: null, diary: {},
  history: [], disliked: [], liked: [], fridge: [],
};

function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return DEFAULT;
    const { today, aiRecipes, ...p } = JSON.parse(raw); // «today» и «aiRecipes» — поля прошлых версий
    const prefs = { ...DEFAULT.prefs, ...(p.prefs || {}) };
    const cuisines = [...new Set(prefs.cuisines.flatMap((c) => (c === "азиатская" ? OLD_ASIAN : [c])))];
    return { ...DEFAULT, ...p, prefs: { ...prefs, cuisines }, diary: p.diary || {} };
  } catch (e) { return DEFAULT; }
}

function pruneDiary(diary) {
  const keep = Object.keys(diary).sort().slice(-DIARY_KEEP_DAYS);
  return Object.fromEntries(keep.map((d) => [d, diary[d]]));
}

function save() {
  try { localStorage.setItem(KEY, JSON.stringify({ ...S, diary: pruneDiary(S.diary) })); }
  catch (e) { /* хранилище недоступно: работаем в памяти */ }
}

let S = load();
let UI = {
  tab: "today", open: null, sheet: null, dishTab: "ingredients", onbStep: 0,
  skipped: {}, ctl: null, confirmReset: false, previewPortions: null,
  draft: null, bodyDraft: null, foodDraft: null, fridgeDraft: null,
  cat: { q: "", goal: "", meal: "", price: 0, cuisine: "", time: 999, shown: CATALOG_PAGE },
};

function commit(next) { S = next; save(); render(); }
