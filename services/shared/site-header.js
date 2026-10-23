// engineerfamily site header pieces, the same on every page (see README.md here):
//   <ef-home [light]>                 the round home icon to /, first thing in the header
//   <ef-profile [light] next="/path"> sign in, or initials + a menu that ends with Sign out, last thing in the header
//   <ef-site-header active="games|strelitzia|wordle">  the whole bar (home, site links, profile) for every page but the dashboard
// ef-home and ef-profile use Shadow DOM with their own fixed styles, so no page theme leaks in; `light` keeps them light
// in OS dark mode. No build step; safe to load twice.
(() => {
  if (customElements.get('ef-home')) return;

  const BASE_CSS = `
    :host {
      all: initial;
      display: inline-flex;
      align-items: center;
      flex: none;
      font: 600 14px/1 system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      letter-spacing: 0;
      --ef-surface: #fffefb;
      --ef-fg: #2a1f17;
      --ef-muted: #6b5e52;
      --ef-border: rgba(42, 31, 23, 0.16);
      --ef-accent: #c95f43;
      --ef-on-accent: #ffffff;
      --ef-hover: rgba(201, 95, 67, 0.12);
      --ef-shadow: 0 10px 28px rgba(42, 31, 23, 0.16);
      --ef-focus: #3a3fa8;
    }
    @media (prefers-color-scheme: dark) {
      :host(:not([light])) {
        --ef-surface: #241f1b;
        --ef-fg: #f3eee6;
        --ef-muted: #c2b5a8;
        --ef-border: rgba(243, 238, 230, 0.2);
        --ef-accent: #f08a6c;
        --ef-on-accent: #1b1612;
        --ef-hover: rgba(240, 138, 108, 0.18);
        --ef-shadow: 0 10px 28px rgba(0, 0, 0, 0.45);
        --ef-focus: #8f95ff;
      }
    }
    :host([hidden]) { display: none; }
    * { box-sizing: border-box; }
    .pill {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      height: 36px;
      padding: 0 14px;
      margin: 0;
      border: 1px solid var(--ef-border);
      border-radius: 999px;
      background: var(--ef-surface);
      color: var(--ef-fg);
      font: inherit;
      text-decoration: none;
      white-space: nowrap;
      cursor: pointer;
    }
    .pill:hover { background: var(--ef-hover); }
    a:focus-visible, button:focus-visible { outline: 2px solid var(--ef-focus); outline-offset: 2px; }
  `;

  class EfHome extends HTMLElement {
    connectedCallback() {
      if (this.shadowRoot) return;
      const root = this.attachShadow({ mode: 'open' });
      // `compact` is still accepted (older pages set it) but the icon is always compact now.
      root.innerHTML = `<style>${BASE_CSS}
        .home { width: 36px; padding: 0; border-radius: 50%; }
        svg { display: block; width: 18px; height: 18px; }
      </style><a class="pill home" href="/" aria-label="engineerfamily home" title="engineerfamily home"><svg viewBox="0 0 24 24"
        fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"
        focusable="false"><path d="M3 10.5 12 3l9 7.5"/><path d="M5 9v11h14V9"/><path d="M10 20v-6h4v6"/></svg></a>`;
    }
  }

  // One /auth/me request per page, however many <ef-profile> there are.
  let mePromise = null;
  function fetchMe() {
    mePromise ??= fetch('/auth/me', { credentials: 'same-origin', headers: { Accept: 'application/json' } })
      .then((resp) => (resp.ok ? resp.json() : null))
      .catch(() => null);
    return mePromise;
  }

  // What's deployed here, from the version.json each deploy writes (scripts/site-version.sh); once per page. Anything
  // missing or odd means no version text.
  let versionPromise = null;
  function fetchVersion() {
    versionPromise ??= fetch('/shared/version.json', { cache: 'no-store', headers: { Accept: 'application/json' } })
      .then((resp) => (resp.ok ? resp.json() : null))
      .then((data) => (data && typeof data.label === 'string' && data.label && typeof data.url === 'string'
        && data.url.startsWith('https://github.com/') ? data : null))
      .catch(() => null);
    return versionPromise;
  }

  // Whether to show "Users": Strelitzia's owner for now (site-perms swaps this for the site admin flag). Asked once
  // per page, only when signed in; any error means no link.
  let ownerPromise = null;
  function fetchIsOwner() {
    ownerPromise ??= fetch('/strelitzia/dashboard/api/auth/me', {
      credentials: 'same-origin',
      headers: { Accept: 'application/json' },
    })
      .then((resp) => (resp.ok ? resp.json() : null))
      .then((data) => Boolean(data && data.enabled && data.user && data.user.role === 'owner'))
      .catch(() => false);
    return ownerPromise;
  }

  function initials(name, email) {
    const words = (name || '').trim().split(/\s+/).filter(Boolean);
    const letters = words.length > 1 ? words[0][0] + words[words.length - 1][0] : (words[0] || email || '?').slice(0, 1);
    return letters.toUpperCase();
  }

  function escapeHtml(text) {
    return String(text).replace(/[&<>"']/g, (ch) => `&#${ch.charCodeAt(0)};`);
  }

  class EfProfile extends HTMLElement {
    connectedCallback() {
      if (this.shadowRoot) return;
      this.attachShadow({ mode: 'open' });
      this.onDocClick = (event) => {
        if (!event.composedPath().includes(this)) this.closeMenu(false);
      };
      const version = fetchVersion();
      // The account UI doesn't wait for the version; it slots in before it when it comes.
      fetchMe().then((me) => {
        this.render(me);
        return version;
      }).then((v) => this.showVersion(v));
    }

    disconnectedCallback() {
      document.removeEventListener('click', this.onDocClick);
    }

    loginHref() {
      const next = this.getAttribute('next') || window.location.pathname + window.location.search;
      return `/auth/login?next=${encodeURIComponent(next)}`;
    }

    render(me) {
      const root = this.shadowRoot;
      const css = `<style>${BASE_CSS}
        :host { position: relative; gap: 8px; }
        .avatar {
          width: 36px; height: 36px; padding: 0; border-radius: 50%;
          background: var(--ef-accent); color: var(--ef-on-accent); border-color: transparent; font-size: 13px;
        }
        .avatar:hover { background: var(--ef-accent); filter: brightness(1.08); }
        .menu {
          position: absolute; top: calc(100% + 8px); right: 0; z-index: 1000;
          width: max-content; min-width: 220px; max-width: min(320px, calc(100vw - 32px));
          padding: 12px; border: 1px solid var(--ef-border); border-radius: 14px;
          background: var(--ef-surface); color: var(--ef-fg); box-shadow: var(--ef-shadow);
          font-weight: 400; line-height: 1.4;
        }
        .menu[hidden] { display: none; }
        .name { font-weight: 700; }
        .email { color: var(--ef-muted); font-size: 13px; overflow-wrap: anywhere; }
        .rule { height: 1px; margin: 10px 0; background: var(--ef-border); }
        .item {
          display: block; width: calc(100% + 16px); padding: 8px; margin: 0 -8px; border: 0; border-radius: 8px;
          background: none; color: var(--ef-fg); font: inherit; text-align: left; text-decoration: none; cursor: pointer;
        }
        .item:hover { background: var(--ef-hover); }
        .version {
          min-width: 0; max-width: 14ch; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
          color: var(--ef-muted); font-size: 12px; font-weight: 400; text-decoration: none;
        }
        .version:hover { color: var(--ef-fg); }
      </style>`;
      // Sign-in off (or /auth/me unreachable): only the version, if any.
      if (!me || !me.enabled) {
        root.innerHTML = css;
        return;
      }
      if (!me.signed_in) {
        root.innerHTML = `${css}<a class="pill" href="/auth/login">Sign in</a>`;
        const link = root.querySelector('a.pill');
        link.href = this.loginHref();
        // The path may have changed since render (client-side routing), so build `next` again on click.
        link.addEventListener('click', () => { link.href = this.loginHref(); });
        return;
      }
      const label = me.name || me.email;
      root.innerHTML = `${css}
        <button class="pill avatar" type="button" aria-haspopup="true" aria-expanded="false" aria-controls="ef-menu"
          aria-label="Account: ${escapeHtml(label)}" title="${escapeHtml(label)}">${escapeHtml(initials(me.name, me.email))}</button>
        <div class="menu" id="ef-menu" hidden>
          ${me.name ? `<div class="name">${escapeHtml(me.name)}</div>` : ''}
          <div class="email">${escapeHtml(me.email)}</div>
          <div class="rule"></div>
          <a class="item" href="/strelitzia/dashboard/">Strelitzia dashboard</a>
          <div class="rule"></div>
          <button class="item signout" type="button">Sign out</button>
        </div>`;
      this.button = root.querySelector('.avatar');
      this.menu = root.querySelector('.menu');
      this.button.addEventListener('click', () => (this.menu.hidden ? this.openMenu() : this.closeMenu(true)));
      root.addEventListener('keydown', (event) => {
        if (event.key === 'Escape' && !this.menu.hidden) {
          event.stopPropagation();
          this.closeMenu(true);
        }
      });
      this.menu.addEventListener('focusout', (event) => {
        if (event.relatedTarget && !root.contains(event.relatedTarget)) this.closeMenu(false);
      });
      root.querySelector('.signout').addEventListener('click', (event) => this.signOut(event.currentTarget));
      // Add Users when the answer comes; the menu works without waiting for it.
      fetchIsOwner().then((isOwner) => {
        if (!isOwner || this.menu.querySelector('.users')) return;
        const users = document.createElement('a');
        users.className = 'item users';
        users.href = '/strelitzia/dashboard/users';
        users.textContent = 'Users';
        this.menu.querySelector('a[href="/strelitzia/dashboard/"]').after(users);
      });
    }

    showVersion(version) {
      const root = this.shadowRoot;
      if (!version || root.querySelector('.version')) return;
      const link = document.createElement('a');
      link.className = 'version';
      link.href = version.url;
      link.title = 'Deployed version';
      link.textContent = version.label;
      root.querySelector('style').after(link);
    }

    openMenu() {
      this.menu.hidden = false;
      this.button.setAttribute('aria-expanded', 'true');
      document.addEventListener('click', this.onDocClick);
      this.menu.querySelector('.item').focus();
    }

    closeMenu(refocus) {
      if (!this.menu || this.menu.hidden) return;
      this.menu.hidden = true;
      this.button.setAttribute('aria-expanded', 'false');
      document.removeEventListener('click', this.onDocClick);
      if (refocus) this.button.focus();
    }

    async signOut(button) {
      button.disabled = true;
      try {
        await fetch('/auth/logout', { method: 'POST', credentials: 'same-origin' });
      } finally {
        window.location.reload();
      }
    }
  }

  // The page header for every engineerfamily.net page but the Strelitzia dashboard: a solid bar like the dashboard's
  // top bar, always light, scrolling away with the page. Light DOM, so `header nav` is queryable; one <style> in <head>.
  const SITE_HEADER_CSS = `
    ef-site-header {
      display: block;
      width: 100%;
      margin: 0;
      color-scheme: light;
    }
    ef-site-header .ef-site-header {
      display: flex;
      align-items: center;
      gap: 16px;
      box-sizing: border-box;
      width: 100%;
      min-width: 0;
      margin: 0;
      padding: 8px 16px;
      background: #ffffff;
      border-bottom: 1px solid #e4d8c6;
      color: #2a1f17;
      font: 14px/1.45 system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
    }
    ef-site-header nav {
      display: flex;
      align-items: center;
      gap: 4px;
      min-width: 0;
      margin: 0;
      padding: 0;
    }
    ef-site-header nav a {
      margin: 0;
      padding: 4px 10px;
      border-radius: 999px;
      color: #6b5e52;
      font-weight: 400;
      text-decoration: none;
      white-space: nowrap;
    }
    ef-site-header nav a:hover { color: #2a1f17; }
    ef-site-header nav a[aria-current="page"] { background: #f5ede0; color: #2a1f17; font-weight: 600; }
    ef-site-header nav a:focus-visible { outline: 2px solid #3a3fa8; outline-offset: 2px; }
    ef-site-header ef-profile { margin-left: auto; }
    @media (max-width: 420px) {
      ef-site-header .ef-site-header { gap: 8px; padding: 8px 12px; }
      ef-site-header nav { gap: 0; }
      ef-site-header nav a { padding: 4px 8px; }
    }
  `;

  class EfSiteHeader extends HTMLElement {
    static get observedAttributes() {
      return ['active'];
    }

    connectedCallback() {
      if (!document.getElementById('ef-site-header-style')) {
        const style = document.createElement('style');
        style.id = 'ef-site-header-style';
        style.textContent = SITE_HEADER_CSS;
        document.head.appendChild(style);
      }
      if (!this.querySelector('header.ef-site-header')) {
        this.innerHTML = `<header class="ef-site-header"><ef-home light></ef-home><nav aria-label="Site"><a
          href="/games/" data-section="games">Games</a><a href="/strelitzia/" data-section="strelitzia">Strelitzia</a><a href="/wordle/" data-section="wordle">Wordle</a></nav><ef-profile
          light></ef-profile></header>`;
      }
      this.markActive();
    }

    attributeChangedCallback() {
      this.markActive();
    }

    markActive() {
      const active = this.getAttribute('active');
      this.querySelectorAll('nav a').forEach((link) => {
        if (link.dataset.section === active) link.setAttribute('aria-current', 'page');
        else link.removeAttribute('aria-current');
      });
    }
  }

  customElements.define('ef-home', EfHome);
  customElements.define('ef-profile', EfProfile);
  customElements.define('ef-site-header', EfSiteHeader);
})();
