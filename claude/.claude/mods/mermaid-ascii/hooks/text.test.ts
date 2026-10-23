import { expect, test } from 'claude-code/testing'

import { displayWidth, fenceFor, fnv1a32, hasForbiddenControl, isMermaid, scanFences } from './text'

const lines = (...l: string[]) => l.join('\n')

test('scanFences finds a backtick fence and its source', () => {
  const text = lines('Intro', '```mermaid', 'flowchart LR', '  A --> B', '```', 'Outro')
  expect(scanFences(text)).toEqual([
    { info: 'mermaid', indent: '', source: 'flowchart LR\n  A --> B', start: 1, end: 4 },
  ])
})

test('scanFences finds a tilde fence', () => {
  const text = lines('~~~mermaid', 'flowchart LR', '~~~')
  expect(scanFences(text)).toEqual([
    { info: 'mermaid', indent: '', source: 'flowchart LR', start: 0, end: 2 },
  ])
})

test('isMermaid takes any case and surrounding spaces', () => {
  expect(isMermaid('mermaid')).toBe(true)
  expect(isMermaid('Mermaid')).toBe(true)
  expect(isMermaid('mermaid  ')).toBe(true)
  expect(isMermaid(' MERMAID')).toBe(true)
  expect(isMermaid('mermaidx')).toBe(false)
  expect(isMermaid('text')).toBe(false)
  expect(isMermaid('')).toBe(false)
})

test('scanFences keeps the raw info string', () => {
  const text = lines('```Mermaid  ', 'x', '```')
  expect(scanFences(text)[0]?.info).toBe('Mermaid  ')
})

test('scanFences leaves an unclosed fence out', () => {
  expect(scanFences(lines('```mermaid', 'flowchart LR', '  A --> B'))).toEqual([])
})

test('scanFences returns two fences in one reply', () => {
  const text = lines('```mermaid', 'a', '```', 'between', '```mermaid', 'b', '```')
  const found = scanFences(text)
  expect(found.map(f => f.source)).toEqual(['a', 'b'])
  expect(found.map(f => [f.start, f.end])).toEqual([[0, 2], [4, 6]])
})

test('scanFences does not see a mermaid fence quoted inside a longer fence', () => {
  const text = lines('````markdown', '```mermaid', 'flowchart LR', '```', '````')
  const found = scanFences(text)
  expect(found).toHaveLength(1)
  expect(found[0]?.info).toBe('markdown')
  expect(found[0]?.source).toBe('```mermaid\nflowchart LR\n```')
})

test('scanFences closes on a longer fence of the same character', () => {
  const text = lines('```mermaid', 'a', '`````', 'after')
  expect(scanFences(text)).toEqual([
    { info: 'mermaid', indent: '', source: 'a', start: 0, end: 2 },
  ])
})

test('scanFences does not close on the other character or a shorter run', () => {
  const text = lines('````mermaid', 'a', '~~~~', '```', 'b', '````')
  expect(scanFences(text)[0]?.source).toBe('a\n~~~~\n```\nb')
})

test('scanFences keeps an indented fence and its indent', () => {
  const text = lines('- item', '  ```mermaid', '  flowchart LR', '  ```')
  expect(scanFences(text)).toEqual([
    { info: 'mermaid', indent: '  ', source: 'flowchart LR', start: 1, end: 3 },
  ])
})

test('displayWidth counts ASCII and box drawing as one column each', () => {
  expect(displayWidth('abc')).toBe(3)
  expect(displayWidth('┌─┐│◇►')).toBe(6)
})

test('displayWidth counts CJK as two columns each', () => {
  expect(displayWidth('日本語')).toBe(6)
  expect(displayWidth('한글a')).toBe(5)
})

test('displayWidth counts an emoji ZWJ sequence as one wide glyph', () => {
  expect(displayWidth('🙂')).toBe(2)
  expect(displayWidth('👨‍👩‍👧')).toBe(2)
})

test('displayWidth counts combining marks as zero', () => {
  expect(displayWidth('é')).toBe(1)
})

test('displayWidth advances a tab to the next multiple of 8', () => {
  expect(displayWidth('\tx')).toBe(9)
  expect(displayWidth('abc\tx')).toBe(9)
})

test('fenceFor is three backticks or one more than the longest run', () => {
  expect(fenceFor('┌─┐')).toBe('```')
  expect(fenceFor('a`b')).toBe('```')
  expect(fenceFor('a````b')).toBe('`````')
})

test('hasForbiddenControl allows tab and newline, refuses every other control', () => {
  expect(hasForbiddenControl('┌─┐\n│\tA│')).toBe(false)
  const forbidden = [
    ...Array.from({ length: 0x20 }, (_, c) => c).filter(c => c !== 0x09 && c !== 0x0a),
    0x7f,
    ...Array.from({ length: 0x20 }, (_, c) => 0x80 + c),
  ]
  // Each one alone, so a gap in the set cannot hide behind another.
  expect(forbidden.filter(c => !hasForbiddenControl(`a${String.fromCharCode(c)}b`))).toEqual([])
})

test('fnv1a32 matches the published FNV-1a vectors', () => {
  expect(fnv1a32('')).toBe('811c9dc5')
  expect(fnv1a32('a')).toBe('e40c292c')
  expect(fnv1a32('foobar')).toBe('bf9cf968')
})

test('fnv1a32 hashes UTF-8 bytes', () => {
  // "é" is c3 a9 in UTF-8.
  expect(fnv1a32('é')).toBe(fnv1a32Bytes([0xc3, 0xa9]))
})

function fnv1a32Bytes(bytes: number[]): string {
  let h = 0x811c9dc5
  for (const b of bytes) h = Math.imul(h ^ b, 0x01000193) >>> 0
  return h.toString(16).padStart(8, '0')
}
