#!/bin/zsh
# Push manifest.json + images/ to the GitHub Pages repo the app reads from
# (https://anikam13.github.io/frameshift-explore/manifest.json).
# Live within a minute or two; apps pick it up on their next launch.
set -euo pipefail
cd "${0:A:h}"
REPO=${FEED_REPO:-anikam13/frameshift-explore}
python3 -c 'import json; m=json.load(open("manifest.json")); assert m["version"]==1; ids=[r["id"] for r in m["references"]]; assert len(ids)==len(set(ids)), "duplicate ids"; import os; [os.stat(r["image"]) for r in m["references"]]'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gh repo clone "$REPO" "$tmp/site" -- --depth 1 --quiet
rsync -a --delete --exclude .git --exclude '*.sh' --exclude README.md ./ "$tmp/site/"
touch "$tmp/site/.nojekyll"
cd "$tmp/site"
git add -A
if git diff --cached --quiet; then echo "Nothing to publish."; exit 0; fi
git commit -qm "Update Explore feed ($(date +%Y-%m-%d))"
git push -q
echo "Published to https://${REPO%%/*}.github.io/${REPO#*/}/manifest.json"
