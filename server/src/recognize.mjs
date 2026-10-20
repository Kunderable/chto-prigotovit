const UNITS = ["г", "мл", "шт"];

const INSTRUCTIONS = (products) => `Ты смотришь на фото открытого холодильника или полки с продуктами.
Перечисли продукты, которые видно на фото. Не придумывай то, чего не видно.
Называй продукты строго так, как они записаны в списке ниже. Если продукта в списке нет — назови его коротко, по-русски, в единственном числе.
Количество оцени примерно: граммы ("г"), миллилитры ("мл") или штуки ("шт"). Если оценить нельзя — amount и unit равны null.
Ответь только JSON без пояснений: {"items":[{"name":"Молоко","amount":900,"unit":"мл"}]}

Список продуктов:
${products.join(", ")}`;

/** Тело запроса к модели в формате OpenAI Chat Completions — его понимают и Yandex AI Studio, и OpenRouter. */
export function buildRequest({ model, imageBase64, products }) {
  return {
    model,
    temperature: 0,
    messages: [
      { role: "system", content: INSTRUCTIONS(products) },
      {
        role: "user",
        content: [
          { type: "text", text: "Что лежит на фото?" },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
        ],
      },
    ],
  };
}

/** Модели иногда оборачивают JSON в ```json … ``` или добавляют фразу перед ним. */
export function parseModelReply(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end <= start) throw new Error("Ответ модели не похож на JSON");
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    throw new Error("Ответ модели не похож на JSON");
  }
}

const key = (name) => name.trim().toLowerCase().replaceAll("ё", "е");

/** Названия — к виду из списка продуктов, единицы — только известные, повторы и пустые строки — прочь. */
export function normalizeItems(items, products) {
  const byKey = new Map(products.map((name) => [key(name), name]));
  const seen = new Set();
  const result = [];
  for (const item of Array.isArray(items) ? items : []) {
    if (typeof item?.name !== "string" || !item.name.trim()) continue;
    const known = byKey.get(key(item.name));
    const name = known ?? item.name.trim().slice(0, 60);
    if (seen.has(key(name))) continue;
    seen.add(key(name));
    const hasAmount = Number.isFinite(item.amount) && item.amount > 0 && UNITS.includes(item.unit);
    result.push({
      name,
      amount: hasAmount ? item.amount : null,
      unit: hasAmount ? item.unit : "",
      known: Boolean(known),
    });
  }
  return result;
}

/** Без ключа к модели сервер отвечает заготовкой: так можно проверить приложение и HTTPS до подключения модели. */
const MOCK_ITEMS = [
  { name: "Яйца", amount: 6, unit: "шт" },
  { name: "Молоко", amount: 900, unit: "мл" },
  { name: "Сыр", amount: 200, unit: "г" },
  { name: "Огурец", amount: 2, unit: "шт" },
];

export async function recognize({ imageBase64, products, config, fetchImpl = fetch }) {
  if (config.mock) return normalizeItems(MOCK_ITEMS, products);

  const response = await fetchImpl(`${config.baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${config.apiKey}`, ...config.extraHeaders },
    body: JSON.stringify(buildRequest({ model: config.model, imageBase64, products })),
    signal: AbortSignal.timeout(config.timeoutMs),
  });
  if (!response.ok) {
    throw new Error(`Модель ответила ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
  const data = await response.json();
  const text = data.choices?.[0]?.message?.content ?? "";
  return normalizeItems(parseModelReply(text).items, products);
}
