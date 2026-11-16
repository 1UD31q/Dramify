const RANKS = ['', 'Рекрут', 'Страж', 'Рыцарь', 'Герой', 'Легенда', 'Властелин', 'Божество', 'Титан'];

export function rankInfo(rankTier, leaderboard) {
  if (!rankTier) return { label: 'Без ранга', medal: 0, stars: 0 };
  const medal = Math.floor(rankTier / 10);
  const stars = rankTier % 10;
  if (medal === 8) {
    return { label: leaderboard ? `Титан · #${leaderboard}` : 'Титан', medal, stars: 0 };
  }
  return { label: `${RANKS[medal] || '?'} ${stars || ''}`.trim(), medal, stars };
}

export function rankIcon(medal) {
  return `https://www.opendota.com/assets/images/dota2/rank_icons/rank_icon_${medal}.png`;
}
export function rankStar(stars) {
  return `https://www.opendota.com/assets/images/dota2/rank_icons/rank_star_${stars}.png`;
}

export const isWin = (m) => (m.player_slot < 128) === m.radiant_win;

export function winrate(win, games) {
  return games ? Math.round((win / games) * 1000) / 10 : 0;
}

export function formatDuration(sec) {
  const m = Math.floor(sec / 60);
  const s = String(sec % 60).padStart(2, '0');
  return `${m}:${s}`;
}

export function timeAgo(unix) {
  if (!unix) return '—';
  const diff = Date.now() / 1000 - unix;
  const plural = (n, one, few, many) => {
    const m10 = n % 10, m100 = n % 100;
    if (m10 === 1 && m100 !== 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  };
  if (diff < 3600) { const n = Math.max(1, Math.floor(diff / 60)); return `${n} ${plural(n, 'минуту', 'минуты', 'минут')} назад`; }
  if (diff < 86400) { const n = Math.floor(diff / 3600); return `${n} ${plural(n, 'час', 'часа', 'часов')} назад`; }
  if (diff < 86400 * 30) { const n = Math.floor(diff / 86400); return `${n} ${plural(n, 'день', 'дня', 'дней')} назад`; }
  return new Date(unix * 1000).toLocaleDateString('ru-RU');
}

const MODES = {
  1: 'All Pick', 2: 'Captains Mode', 3: 'Random Draft', 4: 'Single Draft',
  5: 'All Random', 12: 'Least Played', 16: 'Captains Draft', 18: 'Ability Draft',
  19: 'Ивент', 20: 'ARDM', 21: '1v1 Mid', 22: 'All Pick', 23: 'Turbo',
};
export function gameMode(m) {
  const mode = MODES[m.game_mode] || 'Другое';
  return m.lobby_type === 7 ? `Рейтинг · ${mode}` : mode;
}

const RECENT_KEY = 'dh_recent_v1';
export function loadRecent() {
  try { return JSON.parse(localStorage.getItem(RECENT_KEY) || '[]'); } catch { return []; }
}
export function saveRecent(entry) {
  const list = [entry, ...loadRecent().filter((e) => e.id !== entry.id)].slice(0, 8);
  try { localStorage.setItem(RECENT_KEY, JSON.stringify(list)); } catch { /* ignore */ }
  return list;
}
