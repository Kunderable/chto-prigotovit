// Норма КБЖУ и дневник съеденного.
const SEXES = [{ v: "f", l: "Женщина" }, { v: "m", l: "Мужчина" }];
const ACTIVITY = [
  { v: 1.2, l: "Почти не двигаюсь" },
  { v: 1.375, l: "Тренировки 1–3 раза в неделю" },
  { v: 1.55, l: "Тренировки 3–5 раз в неделю" },
  { v: 1.725, l: "Тренируюсь почти каждый день" },
];
const BODY_LIMITS = { age: [14, 100, "Возраст"], height: [120, 230, "Рост"], weight: [35, 250, "Вес"] };
const GOAL_KCAL_FACTOR = { normal: 1, lose: 0.83, protein: 1, lowcarb: 0.9 };
const PROTEIN_PER_KG = { normal: 1.2, lose: 1.6, protein: 2, lowcarb: 1.6 };
const FAT_PER_KG = 0.9;
const LOWCARB_DAY_CARBS = 80;
const MIN_DAY_CARBS = 50;
const KCAL_FLOOR = { f: 1200, m: 1500 };

const toNum = (v) => Number(String(v ?? "").replace(",", ".").trim());

/** Проверяет введённые данные; возвращает текст ошибки или null. */
function bodyError(d) {
  for (const [k, [lo, hi, label]] of Object.entries(BODY_LIMITS)) {
    const n = toNum(d[k]);
    if (!Number.isFinite(n) || String(d[k] ?? "").trim() === "") return `Укажи: ${label.toLowerCase()}.`;
    if (n < lo || n > hi) return `${label} должен быть от ${lo} до ${hi}.`;
  }
  return SEXES.some((s) => s.v === d.sex) ? null : "Выбери пол.";
}

function normalizeBody(d) {
  return { sex: d.sex, age: toNum(d.age), height: toNum(d.height), weight: toNum(d.weight), activity: Number(d.activity) || 1.375 };
}

/** Формула Миффлина — Сан-Жеора, поправка на активность и цель. */
function dailyNorm(body = S.body, goal = S.prefs.goal) {
  if (!body) return null;
  const { sex, age, height, weight, activity } = body;
  const bmr = 10 * weight + 6.25 * height - 5 * age + (sex === "m" ? 5 : -161);
  const tdee = bmr * activity;
  const kcal = Math.max(KCAL_FLOOR[sex] || 1200, round10(tdee * (GOAL_KCAL_FACTOR[goal] || 1)));
  const p = Math.round(weight * (PROTEIN_PER_KG[goal] || 1.2));
  let c, f;
  if (goal === "lowcarb") {
    c = LOWCARB_DAY_CARBS;
    f = Math.round((kcal - p * 4 - c * 4) / 9);
  } else {
    f = Math.round(weight * FAT_PER_KG);
    c = Math.round((kcal - p * 4 - f * 9) / 4);
    if (c < MIN_DAY_CARBS) { c = MIN_DAY_CARBS; f = Math.round((kcal - p * 4 - c * 4) / 9); }
  }
  return { kcal, p, f, c, bmr: Math.round(bmr), tdee: round10(tdee) };
}

function mealTarget(key) {
  const norm = dailyNorm();
  return norm ? Math.round(norm.kcal * mealInfo(key).share) : null;
}

// дневник
const diaryFor = (date = dayKey()) => S.diary[date] || [];
const sumMacros = (items) => items.reduce((a, x) => ({ kcal: a.kcal + x.kcal, p: a.p + x.p, f: a.f + x.f, c: a.c + x.c }), { kcal: 0, p: 0, f: 0, c: 0 });

function diaryWith(entries, date = dayKey()) {
  return { ...S.diary, [date]: entries };
}
function addDiaryEntry(entry) {
  return diaryWith([...diaryFor().filter((x) => x.key !== entry.key), entry]);
}
function removeDiaryEntry(key) {
  return diaryWith(diaryFor().filter((x) => x.key !== key));
}

/** Разбирает форму «добавить вручную»; возвращает { entry } или { error }. */
function parseCustomFood(d) {
  const name = String(d.name || "").trim().slice(0, 60);
  if (!name) return { error: "Напиши, что съел." };
  const nums = ["kcal", "p", "f", "c"].map((k) => (String(d[k] ?? "").trim() === "" ? 0 : toNum(d[k])));
  if (nums.some((n) => !Number.isFinite(n) || n < 0 || n > 5000)) return { error: "КБЖУ — числа от 0 до 5000." };
  const [k, p, f, c] = nums;
  const kcal = k || Math.round(p * 4 + f * 9 + c * 4);
  if (!kcal) return { error: "Укажи калории или БЖУ." };
  return { entry: { key: `custom-${Date.now().toString(36)}`, name, kcal: Math.round(kcal), p: Math.round(p), f: Math.round(f), c: Math.round(c) } };
}
