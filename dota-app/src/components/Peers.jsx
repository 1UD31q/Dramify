import { WinBar } from './TopHeroes.jsx';
import { winrate } from '../utils.js';

export default function Peers({ peers, onOpen }) {
  const top = (peers || []).filter((p) => p.with_games > 0).slice(0, 10);
  return (
    <section className="card">
      <h2>С кем играет</h2>
      {!peers && <p className="muted">Не удалось загрузить тиммейтов.</p>}
      {peers && top.length === 0 && <p className="muted">Нет данных о совместных играх.</p>}
      <ul className="rows">
        {top.map((p) => (
          <li key={p.account_id} className="clickable" onClick={() => onOpen(p.account_id)}>
            <img className="peer-avatar" src={p.avatarfull} alt="" />
            <div className="grow">
              <div>{p.personaname || `ID ${p.account_id}`}</div>
              <div className="muted small">{p.with_games} игр вместе</div>
            </div>
            <WinBar wr={winrate(p.with_win, p.with_games)} />
          </li>
        ))}
      </ul>
    </section>
  );
}
