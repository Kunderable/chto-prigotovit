// Общие утилиты: DOM, иконки, форматирование.
const same = (a, b) => String(a).trim().toLowerCase() === String(b).trim().toLowerCase();
const dayKey = (d = new Date()) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const allRecipes = () => RECIPES;
const byId = (id) => allRecipes().find((r) => r.id === id);
const hueOf = (c) => (CUISINES.find((x) => same(x.id, c)) || { hue: 140 }).hue;
const mealInfo = (key) => MEALS.find((m) => m.key === key);
const cap = (s) => s[0].toUpperCase() + s.slice(1);
const toggleList = (list, v) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v]);
const round10 = (x) => Math.round(x / 10) * 10;

function plural(n, one, few, many) {
  const a = Math.abs(n) % 100, b = a % 10;
  if (a > 10 && a < 20) return many;
  if (b === 1) return one;
  return b >= 2 && b <= 4 ? few : many;
}

function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith("on")) el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === "class") el.className = v;
    else if (v === true) el.setAttribute(k, "");
    else el.setAttribute(k, v);
  }
  kids.flat(Infinity).forEach((c) => { if (c != null && c !== false) el.append(c instanceof Node ? c : String(c)); });
  return el;
}

function svg(path, size = 22) {
  const s = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  s.setAttribute("viewBox", "0 0 24 24"); s.setAttribute("width", size); s.setAttribute("height", size);
  s.setAttribute("fill", "none"); s.setAttribute("stroke", "currentColor"); s.setAttribute("stroke-width", "1.8");
  s.setAttribute("stroke-linecap", "round"); s.setAttribute("stroke-linejoin", "round"); s.setAttribute("aria-hidden", "true");
  s.innerHTML = path; // статические иконки из этого файла
  return s;
}
const ICON = {
  pot: '<path d="M4 10h16v6a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4v-6Z"/><path d="M2 10h20M9 6c0-1 1-2 3-2s3 1 3 2"/>',
  fridge: '<rect x="5" y="2.5" width="14" height="19" rx="2.5"/><path d="M5 10h14M9 6v1.5M9 13v3"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6"/>',
  dice: '<rect x="3.5" y="3.5" width="17" height="17" rx="4"/><circle cx="9" cy="9" r="1" fill="currentColor"/><circle cx="15" cy="15" r="1" fill="currentColor"/><circle cx="15" cy="9" r="1" fill="currentColor"/><circle cx="9" cy="15" r="1" fill="currentColor"/>',
  no: '<circle cx="12" cy="12" r="9"/><path d="m5.6 5.6 12.8 12.8"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>',
  book: '<path d="M4 4.5A1.5 1.5 0 0 1 5.5 3H19v15H5.5A1.5 1.5 0 0 0 4 19.5v-15Z"/><path d="M4 19.5A1.5 1.5 0 0 0 5.5 21H19v-3M8 7h7M8 10.5h5"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  back: '<path d="M15 5 8 12l7 7"/>',
  next: '<path d="m9 5 7 7-7 7"/>',
  hide: '<path d="M3 3l18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.4 5.2A9.7 9.7 0 0 1 12 5c5 0 8.5 4.5 9.5 7a13 13 0 0 1-2.6 3.6M6.3 6.3A13 13 0 0 0 2.5 12c1 2.5 4.5 7 9.5 7 1.6 0 3-.4 4.3-1"/>',
  sliders: '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
  cart: '<path d="M3 4h2l2.2 10.2a2 2 0 0 0 2 1.6h7.6a2 2 0 0 0 2-1.5L21 8H6.2"/><circle cx="10" cy="20" r="1.3"/><circle cx="17" cy="20" r="1.3"/>',
  journal: '<rect x="5" y="3" width="14" height="18" rx="3"/><path d="M9 8h6M9 12h6M9 16h3"/>',
  close: '<path d="M6 6l12 12M18 6 6 18"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
};

function fmtAmount(a, u) {
  if (a == null) return "по вкусу";
  if (u === "г" || u === "мл") {
    const r = a < 20 ? Math.max(1, Math.round(a)) : Math.round(a / 5) * 5;
    return `${r} ${u}`;
  }
  const r = Math.max(0.5, Math.round(a * 2) / 2);
  const whole = Math.floor(r);
  const s = r % 1 ? (whole ? `${whole}½` : "½") : String(r);
  return u ? `${s} ${u}` : s;
}

function rngFrom(str) {
  let x = 0;
  for (const ch of str) x = (Math.imul(x ^ ch.charCodeAt(0), 2654435761) >>> 0);
  return () => {
    x = (x + 0x6D2B79F5) >>> 0;
    let t = x;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

async function copyText(text, okMsg) {
  try { await navigator.clipboard.writeText(text); toast(okMsg); }
  catch (e) { toast("Не получилось скопировать — список виден на экране, его можно выделить"); }
}
