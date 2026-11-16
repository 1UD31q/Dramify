const BASE = 'https://api.opendota.com/api';
const STEAM_CDN = 'https://cdn.cloudflare.steamstatic.com';
const STEAM64_OFFSET = 76561197960265728n;

async function get(path) {
  let res;
  try {
    res = await fetch(BASE + path);
  } catch {
    throw new Error('Нет связи с OpenDota. Проверь интернет.');
  }
  if (res.status === 429) throw new Error('Слишком много запросов к OpenDota. Подожди минуту.');
  if (!res.ok) throw new Error(`OpenDota ответил ошибкой ${res.status}`);
  return res.json();
}

/**
 * Разбирает ввод пользователя: Account ID (32 бита), SteamID64,
 * ссылку на steamcommunity.com/profiles/… или opendota/dotabuff.
 * Возвращает account_id строкой или null, если это похоже на ник.
 */
export function parseAccountId(input) {
  const s = input.trim();
  const url = s.match(/(?:profiles|players)\/(\d+)/);
  const digits = url ? url[1] : /^\d+$/.test(s) ? s : null;
  if (!digits) return null;
  const n = BigInt(digits);
  if (n > STEAM64_OFFSET) return (n - STEAM64_OFFSET).toString();
  return n.toString();
}

export const searchPlayers = (q) => get(`/search?q=${encodeURIComponent(q)}`);
export const getPlayer = (id) => get(`/players/${id}`);
export const getWinLoss = (id) => get(`/players/${id}/wl`);
export const getRecentMatches = (id) => get(`/players/${id}/recentMatches`);
export const getPlayerHeroes = (id) => get(`/players/${id}/heroes`);
export const getPeers = (id) => get(`/players/${id}/peers`);

export async function refreshPlayer(id) {
  const res = await fetch(`${BASE}/players/${id}/refresh`, { method: 'POST' });
  if (!res.ok) throw new Error('Не удалось запросить обновление');
}

const HEROES_KEY = 'dh_heroes_v1';
const DAY = 24 * 60 * 60 * 1000;

/** Справочник героев { [id]: { name, img } }, кешируется на сутки. */
export async function getHeroes() {
  try {
    const cached = JSON.parse(localStorage.getItem(HEROES_KEY) || 'null');
    if (cached && Date.now() - cached.t < DAY) return cached.data;
  } catch { /* кеш недоступен — просто загрузим */ }
  const list = await get('/heroes');
  const data = {};
  for (const h of list) {
    const short = h.name.replace('npc_dota_hero_', '');
    data[h.id] = {
      name: h.localized_name,
      img: `${STEAM_CDN}/apps/dota2/images/dota_react/heroes/${short}.png`,
    };
  }
  try { localStorage.setItem(HEROES_KEY, JSON.stringify({ t: Date.now(), data })); } catch { /* ignore */ }
  return data;
}
