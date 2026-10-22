# Plan: Wordle solver, part 2: tile-grid page, API and Docker image (Wordle repo)
**Status:** ❌ Not started
**Risk:** low (Wordle repo only; a merge there deploys nothing. The user tests the page on preprod in part 3)
**Depends on:** wordle-solver-1-core

## Goal
`docker run -p 8000:8000 wordle` serves the solver at `/wordle/`: a Wordle-style 6×5 grid where you type each guess and
click tiles to set their colors (no clicks or three clicks = black, one = yellow, two = green, cycling), press Submit,
and below the grid see every remaining word with its probability, E(|v|) and weighted E(|v|).

## Where the work happens (cross-repo)
Same as part 1: fresh clone of **SiddharthEngineer/Wordle**, branch `agent/wordle-solver-2-web`, PR to `main`,
`gh pr merge --auto --merge` (or merge on green CI). If the token can't push to Wordle, mark tasks ⏸.
The engineerfamily side only updates Status lines and the ROADMAP row.

## Context
- Wordle `solver.py` (part 1): `WORDS`, `parse_pattern`, `filter_candidates`, `probabilities`, `expected_sizes`, `solve`.
- engineerfamily `services/shared/README.md`: header contract. Since E3 (site-header-bar) every page except the Strelitzia
  dashboard loads `/shared/site-header.js` and puts `<ef-site-header>` first in `<body>`, with no header CSS of its own. nginx serves `/shared/` on the same host, so it
  works on preprod/prod; locally the elements just don't render. Don't restyle them.
- engineerfamily `services/strelitzia/style.css:1-10`: the "Sunrise" color tokens (light + dark) to copy.
- engineerfamily `services/strelitzia/index.html`: head markup and the brand row above the `h1` to mirror.
- nginx (part 3) proxies `/wordle/` to this container **without stripping the prefix**, so every route lives under
  `/wordle`. The upstream sees Cloudflare → nginx; the app needs no client IP.
- Opening position (no rows): E(|v|) over the full list is ~170M pairs, too slow per request. Precompute it once.

## Tasks
### Task 1: Opening table and API
**Runs:** unattended
**Files:** scripts/precompute.py (new), data/opening.csv (new, generated), web/app.py (new), requirements.txt (modify)
**What:**
- `scripts/precompute.py` writes `data/opening.csv` (`word,probability,ev,wev`, every word, rounded to 6 decimals)
  from `solver.solve([])` with no cap. Commit the output.
- `web/app.py`, FastAPI, all routes under `BASE = os.environ.get("WORDLE_BASE_PATH", "/wordle")`:
  - `GET {BASE}` → 307 to `{BASE}/`; `GET {BASE}/` → `web/static/index.html`; static files at `{BASE}/static/`.
  - `GET {BASE}/api/health` → `{"ok": true, "words": 12971}`.
  - `GET {BASE}/api/words` → JSON list of all words (`Cache-Control: public, max-age=86400`), for client-side checks.
  - `POST {BASE}/api/solve`, body `{"rows": [{"guess": "crane", "pattern": "bygbb"}, …]}`, 0–6 rows. Guess is
    lowercased and must be in `WORDS`; pattern must parse. Bad input → 422 `{"detail": "Row 2: 'xxxxx' is not in the word list"}`.
    No rows → the opening table. Otherwise filter, then score E columns only when remaining ≤ `WORDLE_EV_CAP`
    (env, default 3000). Response: `{"remaining": n, "capped": bool, "cap": 3000, "words": [{"word", "probability",
    "ev", "wev"}, …]}`, all remaining words sorted by probability desc, `ev`/`wev` null when capped.
  - Load `WORDS`, the opening table and frequencies once at startup.
- `requirements.txt` adds pinned `fastapi`, `uvicorn[standard]`; pytest's `httpx` goes in CI only.
**Validate:** `python scripts/precompute.py && head -2 data/opening.csv` → header + one row;
`uvicorn web.app:app --port 8000 &` then `curl -s localhost:8000/wordle/api/health` → `{"ok":true,"words":12971}`.
**Status:** ❌

### Task 2: The page
**Runs:** unattended
**Files:** web/static/index.html (new, markup + CSS), web/static/app.js (new, vanilla JS, no build step)
**What:**
- Header per the shared contract: `<ef-site-header>` first in `<body>`; then a page row with the brand "Wordle solver" and a GitHub link.
  Sunrise tokens for the page; tiles use Wordle colors: black `#3a3a3c`, yellow `#c9b458`, green `#6aaa64`, white letters.
- Grid: 6 rows × 5 tiles. The active row takes letters from the physical keyboard and an on-screen QWERTY keyboard
  (Enter, ⌫). A tile with a letter is a `<button>`; each click cycles black → yellow → green → black (state = clicks mod 3,
  starts black). `aria-label` like "Letter C, position 1, yellow". Tiles in submitted rows stay clickable.
- Submit (button or Enter) needs 5 letters and a word from `/api/words`; otherwise the row shakes and shows
  "Not in word list". It POSTs all submitted rows, then unlocks the next row. Changing a submitted row's colors relabels
  the button "Update"; pressing it re-solves. Backspace on an empty active row reopens the last submitted row.
  A Reset button clears everything. On-screen keys show the best color seen per letter (green > yellow > black).
- State (rows, colors) saved in `localStorage` key `wordle-solver:v1`; every read/write in try/catch; reload restores it.
- Results under the grid: "N words left", then one table: Word, Probability (%), E(|v|), Weighted E(|v|). Header
  clicks sort (default probability desc; E columns ascending, lower is better). First 50 rows, then "Show all (N)".
  Short legend explaining the three columns. When `capped`: "Too many words left to score guesses (> 3,000); make
  another guess". 0 left: "No words match. Check your tile colors." Fetch errors show a retry message.
- Works at 390 px wide with no horizontal scroll (table scrolls inside its own box), light and dark mode.
**Validate:** `node --check web/static/app.js` → no output; `curl -s localhost:8000/wordle/ | grep -c 'id="grid"'` → `1`.
**Status:** ❌

### Task 3: Docker image, tests, CI, docs
**Runs:** unattended
**Files:** Dockerfile (new), .dockerignore (new), tests/test_api.py (new), .github/workflows/ci.yml (modify), README.md (modify)
**What:**
- `Dockerfile`: `python:3.12-slim`, `pip install --no-cache-dir -r requirements.txt`, copy `solver.py web/ data/ input/`,
  non-root user, `EXPOSE 8000`, `CMD ["uvicorn", "web.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]`,
  `HEALTHCHECK` via `python -c` urllib on `/wordle/api/health`. `.dockerignore`: `.git`, `env/`, `*.ipynb`, `output/`, caches.
- `tests/test_api.py` (FastAPI TestClient): health; `/wordle/` returns HTML; no rows → 12,971 words; one row
  (`crane`, pattern of `crane` vs `abide`) keeps `abide`; probabilities sum to ~1; 422 for an unknown word, a bad pattern,
  7 rows; `capped` true with `WORDLE_EV_CAP=10` and `ev` null; first 3 rows of `data/opening.csv` match
  `expected_sizes` for those words.
- CI: install `httpx` too; add job `docker` that runs `docker build -t wordle .`, starts it, and curls the health URL.
- README: what the site does, run locally (`uvicorn web.app:app`, then `http://localhost:8000/wordle/`), Docker run, CLI.
**Validate:** `python -m pytest -q` → pass; `docker build -t wordle . && docker run -d -p 8000:8000 wordle` then
`curl -s localhost:8000/wordle/api/health` → `{"ok":true,"words":12971}`; PR checks `test` and `docker` green.
**Status:** ❌

## Validation
- `python -m pytest -q` passes; the Docker health check returns `{"ok":true,"words":12971}`.
- `time curl -s -X POST localhost:8000/wordle/api/solve -H 'content-type: application/json'
  -d '{"rows":[{"guess":"fuzzy","pattern":"bbbbb"}]}' -o /dev/null` → under 3 s (worst-case first guess with the cap).
- `scripts/validate.sh` passes in the engineerfamily worktree.

## Human test steps (preprod)
None here: the page reaches preprod in part 3, whose steps cover the UI.

## Decisions
1. FastAPI container serving its own static page, mirroring how Strelitzia's dashboard is built and proxied.
2. Every route lives under `/wordle` (env-overridable) so nginx needs no rewrite.
3. The API returns all remaining words; the page shows 50 and expands, so sorting needs no extra requests.
4. The opening table is committed, not computed at build or start, so the image builds fast and starts instantly.
5. E columns are skipped above 3,000 remaining words to keep a request around a second; probability always shows.
6. No accounts or server-side state; progress lives in the visitor's browser.
