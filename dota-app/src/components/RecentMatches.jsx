import HeroIcon from './HeroIcon.jsx';
import { formatDuration, gameMode, isWin, timeAgo } from '../utils.js';

export default function RecentMatches({ matches, heroes }) {
  return (
    <section className="card">
      <h2>Последние матчи</h2>
      {!matches && <p className="muted">Не удалось загрузить матчи.</p>}
      {matches?.length === 0 && <p className="muted">Матчей пока нет.</p>}
      {matches?.length > 0 && (
        <table className="table">
          <thead>
            <tr><th>Герой</th><th>Результат</th><th>Режим</th><th>Длит.</th><th>K / D / A</th></tr>
          </thead>
          <tbody>
            {matches.map((m) => {
              const win = isWin(m);
              const hero = heroes[m.hero_id];
              return (
                <tr key={m.match_id} className="clickable"
                    onClick={() => window.open(`https://www.opendota.com/matches/${m.match_id}`)}>
                  <td>
                    <div className="hero-cell">
                      <HeroIcon hero={hero} />
                      <div>
                        <div>{hero?.name ?? `Герой #${m.hero_id}`}</div>
                        <div className="muted small">{timeAgo(m.start_time)}</div>
                      </div>
                    </div>
                  </td>
                  <td><span className={`badge ${win ? 'win' : 'loss'}`}>{win ? 'Победа' : 'Поражение'}</span></td>
                  <td className="muted">{gameMode(m)}</td>
                  <td>{formatDuration(m.duration)}</td>
                  <td className="kda">
                    <span className="win">{m.kills}</span> / <span className="loss">{m.deaths}</span> / <span>{m.assists}</span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}
    </section>
  );
}
