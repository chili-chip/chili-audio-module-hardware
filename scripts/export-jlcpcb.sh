#!/usr/bin/env bash
# Export JLCPCB fabrication + assembly files: gerber/drill zip, BOM and CPL.
# Usage: scripts/export-jlcpcb.sh [VERSION] [OUTPUT_DIR]
set -euo pipefail

NAME=chili-audio-module-hardware
PREFIX=chili-audio-module
VERSION=${1:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}
OUT=${2:-production}
PCB=$NAME.kicad_pcb
SCH=$NAME.kicad_sch

cd "$(dirname "$0")/.."
rm -rf "$OUT"
mkdir -p "$OUT/gerbers"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Gerbers (Protel extensions) + Excellon drill in mm.
kicad-cli pcb export gerbers --subtract-soldermask \
  --layers F.Cu,B.Cu,F.Paste,B.Paste,F.SilkS,B.SilkS,F.Mask,B.Mask,Edge.Cuts \
  -o "$OUT/gerbers/" "$PCB"
kicad-cli pcb export drill --format excellon --excellon-units mm \
  --generate-map --map-format gerberx2 -o "$OUT/gerbers/" "$PCB"
(cd "$OUT/gerbers" && zip -q "../$PREFIX-$VERSION-gerbers.zip" ./*)
rm -rf "$OUT/gerbers"

# BOM in JLCPCB column format, grouped by value/footprint/LCSC part.
kicad-cli sch export bom \
  --fields 'Value,Reference,${FOOTPRINT_NAME},LCSC' \
  --labels 'Comment,Designator,Footprint,LCSC Part #' \
  --group-by 'Value,${FOOTPRINT_NAME},LCSC' \
  --exclude-dnp -o "$OUT/$PREFIX-$VERSION-bom.csv" "$SCH"

# CPL: KiCad position file converted to JLCPCB column names.
kicad-cli pcb export pos --format csv --units mm --side front --exclude-dnp \
  -o "$TMP/pos.csv" "$PCB"
python3 - "$TMP/pos.csv" "$OUT/$PREFIX-$VERSION-cpl.csv" <<'EOF'
import csv, sys
with open(sys.argv[1]) as src, open(sys.argv[2], "w", newline="") as dst:
    w = csv.writer(dst)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    for r in csv.DictReader(src):
        w.writerow([r["Ref"], f'{float(r["PosX"]):.4f}mm', f'{float(r["PosY"]):.4f}mm',
                    "Top" if r["Side"] == "top" else "Bottom", f'{float(r["Rot"]) % 360:g}'])
EOF

ls -1 "$OUT"
