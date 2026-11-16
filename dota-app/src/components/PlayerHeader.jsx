import { useState } from 'react';
import { refreshPlayer } from '../api.js';
import { rankIcon, rankInfo, rankStar, winrate } from '../utils.js';

export default function PlayerHeader({ player, wl, id, onReload }) {
  const { profile, rank_tier, leaderboard_rank } = player;
  const rank = rankInfo(rank_tier, leaderboard_rank);
  const win = wl?.win ?? 0, lose = wl?.lose ?? 0;
  const wr = winrate(win, win + lose);
  const [refreshing, setRefreshing] = useState(false);

  async function refresh() {
    setRefreshing(true);
    try {
      await refreshPlayer(id);
      // OpenDota обрабатывает запрос в фоне — даём ему немного времени
      setTimeout(() => { setRefreshing(false); onReload(); }, 4000);
    } catch {
      setRefreshing(false);
    }
  }

  return (
    <section className="card player-header">
      <img className="avatar" src={profile.avatarfull} alt="" />
      <div className="info">
        <h1>{profile.personaname}</h1>
        <div className="muted small">
          ID {id}
          {profile.loccountrycode && ` · ${profile.loccountrycode}`}
          {' · '}<a href={profile.profileurl} target="_blank" rel="noreferrer">Steam</a>
          {' · '}<a href={`https://www.opendota.com/players/${id}`} target="_blank" rel="noreferrer">OpenDota</a>
        </div>
        <button className="btn ghost small-btn" onClick={refresh} disabled={refreshing}>
          {refreshing ? 'Обновляем…' : '⟳ Обновить данные'}
        </button>
      </div>

      <div className="rank">
        <div className="medal">
          {rank.medal > 0 && <img src={rankIcon(rank.medal)} alt="" onError={(e) => (e.target.style.display = 'none')} />}
          {rank.stars > 0 && <img src={rankStar(rank.stars)} alt="" onError={(e) => (e.target.style.display = 'none')} />}
        </div>
        <div className="rank-label">{rank.label}</div>
      </div>

      <div className="stats">
        <Stat label="Победы" value={win.toLocaleString('ru-RU')} cls="win" />
        <Stat label="Поражения" value={lose.toLocaleString('ru-RU')} cls="loss" />
        <Stat label="Винрейт" value={`${wr}%`} cls={wr >= 50 ? 'win' : 'loss'} />
      </div>
    </section>
  );
}

function Stat({ label, value, cls }) {
  return (
    <div className="stat">
      <div className={`stat-value ${cls}`}>{value}</div>
      <div className="muted small">{label}</div>
    </div>
  );
}
