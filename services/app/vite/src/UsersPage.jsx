import { useEffect, useRef, useState } from 'react';

// Admin-only: who may open which page. The data path is the /api/admin/* API (services/app/admin.py), which refuses
// non-admins itself; this page only hides what they couldn't use anyway. Every change saves on its own (no Save button).

const EVERYONE = '*';
const NEEDS_ACCOUNT = 'Needs a signed-in, invited user';

const who = (row) => (row.email === EVERYONE ? 'everyone' : row.email);

async function api(method, path, body) {
  const options = { method, credentials: 'same-origin', headers: { Accept: 'application/json' } };
  if (body !== undefined) {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }
  const resp = await fetch(path, options);
  if (resp.status === 204) return null;
  const data = await resp.json().catch(() => null);
  if (!resp.ok) throw new Error(data?.error || `the server answered ${resp.status}`);
  return data;
}

const userPath = (email) => `/api/admin/users/${encodeURIComponent(email)}`;

function Shell({ children }) {
  return (
    <section className="page-shell users-shell">
      <article className="users-card">
        <h1>Users</h1>
        {children}
      </article>
    </section>
  );
}

function CapInput({ row, disabled, title, onSave }) {
  // Admins have no cap, whatever is stored (promoting a user keeps their old cap_usd): show "No cap".
  const saved = row.admin || row.cap_usd == null ? '' : String(row.cap_usd);
  const [draft, setDraft] = useState(saved);
  useEffect(() => setDraft(saved), [saved]);

  function commit() {
    const text = draft.trim();
    if (text === saved) return;
    const cap = text === '' ? null : Number(text);
    if (cap !== null && (!Number.isFinite(cap) || cap < 0)) {
      setDraft(saved);
      onSave(undefined, 'the cap must be a number of dollars, 0 or more, or empty for no cap');
      return;
    }
    setDraft(cap === null ? '' : String(cap));
    onSave(cap);
  }

  return (
    <span className="users-cap" title={title}>
      <span aria-hidden="true">$</span>
      <input
        type="text"
        inputMode="decimal"
        placeholder="No cap"
        aria-label={`Cap Spend for ${who(row)}`}
        value={draft}
        disabled={disabled}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === 'Enter') e.currentTarget.blur();
        }}
      />
    </span>
  );
}

function UserRow({ row, pages, me, readOnly, onChange, onRemove }) {
  const everyone = row.email === EVERYONE;
  const self = !everyone && row.email === me;
  const cells = [];

  for (const page of pages) {
    const blocked = everyone && page.needs_account;
    cells.push(
      <td key={page.key} title={blocked ? NEEDS_ACCOUNT : undefined}>
        <input
          type="checkbox"
          aria-label={`${page.label} for ${who(row)}`}
          checked={row.admin || row.pages.includes(page.key)}
          disabled={readOnly || row.admin || blocked}
          onChange={(e) => onChange(row, { pages: { [page.key]: e.target.checked } })}
        />
      </td>
    );
    if (page.cap) {
      // Granting the page resets the cap to the default, so the cap opens up only once the page is ticked.
      const granted = row.pages.includes(page.key);
      let capTitle;
      if (everyone) capTitle = NEEDS_ACCOUNT;
      else if (!row.admin && !granted) capTitle = `Tick ${page.label} first`;
      cells.push(
        <td key={`${page.key}-cap`}>
          <CapInput
            row={row}
            disabled={readOnly || row.admin || everyone || !granted}
            title={capTitle}
            onSave={(cap, error) => onChange(row, { cap_usd: cap }, error)}
          />
        </td>
      );
    }
  }

  return (
    <tr className={everyone ? 'users-everyone' : undefined}>
      <th scope="row">{everyone ? 'Everyone (signed out or not invited)' : row.email}</th>
      <td title={self ? "You can't remove your own admin flag" : undefined}>
        {everyone ? null : (
          <input
            type="checkbox"
            aria-label={`Admin for ${who(row)}`}
            checked={row.admin}
            disabled={readOnly || self}
            onChange={(e) => onChange(row, { admin: e.target.checked })}
          />
        )}
      </td>
      {cells}
      <td>
        {everyone ? null : (
          <button
            type="button"
            className="users-remove"
            disabled={readOnly || self}
            title={self ? "You can't remove yourself" : undefined}
            onClick={() => onRemove(row)}
          >
            Remove
          </button>
        )}
      </td>
    </tr>
  );
}

function applyChange(row, change) {
  const next = { ...row };
  if ('admin' in change) next.admin = change.admin;
  if ('cap_usd' in change) next.cap_usd = change.cap_usd;
  for (const [key, allowed] of Object.entries(change.pages || {})) {
    next.pages = allowed ? [...next.pages.filter((k) => k !== key), key] : next.pages.filter((k) => k !== key);
  }
  return next;
}

export default function UsersPage() {
  const [me, setMe] = useState(undefined);
  const [data, setData] = useState(null);
  const [loadError, setLoadError] = useState('');
  const [error, setError] = useState('');
  const [invite, setInvite] = useState('');
  const [inviteError, setInviteError] = useState('');
  const [inviting, setInviting] = useState(false);
  const queues = useRef({});

  useEffect(() => {
    let live = true;
    api('GET', '/auth/me')
      .then((answer) => live && setMe(answer))
      .catch(() => live && setMe(null));
    return () => {
      live = false;
    };
  }, []);

  useEffect(() => {
    if (!me?.admin) return undefined;
    let live = true;
    api('GET', '/api/admin/users')
      .then((users) => live && setData(users))
      .catch((e) => live && setLoadError(e.message));
    return () => {
      live = false;
    };
  }, [me?.admin]);

  if (me === undefined) return <Shell><p className="users-muted">Loading…</p></Shell>;

  if (!me?.admin) {
    return (
      <Shell>
        <p>You don't have access to this page.</p>
        {me?.enabled && !me.signed_in ? (
          <p>
            <a href="/auth/login?next=/users/">Sign in</a> with an admin account.
          </p>
        ) : null}
      </Shell>
    );
  }

  if (!data) {
    return (
      <Shell>
        {loadError ? <p role="alert" className="users-error">Couldn't load the users: {loadError}</p> : <p className="users-muted">Loading…</p>}
      </Shell>
    );
  }

  const readOnly = !data.db;
  const myEmail = (me.email || '').trim().toLowerCase();

  function updateRow(email, update) {
    setData((d) =>
      email === EVERYONE
        ? { ...d, everyone: update(d.everyone) }
        : { ...d, users: d.users.map((u) => (u.email === email ? update(u) : u)) }
    );
  }

  // One request at a time per row, so a later click can't be overwritten by an earlier answer. A refused change
  // reloads the table, which also keeps any other change to the row that did save.
  function change(row, body, localError) {
    const label = row.email === EVERYONE ? 'Everyone' : row.email;
    if (localError) {
      setError(`${label}: ${localError}`);
      return;
    }
    setError('');
    updateRow(row.email, (current) => applyChange(current, body));
    const path = row.email === EVERYONE ? '/api/admin/everyone' : userPath(row.email);
    const previous = queues.current[row.email] || Promise.resolve();
    const run = previous.then(async () => {
      try {
        const saved = await api('PATCH', path, body);
        if (queues.current[row.email] === run) updateRow(row.email, () => saved);
      } catch (e) {
        setError(`${label}: ${e.message}`);
        api('GET', '/api/admin/users').then(setData, () => {});
      }
    });
    queues.current[row.email] = run;
  }

  async function remove(row) {
    if (!window.confirm(`Remove ${row.email}? They lose every page that isn't open to everyone.`)) return;
    setError('');
    try {
      await api('DELETE', userPath(row.email));
      setData((d) => ({ ...d, users: d.users.filter((u) => u.email !== row.email) }));
    } catch (e) {
      setError(`${row.email}: ${e.message}`);
    }
  }

  async function submitInvite(e) {
    e.preventDefault();
    setInviteError('');
    setInviting(true);
    try {
      const row = await api('POST', '/api/admin/users', { email: invite });
      setData((d) => ({ ...d, users: [...d.users, row] }));
      setInvite('');
    } catch (err) {
      setInviteError(err.message);
    } finally {
      setInviting(false);
    }
  }

  const headers = [];
  for (const page of data.pages) {
    headers.push(<th key={page.key} scope="col">{page.label}</th>);
    if (page.cap) headers.push(<th key={`${page.key}-cap`} scope="col">Cap Spend</th>);
  }

  return (
    <Shell>
      <p className="users-muted">Who may open which page. Admins can open everything, with no cap.</p>
      {readOnly ? <p className="users-banner">No database configured: read-only.</p> : null}

      <form className="users-invite" onSubmit={submitInvite}>
        <label htmlFor="users-invite-email">Invite by email</label>
        <div className="users-invite-row">
          <input
            id="users-invite-email"
            type="email"
            autoComplete="off"
            required
            value={invite}
            disabled={readOnly}
            aria-describedby={inviteError ? 'users-invite-error' : undefined}
            onChange={(e) => setInvite(e.target.value)}
          />
          <button type="submit" disabled={readOnly || inviting}>
            Invite
          </button>
        </div>
        {inviteError ? (
          <p id="users-invite-error" role="alert" className="users-error">
            {inviteError}
          </p>
        ) : null}
      </form>

      {error ? (
        <p role="alert" className="users-error">
          {error}
        </p>
      ) : null}

      <div className="users-table-wrap">
        <table className="users-table">
          <thead>
            <tr>
              <th scope="col">Email</th>
              <th scope="col">Admin</th>
              {headers}
              <th scope="col">
                <span className="users-sr">Remove</span>
              </th>
            </tr>
          </thead>
          <tbody>
            {[data.everyone, ...data.users].map((row) => (
              <UserRow
                key={row.email}
                row={row}
                pages={data.pages}
                me={myEmail}
                readOnly={readOnly}
                onChange={change}
                onRemove={remove}
              />
            ))}
          </tbody>
        </table>
      </div>
    </Shell>
  );
}
