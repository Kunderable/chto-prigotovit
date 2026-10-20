// Справочники и пороги.
const CUISINES = [
  { id: "русская", hue: 205 }, { id: "итальянская", hue: 12 }, { id: "грузинская", hue: 330 },
  { id: "узбекская", hue: 45 }, { id: "французская", hue: 230 }, { id: "средиземноморская", hue: 185 },
  { id: "американская", hue: 0 }, { id: "мексиканская", hue: 35 }, { id: "ближневосточная", hue: 25 },
  { id: "индийская", hue: 50 }, { id: "китайская", hue: 355 }, { id: "японская", hue: 340 },
  { id: "корейская", hue: 15 }, { id: "тайская", hue: 95 }, { id: "испанская", hue: 20 },
  { id: "вьетнамская", hue: 160 },
];
const OLD_ASIAN = ["китайская", "японская", "корейская", "тайская", "индийская"];
const AVOID = [
  { id: "meat", label: "Мясо и птица" }, { id: "pork", label: "Свинина" },
  { id: "fish", label: "Рыба и морепродукты" }, { id: "dairy", label: "Молочное" }, { id: "gluten", label: "Глютен" },
];
const TIMES = [{ v: 20, l: "до 20 мин" }, { v: 40, l: "до 40 мин" }, { v: 999, l: "не важно" }];
const GOALS = [
  { v: "normal", l: "Просто вкусно" }, { v: "lose", l: "Похудеть" },
  { v: "protein", l: "Больше белка" }, { v: "lowcarb", l: "Мало углеводов" },
];

/** Приёмы пищи и их доля в дневной норме калорий. */
const MEALS = [
  { key: "breakfast", label: "Завтрак", share: 0.25 },
  { key: "lunch", label: "Обед", share: 0.4 },
  { key: "dinner", label: "Ужин", share: 0.35 },
];

// Пороги «на порцию» для меток и фильтров каталога.
const LOW_CARB_MAX = 20;
const LOSE_KCAL_MAX = 500;
const PROTEIN_MIN = 35;
const BREAKFAST_LOSE_KCAL_MAX = 400;
const BREAKFAST_PROTEIN_MIN = 20;
const GOAL_TEST = {
  lose: (r) => r.kcal <= LOSE_KCAL_MAX,
  protein: (r) => r.p >= PROTEIN_MIN,
  lowcarb: (r) => r.c <= LOW_CARB_MAX,
};

const CATALOG_PAGE = 30;
const UNITS = ["г", "мл", "шт", "зубч.", "ст.л.", "ч.л."];
const MAX_PORTIONS = 8;
const LEFTOVER_MIN = { "г": 10, "мл": 10, "шт": 1, "зубч.": 1 };
const DIARY_KEEP_DAYS = 30;

// Рецепты подставляет build.mjs из data/recipes/*.json
const RECIPES = /*__RECIPES__*/[];
