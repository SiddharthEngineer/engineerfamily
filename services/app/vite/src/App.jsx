import { Navigate, Route, Routes, useLocation } from 'react-router-dom';

function Navbar() {
  const location = useLocation();
  const isGamesPage = location.pathname.startsWith('/games');

  return (
    <header className="site-header">
      <nav className="site-nav" aria-label="Main navigation">
        {/* Shared with every engineerfamily.net page (services/shared/site-header.js); don't restyle. */}
        <ef-home></ef-home>

        <ul className="nav-menu">
          <li className="nav-item">
            <a className={`nav-link ${isGamesPage ? 'is-active' : ''}`} href="/games/">
              Games
            </a>
          </li>
          <li className="nav-item">
            {/* nginx serves /strelitzia/ (static page + dashboard), not this app, so a full page load. */}
            <a className="nav-link" href="/strelitzia/">
              Strelitzia
            </a>
          </li>
        </ul>

        <ef-profile></ef-profile>
      </nav>
    </header>
  );
}

function HomePage() {
  return <section className="page-shell barebones-home" />;
}

function GamesPage() {
  return (
    <section className="page-shell games-shell">
      <article className="games-card">
        <h1>Games</h1>
        <p>Built with the same site framework, but with room for game-first content and cards.</p>
      </article>
    </section>
  );
}

export default function App() {
  return (
    <>
      <Navbar />
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/games/" element={<GamesPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  );
}
