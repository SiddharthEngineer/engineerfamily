// engineerfamily site header pieces, the same on every page (see README.md here):
//   <ef-home [compact]>       the engineerfamily home link, first thing in the header (compact: only the dot at ≤560px)
//   <ef-profile next="/path"> sign in, or initials + menu + Sign out, last thing in the header
// Shadow DOM with their own fixed styles, so no page theme leaks in. No build step; safe to load twice.
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
      :host {
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
      root.innerHTML = `<style>${BASE_CSS}
        .home { font-weight: 700; font-size: 15px; letter-spacing: 0.01em; }
        .dot { width: 8px; height: 8px; margin-right: 8px; border-radius: 50%; background: var(--ef-accent); }
        @media (max-width: 560px) {
          :host([compact]) .home { width: 36px; padding: 0; }
          :host([compact]) .dot { margin-right: 0; }
          :host([compact]) .label { display: none; }
        }
      </style><a class="pill home" href="/" aria-label="engineerfamily home"><span class="dot" aria-hidden="true"></span><span
        class="label">engineerfamily</span></a>`;
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
      fetchMe().then((me) => this.render(me));
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
      // Sign-in off (or /auth/me unreachable): render nothing.
      if (!me || !me.enabled) {
        root.innerHTML = '';
        return;
      }
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
        .menu a { display: block; padding: 8px; margin: 0 -8px; border-radius: 8px; color: var(--ef-fg); text-decoration: none; }
        .menu a:hover { background: var(--ef-hover); }
      </style>`;
      if (!me.signed_in) {
        root.innerHTML = `${css}<a class="pill" href="/auth/login">Sign in</a>`;
        const link = root.querySelector('a');
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
          <a href="/strelitzia/dashboard/">Strelitzia dashboard</a>
        </div>
        <button class="pill signout" type="button">Sign out</button>`;
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
    }

    openMenu() {
      this.menu.hidden = false;
      this.button.setAttribute('aria-expanded', 'true');
      document.addEventListener('click', this.onDocClick);
      this.menu.querySelector('a').focus();
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

  customElements.define('ef-home', EfHome);
  customElements.define('ef-profile', EfProfile);
})();
