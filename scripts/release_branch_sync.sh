#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <validate|sync> <major.minor.patch>"
  exit 1
}

parse_version() {
  local version="$1"
  if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Invalid version '$version'. Expected format: <major>.<minor>.<patch>"
    exit 1
  fi

  VERSION="$version"
  MAJOR="${BASH_REMATCH[1]}"
  MINOR="${BASH_REMATCH[2]}"
  PATCH="${BASH_REMATCH[3]}"
  MINOR_LINE="${MAJOR}.${MINOR}"
  RELEASE_BRANCH="release-v${MINOR_LINE}"
}

load_repo_state() {
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

  git fetch origin main --tags --quiet

  RELEASE_EXISTS=0
  if git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
    RELEASE_EXISTS=1
    git fetch origin "$RELEASE_BRANCH" --quiet
  fi

  AHEAD_COUNT=0
  if [[ "$RELEASE_EXISTS" -eq 1 ]]; then
    AHEAD_COUNT="$(git rev-list --count origin/main..origin/${RELEASE_BRANCH})"
  fi
}

validate_tagging_policy() {
  if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "$RELEASE_BRANCH" ]]; then
    echo "Error: tags for v${MINOR_LINE}.x must be created from main or ${RELEASE_BRANCH} (current: ${CURRENT_BRANCH})."
    exit 1
  fi

  if [[ "$AHEAD_COUNT" -gt 0 && "$CURRENT_BRANCH" == "main" ]]; then
    echo "Error: ${RELEASE_BRANCH} is ahead of main by ${AHEAD_COUNT} commit(s)."
    echo "Set tags for v${MINOR_LINE}.x from ${RELEASE_BRANCH}, not main."
    exit 1
  fi
}

find_latest_tag_for_minor() {
  local latest_patch
  latest_patch="$(git tag -l | sed -n "s/^v${MINOR_LINE}\.\([0-9][0-9]*\)\(-preprod\)\?$/\1/p" | sort -n | tail -n1)"

  if [[ -z "$latest_patch" ]]; then
    LATEST_TAG=""
    return
  fi

  if git rev-parse --verify --quiet "refs/tags/v${MINOR_LINE}.${latest_patch}" >/dev/null; then
    LATEST_TAG="v${MINOR_LINE}.${latest_patch}"
  else
    LATEST_TAG="v${MINOR_LINE}.${latest_patch}-preprod"
  fi
}

merge_main_into_release() {
  local tmp_dir merged_sha

  echo "Tag created from main; merging origin/main into ${RELEASE_BRANCH}"
  tmp_dir="$(mktemp -d)"

  git worktree add --detach "$tmp_dir" "origin/${RELEASE_BRANCH}" >/dev/null
  if (cd "$tmp_dir" && git merge --no-ff --no-edit origin/main >/dev/null 2>&1); then
    merged_sha="$(git -C "$tmp_dir" rev-parse HEAD)"
    git push origin "${merged_sha}:refs/heads/${RELEASE_BRANCH}"
    git worktree remove --force "$tmp_dir" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
  else
    echo "Automatic merge failed for ${RELEASE_BRANCH} <- main. Resolve manually."
    git worktree remove --force "$tmp_dir" >/dev/null 2>&1 || true
    rm -rf "$tmp_dir"
    exit 1
  fi
}

sync_release_branch() {
  find_latest_tag_for_minor

  if [[ -z "$LATEST_TAG" ]]; then
    echo "No tags found for minor line v${MINOR_LINE}.x. Skipping release branch sync."
    exit 0
  fi

  if [[ "$RELEASE_EXISTS" -eq 1 ]]; then
    echo "Detected tagging branch: ${CURRENT_BRANCH}"
    if [[ "$CURRENT_BRANCH" == "main" ]]; then
      merge_main_into_release
    else
      echo "Tag created from ${RELEASE_BRANCH}; aligning branch to latest tag ${LATEST_TAG}"
      git push --force-with-lease origin "${LATEST_TAG}:refs/heads/${RELEASE_BRANCH}"
    fi
  else
    echo "Creating ${RELEASE_BRANCH} at ${LATEST_TAG}"
    git push -u origin "${LATEST_TAG}:refs/heads/${RELEASE_BRANCH}"
  fi
}

main() {
  if [[ "$#" -ne 2 ]]; then
    usage
  fi

  local mode="$1"
  local version="$2"

  if [[ "$mode" != "validate" && "$mode" != "sync" ]]; then
    usage
  fi

  parse_version "$version"
  load_repo_state
  validate_tagging_policy

  if [[ "$mode" == "sync" ]]; then
    sync_release_branch
  fi
}

main "$@"
