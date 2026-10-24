#!/usr/bin/env bash
# Checks App/Sources/Localizable.xcstrings against the strings the app's
# code uses, and that it and InfoPlist.xcstrings are translated into every
# language below.
# Run scripts/build-app.sh first: the build extracts the strings.
#
#   scripts/check-localizations.sh           # fail on a mismatch
#   scripts/check-localizations.sh --update  # bring the catalog in step
set -euo pipefail

languages=(ja)
root=$(cd "$(dirname "$0")/.." && pwd)
catalog="$root/App/Sources/Localizable.xcstrings"
objects="$root/target/DerivedData/Build/Intermediates.noindex/Trackdo.build/Debug-iphonesimulator/Trackdo.build/Objects-normal/arm64"

stringsdata=()
for file in "$objects"/*.stringsdata; do
  [[ "$(basename "$file")" == ExtractedAppShortcutsMetadata.stringsdata ]] || stringsdata+=(--stringsdata "$file")
done
if [[ ${#stringsdata[@]} -eq 0 ]]; then
  echo "No extracted strings in $objects; run scripts/build-app.sh first." >&2
  exit 1
fi

synced=$(mktemp -d)/Localizable.xcstrings
trap 'rm -rf "$(dirname "$synced")"' EXIT
cp "$catalog" "$synced"
xcrun xcstringstool sync "$synced" "${stringsdata[@]}"
# Strings the code no longer uses are only marked stale; drop them, and
# write the file the way Xcode does so an update leaves no format churn.
python3 -I - "$synced" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    catalog = json.load(f)
catalog["strings"] = {
    key: value for key, value in catalog["strings"].items()
    if value.get("extractionState") != "stale"
}
with open(path, "w", encoding="utf-8") as f:
    f.write(json.dumps(catalog, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n")
EOF

if [[ "${1:-}" == --update ]]; then
  cp "$synced" "$catalog"
elif ! diff -q <(jq -S . "$catalog") <(jq -S . "$synced") >/dev/null; then
  echo "Localizable.xcstrings is out of step with the code; run $0 --update." >&2
  diff <(jq -S '.strings | keys' "$catalog") <(jq -S '.strings | keys' "$synced") >&2 || true
  exit 1
fi

status=0
for file in "$catalog" "$root/App/Sources/InfoPlist.xcstrings"; do
  for language in "${languages[@]}"; do
    missing=$(jq -r --arg l "$language" '
      .strings | to_entries[]
      | select(.value.shouldTranslate != false)
      | select(.value.localizations[$l].stringUnit.state != "translated")
      | .key' "$file")
    if [[ -n "$missing" ]]; then
      echo "$(basename "$file") is not translated into $language:" >&2
      printf '  %s\n' "$missing" >&2
      status=1
    fi
  done
done
exit $status
