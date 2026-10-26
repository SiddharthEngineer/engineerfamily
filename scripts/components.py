#!/usr/bin/env python3
"""Read components.toml, the tags of the child repos every engineerfamily deploy builds.

  scripts/components.py [--file F] list              # name<TAB>repo<TAB>tag<TAB>service, one line per component
  scripts/components.py [--file F] get <name> <key>  # one value
  scripts/components.py [--file F] check [--remote]  # one line per problem, exit 1 if any; --remote: tags exist on GitHub

Standard library only (Python 3.11+): the root deploy script runs it on the VPS host.
"""
import argparse
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path

DEFAULT_FILE = Path(__file__).resolve().parent.parent / "components.toml"
TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")
REQUIRED = ("repo", "tag", "service")
KEYS = set(REQUIRED) | {"hold"}


def load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def problems(data):
    out = []
    for name, comp in data.items():
        if not NAME_RE.match(name):
            out.append(f"{name}: bad name (want [a-z][a-z0-9-]*)")
        if not isinstance(comp, dict):
            out.append(f"{name}: not a table")
            continue
        for key in sorted(set(comp) - KEYS):
            out.append(f"{name}: unknown key {key!r}")
        for key in REQUIRED:
            if key not in comp:
                out.append(f"{name}: missing {key!r}")
            elif not isinstance(comp[key], str) or not comp[key]:
                out.append(f"{name}: {key!r} must be a non-empty string")
        tag = comp.get("tag")
        if isinstance(tag, str) and tag and not TAG_RE.match(tag):
            out.append(f"{name}: bad tag {tag!r} (want vX.Y.Z)")
    return out


def remote_problems(data):
    out = []
    for name, comp in data.items():
        url = f"https://github.com/{comp['repo']}"
        try:
            r = subprocess.run(["git", "ls-remote", "--tags", url, f"refs/tags/{comp['tag']}"],
                               capture_output=True, text=True, timeout=60,
                               env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})
        except subprocess.TimeoutExpired:
            out.append(f"{name}: git ls-remote {url} timed out")
            continue
        if r.returncode != 0:
            err = (r.stderr.strip().splitlines() or ["?"])[-1]
            out.append(f"{name}: git ls-remote {url} failed: {err}")
        elif not r.stdout.strip():
            out.append(f"{name}: tag {comp['tag']} not found in {comp['repo']}")
    return out


def main(argv=None):
    p = argparse.ArgumentParser(description="Read and check components.toml")
    p.add_argument("--file", default=DEFAULT_FILE)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    g = sub.add_parser("get")
    g.add_argument("name")
    g.add_argument("key")
    c = sub.add_parser("check")
    c.add_argument("--remote", action="store_true")
    a = p.parse_args(argv)

    try:
        data = load(a.file)
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"{a.file}: {e}", file=sys.stderr)
        return 1

    if a.cmd == "check":
        found = problems(data)
        if not found and a.remote:
            found = remote_problems(data)
        for line in found:
            print(line)
        return 1 if found else 0

    found = problems(data)
    if found:
        for line in found:
            print(line, file=sys.stderr)
        return 1
    if a.cmd == "list":
        for name, comp in data.items():
            print("\t".join([name, comp["repo"], comp["tag"], comp["service"]]))
        return 0
    value = data.get(a.name, {}).get(a.key)
    if value is None:
        print(f"no {a.key!r} for {a.name!r}", file=sys.stderr)
        return 1
    print(value)
    return 0


if __name__ == "__main__":
    sys.exit(main())
