# services/shared: the site header contract

nginx serves this folder at `/shared/` (`Cache-Control: no-cache`, so a change shows on the next load). It holds
`site-header.js`, which defines three custom elements: `<ef-site-header>` for every engineerfamily.net page except the
Strelitzia dashboard, and the two pieces it is made of, `<ef-home>` and `<ef-profile>`, which the dashboard also uses
in its own top bar.

Every page except the dashboard: the header is the first child of `<body>`, and the page adds no header CSS of its own.

```html
<script src="/shared/site-header.js" defer></script>
<body>
  <ef-site-header active="games"></ef-site-header>   <!-- active: games | strelitzia | (none) -->
  …the page…
</body>
```

The Strelitzia dashboard keeps its own bar and links, and places the pieces:

```html
<header>
  <ef-home></ef-home>          <!-- first: the home icon, always to / -->
  …the app's own brand and nav…
  <ef-profile></ef-profile>    <!-- last: Sign in, or initials + menu -->
</header>
```

- `<ef-site-header active="games|strelitzia|wordle">`: a solid, full-width bar like the dashboard's top bar (white,
  1 px rule under it, `8px 16px` padding, about 53 px tall). It is not sticky: it scrolls away with the page. It holds
  `<ef-home light>`, a `nav` with **Games** (`/games/`), **Strelitzia** (`/strelitzia/`) and **Wordle** (`/wordle/`) in the dashboard's link
  style, and `<ef-profile light>` pushed right. The link named by `active` gets `aria-current="page"` and the
  highlight. Light DOM (so `ef-site-header header nav` can be queried) styled by one `<style>` it adds to `<head>`, with
  every rule scoped under `ef-site-header`. Always light, even in OS dark mode. Stays one row at phone width.
- `<ef-home>`: a 36 px round button with a house icon, linking to `/` ("engineerfamily home"). The first thing in every
  header. `compact` is still accepted and does nothing.
- `<ef-profile next="/path">`: asks `/auth/me` once per page (see `services/app/auth.py`). Signed out: a **Sign in**
  button to `/auth/login?next=<next>` (`next` defaults to the current path and query). Signed in: a round initials
  button (no Google picture, so no third-party image loads) that opens a menu with the name, email, a Strelitzia
  dashboard link (only when `/auth/me`'s `pages` has `strelitzia`; always, if `pages` is missing), **Users** (`/users/`,
  only when `admin`) and **Sign out** (`POST /auth/logout`, then reload). There is no Sign out outside the menu. Enter/Space opens the menu and focuses its first item, Escape closes
  it and returns focus, focus leaving the menu closes it. Renders nothing while sign-in is off (`enabled: false`).
- `light` on `<ef-home>` / `<ef-profile>`: ignore `prefers-color-scheme: dark` and stay light. `<ef-site-header>` sets it.

Rules for pages:
- Don't restyle the elements. `<ef-home>` and `<ef-profile>` use Shadow DOM with their own fixed fonts, sizes and
  colors, so they look the same on every theme.
- The script has no build step and no dependencies, and loading it twice is harmless.
