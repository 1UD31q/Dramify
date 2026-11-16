import { useEffect, useState } from 'react';
import { getHeroes } from './api.js';
import Home from './components/Home.jsx';
import PlayerPage from './components/PlayerPage.jsx';

export default function App() {
  const [stack, setStack] = useState([{ name: 'home' }]);
  const [heroes, setHeroes] = useState({});
  const view = stack[stack.length - 1];

  useEffect(() => { getHeroes().then(setHeroes).catch(() => {}); }, []);

  const openPlayer = (id) => setStack((s) => [...s, { name: 'player', id: String(id) }]);
  const back = () => setStack((s) => (s.length > 1 ? s.slice(0, -1) : s));
  const home = () => setStack([{ name: 'home' }]);

  return (
    <div className="app">
      <header className="topbar">
        <button className="logo" onClick={home}>
          <span className="logo-mark">D</span> DotaHelperr
        </button>
        {stack.length > 1 && <button className="btn ghost" onClick={back}>← Назад</button>}
      </header>
      <main className="content">
        {view.name === 'home' && <Home onOpen={openPlayer} />}
        {view.name === 'player' && <PlayerPage key={view.id} id={view.id} heroes={heroes} onOpen={openPlayer} />}
      </main>
      <footer className="footer">Данные: OpenDota API · не связано с Valve</footer>
    </div>
  );
}
