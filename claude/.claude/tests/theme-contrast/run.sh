#!/usr/bin/env bash
# Theme contrast test.
#
# Asserts every foreground token in the custom Catppuccin theme clears the
# WCAG AA floor of 4.5:1 against the theme's own background. The 4.5 figure
# is WCAG's allowance for 20/40 visual acuity; 7.0 (AAA) corresponds to 20/80.
#
# Exits 0 if all pass, 1 on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="$HERE/../../themes/catppuccin.json"

command -v node >/dev/null 2>&1 || { echo "node required" >&2; exit 2; }
[[ -f "$THEME" ]] || { echo "missing $THEME" >&2; exit 2; }

THEME="$THEME" node <<'NODE'
const fs = require('fs');
const o = JSON.parse(fs.readFileSync(process.env.THEME, 'utf8')).overrides;
const bg = o.background;

// WCAG 2.2 relative luminance, then the contrast ratio of two colours.
function lum(hex) {
  const n = parseInt(hex.slice(1), 16);
  const ch = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
}
function ratio(a, b) {
  const [l1, l2] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

// Tokens naming a background fill rather than drawn text. These are measured
// against the text drawn on them, not against the base background, so the
// floor below does not apply to them.
const FILL = /[Bb]ackground|^diffAdded|^diffRemoved|^selectionBg$|^rate_limit_/;

// inverseText is background-coloured on purpose: it is drawn on top of a
// coloured badge and never on the base background.
const ALLOW_LOW = new Set(['inverseText']);

const AA = 4.5;
let fail = 0;
const ok  = (m) => console.log(`  ok   ${m}`);
const bad = (m) => { console.log(`  FAIL ${m}`); fail = 1; };

for (const [token, hex] of Object.entries(o)) {
  if (typeof hex !== 'string' || !hex.startsWith('#')) continue;
  if (FILL.test(token) || ALLOW_LOW.has(token)) continue;
  const r = ratio(hex, bg);
  const line = `${token.padEnd(38)} ${hex} ${r.toFixed(2).padStart(6)}:1`;
  if (r >= AA) ok(line); else bad(`${line} (want >= ${AA})`);
}

process.exit(fail);
NODE
rc=$?

echo
if [[ $rc -eq 0 ]]; then
  echo "theme-contrast: all passed"
else
  echo "theme-contrast: FAILURES"
fi
exit $rc
