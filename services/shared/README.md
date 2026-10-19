# services/shared: the site header contract

nginx serves this folder at `/shared/` (`Cache-Control: no-cache`, so a change shows on the next load). It holds
`site-header.js`, which defines two custom elements used by every engineerfamily.net page: the Vite site, Strelitzia's
static pages and the Strelitzia dashboard.

```html
<script src="/shared/site-header.js" defer></script>

<header>
  <ef-home></ef-home>          <!-- first: the engineerfamily home link, always to / -->
  …the app's own brand and nav…
  <ef-profile></ef-profile>    <!-- last: Sign in, or initials + menu + Sign out -->
</header>
```

- `<ef-home>`: the engineerfamily wordmark, linking to `/`. The first thing in every header. With `compact`, it shows
  only the dot at phone width (≤560 px), for headers that need the room (Strelitzia's static pages).
- `<ef-profile next="/path">`: asks `/auth/me` once per page (see `services/app/auth.py`). Signed out: a **Sign in**
  button to `/auth/login?next=<next>` (`next` defaults to the current path and query). Signed in: a round initials
  button (no Google picture, so no third-party image loads) that opens a menu with the name, email and a Strelitzia
  dashboard link, then a **Sign out** button (`POST /auth/logout`, then reload). Enter/Space opens the menu, Escape
  closes it and returns focus. Renders nothing while sign-in is off (`enabled: false`). The last thing in every header.

Rules for pages:
- Don't restyle them. Both use Shadow DOM with their own fixed fonts, sizes and colors (light and dark through
  `prefers-color-scheme`) and their own background, so they look the same on every theme. Pages only place them:
  the header is a flex row with `<ef-home>` first and `<ef-profile>` last (push it right with `margin-left: auto`).
- At phone width the nav between them may wrap or scroll, but `<ef-home>` stays first and `<ef-profile>` last on the top row.
- The script has no build step and no dependencies, and loading it twice is harmless.
