import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom';
import siddharth from '../../portfolios/siddharth/profile.json';
import shivam from '../../portfolios/shivam/profile.json';
import suryan from '../../portfolios/suryan/profile.json';
import nivi from '../../portfolios/nivi/profile.json';

const PEOPLE = [
  { slug: 'siddharth', profile: siddharth },
  { slug: 'shivam', profile: shivam },
  { slug: 'suryan', profile: suryan },
  { slug: 'nivi', profile: nivi },
];

function getStreamlitUrl() {
  const { hostname } = window.location;

  if (hostname === 'localhost' || hostname === '127.0.0.1') {
    return `http://${hostname}:8501`;
  }

  if (hostname.includes('preprod')) {
    return 'https://streamlit-preprod.engineerfamily.net';
  }

  return 'https://streamlit.engineerfamily.net';
}

function Navbar() {
  const location = useLocation();
  const isPortfolioPage = PEOPLE.some((p) => location.pathname.startsWith(`/${p.slug}`));
  const isGamesPage = location.pathname.startsWith('/games');
  const streamlitUrl = getStreamlitUrl();

  return (
    <header className="site-header">
      <nav className="site-nav" aria-label="Main navigation">
        <Link to="/" className="brand-link">
          Engineer Family
        </Link>

        <ul className="nav-menu">
          <li className={`nav-item nav-item-dropdown ${isPortfolioPage ? 'is-active' : ''}`}>
            <button className="nav-link dropdown-trigger" type="button" aria-haspopup="true">
              Portfolios
            </button>
            <ul className="dropdown-menu" aria-label="Portfolios dropdown">
              {PEOPLE.map((person) => (
                <li key={person.slug}>
                  <Link className="dropdown-link" to={`/${person.slug}/`}>
                    {person.profile.name}
                  </Link>
                </li>
              ))}
            </ul>
          </li>
          <li className="nav-item">
            <a className="nav-link" href="https://writing.engineerfamily.net" target="_blank" rel="noreferrer noopener">
              Writing
            </a>
          </li>
          <li className="nav-item">
            <a className={`nav-link ${isGamesPage ? 'is-active' : ''}`} href="/games/">
              Games
            </a>
          </li>
          <li className="nav-item">
            <a className="nav-link" href={streamlitUrl} target="_blank" rel="noreferrer noopener">
              Streamlit
            </a>
          </li>
        </ul>
      </nav>
    </header>
  );
}

function HomePage() {
  return <section className="page-shell barebones-home" />;
}

function PortfolioPage({ profile }) {
  return (
    <section className="page-shell">
      <article className="portfolio-card" style={{ borderTop: `3px solid ${profile.themeColor}` }}>
        <h1>{profile.name}</h1>
        <p className="portfolio-headline">{profile.headline}</p>
        <p>{profile.summary}</p>
      </article>
    </section>
  );
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
        {PEOPLE.map((person) => (
          <Route
            key={person.slug}
            path={`/${person.slug}/`}
            element={<PortfolioPage profile={person.profile} />}
          />
        ))}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  );
}
