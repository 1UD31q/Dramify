import { useState } from 'react';
import { parseAccountId, searchPlayers } from '../api.js';
import { loadRecent, timeAgo } from '../utils.js';

export default function Home({ onOpen }) {
  const [q, setQ] = useState('');
  const [results, setResults] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const recent = loadRecent();

  async function submit(e) {
    e.preventDefault();
    const text = q.trim();
    if (!text) return;
    const id = parseAccountId(text);
    if (id) return onOpen(id);
    setLoading(true); setError(''); setResults(null);
    try {
      setResults(await searchPlayers(text));
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="home">
      <h1 className="hero-title">Статистика игроков Dota 2</h1>
      <p className="muted">Введи ник, Steam ID / Friend ID или ссылку на профиль Steam</p>
      <form className="search" onSubmit={submit}>
        <input
          autoFocus
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Например: 87278757 или steamcommunity.com/profiles/7656…"
        />
        <button className="btn primary" disabled={loading}>{loading ? 'Ищем…' : 'Найти'}</button>
      </form>

      {error && <div className="error">{error}</div>}

      {results && (
        <section className="card">
          <h2>Результаты поиска</h2>
          {results.length === 0 && <p className="muted">Никого не нашли. Попробуй Friend ID — его видно в профиле Dota 2.</p>}
          <ul className="player-list">
            {results.slice(0, 30).map((p) => (
              <li key={p.account_id} onClick={() => onOpen(p.account_id)}>
                <img src={p.avatarfull} alt="" />
                <div>
                  <div className="name">{p.personaname}</div>
                  <div className="muted small">ID {p.account_id} · последняя игра {timeAgo(p.last_match_time && Date.parse(p.last_match_time) / 1000)}</div>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}

      {!results && recent.length > 0 && (
        <section className="card">
          <h2>Недавние</h2>
          <ul className="player-list">
            {recent.map((p) => (
              <li key={p.id} onClick={() => onOpen(p.id)}>
                <img src={p.avatar} alt="" />
                <div>
                  <div className="name">{p.name}</div>
                  <div className="muted small">ID {p.id}</div>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
