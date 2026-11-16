import HeroIcon from './HeroIcon.jsx';
import { timeAgo, winrate } from '../utils.js';

export default function TopHeroes({ stats, heroes }) {
  const top = (stats || []).filter((h) => h.games > 0).slice(0, 10);
  return (
    <section className="card">
      <h2>Любимые герои</h2>
      {!stats && <p className="muted">Не удалось загрузить героев.</p>}
      {stats && top.length === 0 && <p className="muted">Нет данных.</p>}
      <ul className="rows">
        {top.map((h) => {
          const hero = heroes[h.hero_id];
          const wr = winrate(h.win, h.games);
          return (
            <li key={h.hero_id}>
              <HeroIcon hero={hero} size="sm" />
              <div className="grow">
                <div>{hero?.name ?? `#${h.hero_id}`}</div>
                <div className="muted small">{h.games} игр · {timeAgo(h.last_played)}</div>
              </div>
              <WinBar wr={wr} />
            </li>
          );
        })}
      </ul>
    </section>
  );
}

export function WinBar({ wr }) {
  return (
    <div className="winbar" title={`Винрейт ${wr}%`}>
      <span className={wr >= 50 ? 'win' : 'loss'}>{wr}%</span>
      <div className="bar"><div className={wr >= 50 ? 'fill win' : 'fill loss'} style={{ width: `${wr}%` }} /></div>
    </div>
  );
}
