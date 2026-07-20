What changes and why
There are two bugs in sync_release_branch() that violate the "release branches never move backwards" rule, plus an unnecessary merge function.
Bug 1: merge_main_into_release() creates a commit ahead of main
Lines 85–103. When you tag from main and the release branch exists, this function does a --no-ff merge of origin/main into the release branch. That merge commit makes the release branch one commit ahead of main, which then blocks all future tags from main for that minor line.
Fix: Replace it with a simple force-push of HEAD to the release branch. Since validation already guarantees the release branch is not ahead of main (or doesn't exist), this is safe — it just snaps the release branch to main's tip without creating a merge commit.
Bug 2: sync_release_branch() moves the release branch backwards
Lines 125–126. When you tag from the release branch itself, the sync force-pushes the release branch back to LATEST_TAG. If you've made commits on the release branch beyond the previous tag, those get wiped.
Fix: When tagging from the release branch, do nothing to the branch. The user controls the branch directly via commits.
Changes to scripts/release_branch_sync.sh
1. Delete merge_main_into_release() (lines 85–103) — no longer needed.
2. Rewrite sync_release_branch() (lines 105–132) with this logic:
sync_release_branch():
  find_latest_tag_for_minor

  if no existing tags for this minor line:
    if release branch doesn't exist:
      → create it from HEAD (existing line 115)
    elif on main:
      → force-push HEAD to release branch (reset, not merge)
    elif on release branch:
      → do nothing (branch is being developed directly)
    exit 0

  if release branch exists:
    if on main:
      → force-push HEAD to release branch (reset, not merge)
    elif on release branch:
      → do nothing (user commits directly to this branch)
  else:
    → create release branch from HEAD (existing line 130)
No changes to validate_tagging_policy() — the blocking rule is preserved as-is.
No changes to load_repo_state() — it still fetches everything needed for validation.
What this enables
Scenario	Before	After
Tag from main, release branch behind main	Merges main → release branch, creates merge commit, future tags from main blocked	Resets release branch to main's tip, no extra commit
Tag from main, release branch ahead of main	Blocked (correct)	Blocked (correct, unchanged)
Tag from release branch	Force-pushes branch back to previous latest tag (moves backwards)	No-op on branch, tag points at current HEAD