#!/bin/zsh
# Add a photo to the remote Explore feed.
#   ./add-reference.sh <photo> <women|men> [tag ...]
# Tags: fullBody portraits seated couples groups
# Converts to JPEG (long edge ≤ 1600px), copies into images/, appends to manifest.json.
# Then run ./publish.sh to put it live.
set -euo pipefail
cd "${0:A:h}"
[[ $# -ge 2 ]] || { echo "usage: $0 <photo> <women|men> [fullBody|portraits|seated|couples|groups ...]"; exit 1; }
src=$1; subject=$2; shift 2
[[ $subject == women || $subject == men ]] || { echo "subject must be women or men"; exit 1; }
for t in "$@"; do
  [[ $t == (fullBody|portraits|seated|couples|groups) ]] || { echo "unknown tag: $t"; exit 1; }
done
base=${${src:t:r}:l}; base=${base//[^a-z0-9]/-}
id="$base-$(date +%Y%m%d%H%M%S)"
out="images/$id.jpg"
sips -s format jpeg -s formatOptions 85 -Z 1600 "$src" --out "$out" >/dev/null
python3 - "$id" "$out" "$subject" "$@" <<'PY'
import json, sys
id, image, subject, *tags = sys.argv[1:]
m = json.load(open("manifest.json"))
m["references"].insert(0, {"id": id, "image": image, "subject": subject, "tags": tags})
json.dump(m, open("manifest.json", "w"), indent=2)
open("manifest.json", "a").write("\n")
PY
echo "Added $id ($subject${*:+, $*}). Run ./publish.sh to go live."
