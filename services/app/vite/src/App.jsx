import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import UsersPage from './UsersPage.jsx';

function Navbar() {
  const location = useLocation();
  const active = location.pathname.startsWith('/games') ? 'games' : undefined;

  // The shared site header (services/shared/site-header.js), the same bar on every engineerfamily.net page; don't restyle.
  return <ef-site-header active={active}></ef-site-header>;
}

// Google's OAuth verification reads this page for the app's purpose. index.html has the same text inside #root for
// crawlers that don't run JS, so keep the two in sync.
function HomePage() {
  return (
    <section className="page-shell home-shell">
      <article className="home-card">
        <h1>engineerfamily</h1>
        <p className="home-lede">
          engineerfamily.net is a personal website run by Siddharth Engineer. It hosts small games and Strelitzia, a
          self-hosted job search assistant.
        </p>
        <h2>Signing in with Google</h2>
        <p>
          Every page can be read without signing in. If you sign in with Google, the site uses your name and email
          address only to show who is signed in and to let invited users open the Strelitzia dashboard.
        </p>
        <p>
          Strelitzia can save the resumes and cover letters it writes to your own Google Drive, using the{' '}
          <code>drive.file</code> permission, so it only sees files it created. It works with text documents only. It
          does not create, edit or analyze images, and it does not use Google data to train AI models.
        </p>
        <p>
          <a href="/privacy">Privacy policy</a> · <a href="/strelitzia/">About Strelitzia</a> ·{' '}
          <a href="/strelitzia/privacy">Strelitzia privacy policy</a>
        </p>
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
        <Route path="/users/" element={<UsersPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </>
  );
}
