#!/bin/zsh
# Lists localizable strings in the code that the string catalogs don't have yet, with where each is used.
# The compiler extracts every key exactly as SwiftUI and String(localized:) look it up ("Hide %@", "%lld errors").
# Usage: tools/missing-strings.sh          keys missing from either catalog, one per line, then a count
#        tools/missing-strings.sh --json   {"MacMinion": {key: "File.swift:line"}, "MacMinionKit": {...}}
# Exit 1 when any key is missing.
set -euo pipefail
here=${0:A:h:h}
scratch="$HOME/Library/Developer/MacMinion/strings-build"
swift build --package-path "$here" --scratch-path "$scratch" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$scratch/strings" 2>&1 \
  | grep -E "error:" && exit 2
exec python3 -I - "$here" "$scratch" "${1:-}" <<'EOF'
import json, pathlib, sys
here, scratch, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
targets = {"MacMinion": "MacMinion-p.build", "MacMinionKit": "MacMinionKit-t.build"}
missing = {}
for target, build in targets.items():
    catalog = json.load(open(here / f"Sources/{target}/Resources/Localizable.xcstrings", encoding="utf-8"))["strings"]
    found = {}
    for data in scratch.rglob(f"{build}/**/*.stringsdata"):
        doc = json.load(open(data, encoding="utf-8"))
        source = pathlib.Path(doc["source"]).name
        for table, entries in doc.get("tables", {}).items():
            if table != "Localizable":
                continue
            for e in entries:
                found.setdefault(e["key"], f"{source}:{e['location']['startingLine']}")
    missing[target] = {k: v for k, v in sorted(found.items()) if k and k not in catalog}
if mode == "--json":
    print(json.dumps(missing, indent=2, ensure_ascii=False))
else:
    for target, keys in missing.items():
        for k, where in keys.items():
            print(f"{target}\t{where}\t{k!r}")
    print(f"{sum(map(len, missing.values()))} keys missing", file=sys.stderr)
sys.exit(1 if any(missing.values()) else 0)
EOF
