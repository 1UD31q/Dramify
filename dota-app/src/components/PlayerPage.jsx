import { useEffect, useState } from 'react';
import * as api from '../api.js';
import { saveRecent } from '../utils.js';
import PlayerHeader from './PlayerHeader.jsx';
import RecentMatches from './RecentMatches.jsx';
import TopHeroes from './TopHeroes.jsx';
import Peers from './Peers.jsx';

export default function PlayerPage({ id, heroes, onOpen }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let alive = true;
    setError('');
    Promise.allSettled([
      api.getPlayer(id), api.getWinLoss(id), api.getRecentMatches(id),
      api.getPlayerHeroes(id), api.getPeers(id),
    ]).then(([player, wl, matches, heroStats, peers]) => {
      if (!alive) return;
      if (player.status === 'rejected') return setError(player.reason.message);
      const p = player.value;
      if (!p.profile) return setError('Профиль не найден или скрыт. Игроку нужно включить «Общедоступную историю матчей» в настройках Dota 2.');
      saveRecent({ id, name: p.profile.personaname, avatar: p.profile.avatarfull });
      const val = (r) => (r.status === 'fulfilled' ? r.value : null);
      setData({ player: p, wl: val(wl), matches: val(matches), heroStats: val(heroStats), peers: val(peers) });
    });
    return () => { alive = false; };
  }, [id, reload]);

  if (error) return <div className="error big">{error}</div>;
  if (!data) return <div className="loading"><div className="spinner" />Загружаем профиль…</div>;

  return (
    <div className="player-page">
      <PlayerHeader player={data.player} wl={data.wl} id={id} onReload={() => setReload((n) => n + 1)} />
      <div className="grid">
        <RecentMatches matches={data.matches} heroes={heroes} />
        <div className="side">
          <TopHeroes stats={data.heroStats} heroes={heroes} />
          <Peers peers={data.peers} onOpen={onOpen} />
        </div>
      </div>
    </div>
  );
}
