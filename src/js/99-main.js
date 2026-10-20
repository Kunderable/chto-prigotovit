// Каркас: панель вкладок, отрисовка, уведомления, запуск.

const TABS = [["today", "Сегодня", ICON.pot], ["catalog", "Рецепты", ICON.book], ["fridge", "Холодильник", ICON.fridge], ["profile", "Профиль", ICON.user]];
let tabbarEl = null;

/** Панель вкладок создаётся один раз, чтобы подсветка могла плавно переезжать между вкладками. */
function updateTabbar() {
  if (!tabbarEl) {
    tabbarEl = h("nav", { class: "tabbar", "aria-label": "Разделы" },
      h("span", { class: "tab-thumb", "aria-hidden": "true" }),
      TABS.map(([id, label, icon]) => h("button", { class: "tab", "data-tab": id,
        onclick: () => (UI.tab === id && !UI.open ? window.scrollTo({ top: 0, behavior: "smooth" }) : go({ tab: id, open: null }, "tab")) },
        svg(icon, 24), h("span", {}, label), h("span", { class: "badge", hidden: true }))));
  }
  tabbarEl.style.setProperty("--i", String(TABS.findIndex(([id]) => id === UI.tab)));
  tabbarEl.querySelectorAll(".tab").forEach((b) => {
    const on = b.dataset.tab === UI.tab;
    b.setAttribute("aria-current", on ? "page" : "false");
    if (b.dataset.tab === "fridge") {
      const badge = b.querySelector(".badge");
      badge.hidden = !S.fridge.length;
      badge.textContent = String(S.fridge.length);
    }
  });
  return tabbarEl;
}

function currentView() {
  if (UI.tab === "today" && UI.open?.meal) return renderMealDish(UI.open.meal);
  const views = { fridge: renderFridge, profile: renderProfile, catalog: renderCatalog };
  return (views[UI.tab] || renderToday)();
}

/** Оттенок цветного фона под стеклом — от блюда, которое сейчас на экране. */
const AMBIENT_DEFAULT_HUE = 32;
function ambientHue() {
  const mealKey = UI.open?.meal || (UI.tab === "today" && S.day ? focusMeal().key : null);
  const id = UI.open?.recipe || (mealKey && S.day?.meals[mealKey]?.id);
  const r = id && byId(id);
  return r ? hueOf(r.cuisine) : AMBIENT_DEFAULT_HUE;
}

function render() {
  takeEffects();
  const root = document.getElementById("root");
  const html = document.documentElement;
  if (!S.onboarded) {
    html.style.setProperty("--amb-h", String(AMBIENT_DEFAULT_HUE));
    root.replaceChildren(renderOnboarding());
    return;
  }
  const view = currentView(); // строим до замены: виды могут дополнять план дня
  html.style.setProperty("--amb-h", String(ambientHue()));
  html.classList.toggle("sheet-open", Boolean(UI.sheet));
  root.replaceChildren(h("main", { class: `app${fx("enter") ? " enter" : ""}` }, view), updateTabbar(), renderSheet() || "");
  if (fx("sheet")) root.querySelector(".sheet")?.focus({ preventScroll: true });
}

let toastTimer;
function toast(msg) {
  const slot = document.getElementById("toast-slot");
  slot.replaceChildren(h("div", { class: "toast" }, msg));
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => slot.replaceChildren(), 3000);
}

document.addEventListener("keydown", (e) => { if (e.key === "Escape" && UI.sheet) closeSheet(); });

// завтрак, обед и ужин зависят от часов: обновляемся при возвращении в приложение и раз в 10 минут
const CLOCK_REFRESH_MS = 10 * 60 * 1000;
document.addEventListener("visibilitychange", () => { if (!document.hidden && !UI.sheet) render(); });
setInterval(() => { if (!document.hidden && UI.tab === "today" && !UI.open && !UI.sheet) render(); }, CLOCK_REFRESH_MS);

flash("enter");
render();

