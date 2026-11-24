#!/bin/zsh
# Retire a photo from Explore: ./remove-reference.sh <id>
# Apps drop it on next launch (users who favorited it keep it).
set -euo pipefail
cd "${0:A:h}"
[[ $# -eq 1 ]] || { echo "usage: $0 <id>"; exit 1; }
python3 - "$1" <<'PY'
import json, os, sys
id = sys.argv[1]
m = json.load(open("manifest.json"))
hit = [r for r in m["references"] if r["id"] == id]
if not hit: sys.exit(f"no entry {id}")
m["references"] = [r for r in m["references"] if r["id"] != id]
json.dump(m, open("manifest.json", "w"), indent=2)
open("manifest.json", "a").write("\n")
if os.path.exists(hit[0]["image"]): os.remove(hit[0]["image"])
print(f"Removed {id}. Run ./publish.sh.")
PY
