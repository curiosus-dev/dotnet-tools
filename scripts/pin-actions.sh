#!/usr/bin/env bash
# Pins `uses: owner/repo@...` in workflow files to the commit SHA of the latest release within the same major version:
#     uses: actions/checkout@v7                     ->  uses: actions/checkout@<sha> # v7.0.1
#     uses: actions/checkout@<old sha> # v7.0.0     ->  uses: actions/checkout@<new sha> # v7.0.1
# Major upgrades stay manual: change the version comment (or tag) to the new major and rerun.
#
# Usage: scripts/pin-actions.sh [workflow files...]   (default: .github/workflows/*.yml sync/.github/workflows/*.yml)
# Requires an authenticated gh CLI.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ $# -eq 0 ]]; then
    set -- .github/workflows/*.yml sync/.github/workflows/*.yml
fi

python3 - "$@" <<'EOF'
import json
import re
import subprocess
import sys

USES = re.compile(r'^(?P<prefix>\s*-?\s*uses:\s*)(?P<action>[\w.-]+/[\w.-]+)(?P<path>/[\w./-]+)?@(?P<ref>[\w.-]+)(?:\s*#\s*(?P<comment>v?[\w.-]+))?\s*$')
cache = {}


def gh(*args):
    return json.loads(subprocess.check_output(['gh', 'api', *args], text=True))


def resolve(action, version):
    major = re.match(r'v?(\d+)', version).group(1)
    key = (action, major)
    if key not in cache:
        releases = gh(f'repos/{action}/releases?per_page=100')
        tags = [r['tag_name'] for r in releases if not r['draft'] and not r['prerelease']]
        tags = [t for t in tags if re.fullmatch(rf'v?{major}(\.\d+)*', t)]
        if not tags:
            sys.exit(f'{action}: no releases for major version {major}')
        tag = max(tags, key=lambda t: [int(x) for x in re.findall(r'\d+', t)])
        ref = gh(f'repos/{action}/git/ref/tags/{tag}')['object']
        # Annotated tags point to a tag object, dereference it to the commit.
        while ref['type'] == 'tag':
            ref = gh(f'repos/{action}/git/tags/{ref["sha"]}')['object']
        cache[key] = (ref['sha'], tag)
    return cache[key]


for path in sys.argv[1:]:
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')

    changed = False
    for i, line in enumerate(lines):
        m = USES.match(line)
        if not m:
            continue
        version = m['comment'] or m['ref']
        if not re.match(r'v?\d', version):
            sys.exit(f'{path}:{i + 1}: cannot infer the version of {m["action"]}, add a "# vX.Y.Z" comment')
        sha, tag = resolve(m['action'], version)
        pinned = f'{m["prefix"]}{m["action"]}{m["path"] or ""}@{sha} # {tag}'
        if pinned != line:
            print(f'{path}:{i + 1}: {m["action"]} -> {tag}')
            lines[i] = pinned
            changed = True

    if changed:
        with open(path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
EOF
