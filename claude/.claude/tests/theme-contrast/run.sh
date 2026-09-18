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

// Tokens naming a background fill rather than drawn text. Contrast against
// the base background is meaningless for these, so the floor below does not
// apply. Checking each fill against the text drawn on top of it is a
// separate question this suite does not answer.
//
// Anchored deliberately. An unanchored /[Bb]ackground/ would also swallow a
// future foreground token whose name merely contains the word, dropping it
// from the report with no trace.
const FILL = /^background$|_background$|Background(Color|Hover)?$|^diff|^selectionBg$|^rate_limit_empty$/;

// inverseText is background-coloured on purpose: it is drawn on top of a
// coloured badge and never on the base background.
const ALLOW_LOW = new Set(['inverseText']);

const AA = 4.5;
let fail = 0;
let skipped = 0;
const ok   = (m) => console.log(`  ok   ${m}`);
const bad  = (m) => { console.log(`  FAIL ${m}`); fail = 1; };
// Every exclusion is printed. A silent skip is indistinguishable from a
// token that was checked and passed.
const skip = (m) => { console.log(`  skip ${m}`); skipped++; };

for (const [token, hex] of Object.entries(o)) {
  if (typeof hex !== 'string' || !hex.startsWith('#')) continue;
  if (FILL.test(token))      { skip(`${token.padEnd(38)} ${hex} (background fill)`); continue; }
  if (ALLOW_LOW.has(token))  { skip(`${token.padEnd(38)} ${hex} (drawn on a coloured badge)`); continue; }
  const r = ratio(hex, bg);
  const line = `${token.padEnd(38)} ${hex} ${r.toFixed(2).padStart(6)}:1`;
  if (r >= AA) ok(line); else bad(`${line} (want >= ${AA})`);
}

// Role separation. These pairs appear on screen together, so sharing a hue
// makes them indistinguishable: a permission prompt rendered in the
// assistant's own colour does not read as something awaiting a decision.
// The palette is saturated, so the rule is not "one hue per token" but
// "no shared hue between roles that co-occur".
const SEPARATE = [['claude', 'permission'], ['claude', 'merged']];
for (const [a, b] of SEPARATE) {
  if (!o[a] || !o[b]) {
    bad(`role separation: ${a} or ${b} is missing from the theme`);
  } else if (o[a].toLowerCase() === o[b].toLowerCase()) {
    bad(`${a} and ${b} both use ${o[a]} (must differ)`);
  } else {
    ok(`${a} ${o[a]} separated from ${b} ${o[b]}`);
  }
}

console.log(`\n  ${skipped} token(s) skipped as fills; see the skip lines above`);
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
