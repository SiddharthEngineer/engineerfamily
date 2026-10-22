# Plan: Wordle solver, part 1: fast solver core, tests and CI (Wordle repo)
**Status:** ✅ 2026-10-22, all tasks done; Wordle PR #1 has CI `test` green and is waiting to be merged (the agent's `gh pr merge` was denied by permissions)
**Risk:** low (Wordle repo only; a merge there deploys nothing, prod moves only with `make wordle-deploy`)

## Goal
The Wordle repo gets a fast, tested solver module that the web app (part 2) can call: filter the word list by
guess/color rows, give each remaining word a probability, and score each remaining word with plain and
frequency-weighted E(|v|). The CLI (`python run.py`) keeps working. CI runs the tests on every PR.

## Where the work happens (cross-repo)
- All code goes to **SiddharthEngineer/Wordle** (default branch `main`). Clone it fresh next to the engineerfamily
  worktree (never under `/srv`, never inside the engineerfamily worktree), branch `agent/wordle-solver-1-core`,
  push, open a PR to `main`, then `gh pr merge --auto --merge`. If auto-merge isn't enabled on the repo, wait for green CI
  and merge with `gh pr merge --merge`. If the token can't push to Wordle, stop and mark the tasks ⏸ (token access).
- The engineerfamily side of this run only updates this plan's Status lines and the ROADMAP row.

## Context (Wordle repo)
- `predictor.py:51-75`: `calculate_rule(guess, solution)`, the reference coloring, including duplicate letters
  (greens first, then yellows while the solution still has unused copies). The new code must match it exactly.
- `predictor.py:77-84`: `update_valid` keeps words whose rule equals the given rule.
- `predictor.py:86-91`: `get_frequencies` uses `zipf_frequency(w, 'en')`.
- `predictor.py:113-152`: `mean_size` + `expected_valid_size(valid, word_freq)`: per guess, bins over 243 patterns,
  each bin is a count (or the sum of the solutions' zipf frequency when `word_freq`), result = mean of non-zero bins.
  Column names `E( |v| )` and `E[ w( |v| ) ]`. Pure Python, O(n²); ~170M pairs on the full list, so it must be vectorized.
- `predictor.py:24`, `runtime.py:27,33`: `np.loadtxt("input/...")` paths are relative to the cwd (breaks when run elsewhere).
- `output/expected-valid-size.csv:1-3`: plain E(|v|) for every word against the full list (`tares` = 61.18867924528302).
  Use it as a regression fixture.
- `run.py:52-55,108-109`: the CLI uses `Runtime` for a time estimate; runtime.py pulls in scikit-learn.
- `requirements.txt`: a Jupyter/matplotlib/sklearn dev freeze (56 pins). `test.ipynb` is kept as is (experiments).
- No tests, no CI, no AGENTS.md today. `.DS_Store` is committed.

## Tasks
### Task 1: Vectorized solver module
**Runs:** unattended
**Files:** solver.py (new), predictor.py (modify), run.py (modify), runtime.py (delete)
**What:** `solver.py`, numpy only plus wordfreq:
- `WORDS: np.ndarray` (str, lowercase), loaded from `Path(__file__).parent / "input/valid-wordle-words.txt"`.
- Pattern code: digit per position, 0 black / 1 yellow / 2 green, value `sum(d_i * 3**i)` (0–242).
  `pattern_string(code) -> str` and `parse_pattern("bygbg") -> int` (raise `ValueError` on anything but 5 of b/y/g).
- `pattern(guess, solution) -> int` and `pattern_matrix(guesses, solutions) -> np.ndarray[uint8]` shape (G, S),
  vectorized over letter-code arrays, same duplicate-letter rules as `calculate_rule`.
- `filter_candidates(rows: list[tuple[str, str]], words=WORDS) -> np.ndarray`: rows are (guess, "bygbg").
- `probabilities(words) -> np.ndarray`: `word_frequency(w, "en")` with a floor of 1e-9, normalized to sum to 1.
- `expected_sizes(guesses, candidates, weighted=False, chunk=512) -> np.ndarray[float]`: same definition as
  `expected_valid_size` (mean of non-zero bins; weighted bins sum the candidates' `zipf_frequency`), computed with
  `np.bincount` per guess over chunks of guesses so memory stays bounded.
- `solve(rows) -> list[dict]` with keys `word, probability, ev, wev`, sorted by probability descending
  (`ev`/`wev` scored with guesses = candidates).
`predictor.py`: load paths relative to the file; `update_valid`/`expected_valid_size` delegate to `solver`, keeping their
DataFrame output and column names. `run.py`: drop `Runtime` and the time estimate line; delete `runtime.py`.
**Validate:** `python -c "import solver; print(len(solver.WORDS), solver.pattern_string(solver.pattern('speed','abide')))"`
→ `12971 bbyby`; `echo q | python run.py` exits 0.
**Status:** ✅ 2026-10-22, Wordle 77354b4 (12,972 words: the plan's 12,971 came from `wc -l`, and the file has no trailing newline)

### Task 2: Tests
**Runs:** unattended
**Files:** tests/test_solver.py (new)
**What:** pytest. A copy of the original `calculate_rule` logic inside the test file as the reference. Cases:
1. Duplicate letters, hand-checked: (`speed`,`abide`)→`bbyby`, (`geese`,`these`)→`bbggg`, (`llama`,`hello`)→`yybbb`,
   (`crane`,`crane`)→`ggggg`, (`eerie`,`there`)→`ybybg` (checked against the original code).
2. `pattern` equals the reference on 2,000 random (guess, solution) pairs (seeded).
3. `pattern_matrix` equals `pattern` element-wise on a 50×60 sample.
4. `filter_candidates` keeps the solution and every kept word reproduces each row's pattern.
5. `expected_sizes(["tares","teras"], WORDS)` ≈ the values in `output/expected-valid-size.csv` (rel 1e-9).
6. `probabilities` sums to 1 and has no zeros; `solve([])` returns 12,971 rows.
7. `parse_pattern` rejects `"bygb"`, `"bygbx"`.
**Validate:** `python -m pytest -q` → all pass, under 60 s.
**Status:** ✅ 2026-10-22, Wordle 0d63570 (13 tests; 17 after the review fixes in a3eca86, about 16 s)

### Task 3: Dependencies, CI, agent docs, cleanup
**Runs:** unattended
**Files:** requirements.txt (modify), .github/workflows/ci.yml (new), AGENTS.md (new), CLAUDE.md (new), .gitignore (modify),
.DS_Store (delete)
**What:** `requirements.txt` = runtime only, pinned: `numpy`, `pandas`, `wordfreq` (keep current versions; Python 3.12).
CI: on `pull_request` and push to `main`, `ubuntu-latest`, Python 3.12, `pip install -r requirements.txt pytest`,
`python -m pytest -q`; job name `test` (part 2 adds a Docker build job). `.gitignore` adds `.DS_Store`,
`__pycache__/`, `.pytest_cache/`. `AGENTS.md` (short, like engineerfamily's): what the repo is, file map, how to run
the CLI and tests, that it's deployed by the engineerfamily repo (`/wordle/`), never commit secrets. `CLAUDE.md` = `@AGENTS.md`.
**Validate:** `python -m pytest -q` passes in a fresh venv from `requirements.txt` + pytest; the PR's C**Status:** ✅ 2026-10-22, Wordle a3eca86 + 5202ede (ci.yml pushed after the token got the `workflow` scope, user answer A); CI `test` green on Wordle#1he file is in the PR body

## Validation
- `python -m pytest -q` passes locally and in the PR's CI.
- `scripts/validate.sh` passes in the engineerfamily worktree (only plan/ROADMAP edits there).

## Human test steps (preprod)
None (low risk; nothing deploys until part 3).

## Decisions
1. Pattern digits 0/1/2 = black/yellow/green; the old `Hint` enum order stays only inside `predictor.py`.
2. Probability is normalized linear `word_frequency` (not zipf), floored so unseen words stay possible.
3. Suggested guesses are scored over the remaining words only (`valid=True`), as the user chose.
4. runtime.py goes (the web app caps work instead of estimating time); its two small training-data files stay to keep this plan within the file budget.
