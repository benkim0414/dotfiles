// Spec R3 and "Width rule". Pure: no `$`.

// The engine indents a reply by 2 columns (spec concern 5).
export const INDENT = 2
// Cells between the English and Korean columns.
export const GUTTER = 3
// 50 English characters, 25 Hangul syllables: below this, stack.
const FLOOR = 50
// Bringhurst's upper bound; 37 syllables, under WCAG's 40 for CJK.
const CAP = 75
// INDENT + FLOOR + GUTTER + FLOOR.
const SIDE_FROM = 105

export type Layout = { mode: 'side'; colWidth: number } | { mode: 'stacked' }

export function layoutFor(columns: number | undefined): Layout {
  if (columns === undefined || columns < SIDE_FROM) return { mode: 'stacked' }
  return { mode: 'side', colWidth: Math.min(CAP, Math.floor((columns - INDENT - GUTTER) / 2)) }
}
