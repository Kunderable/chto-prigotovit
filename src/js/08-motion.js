// Навигация и движение: переходы между экранами и одноразовые эффекты.
// Экран перерисовывается целиком при любом изменении, поэтому анимации появления
// включаются флагами только для того кадра, где они уместны, а не на каждый клик.

const reduceMotion = () => Boolean(window.matchMedia?.("(prefers-reduced-motion: reduce)").matches);

let fxQueued = new Set();
let fxFrame = new Set();
/** Запланировать эффект на следующую отрисовку: "enter", "sheet", "pop:lunch" и т. п. */
const flash = (name) => fxQueued.add(name);
/** Включён ли эффект в текущей отрисовке. */
const fx = (name) => fxFrame.has(name);
function takeEffects() { fxFrame = fxQueued; fxQueued = new Set(); }

/** Переход между экранами. kind: "push" — вглубь, "pop" — назад, "tab" — между вкладками. */
function go(patch, kind = "push") {
  const apply = () => {
    UI = { ...UI, ...patch };
    flash("enter");
    render();
    window.scrollTo(0, 0);
  };
  if (!document.startViewTransition || reduceMotion()) { apply(); return; }
  document.documentElement.dataset.nav = kind;
  document.startViewTransition(apply);
}

const SHEET_CLOSE_MS = 260;

function openSheet(name) {
  UI = { ...UI, sheet: name };
  flash("sheet");
  render();
}

function closeSheet() {
  const el = document.querySelector(".sheet-layer");
  const finish = () => { UI = { ...UI, sheet: null }; render(); };
  if (!el || reduceMotion()) { finish(); return; }
  el.classList.add("closing");
  setTimeout(finish, SHEET_CLOSE_MS);
}
