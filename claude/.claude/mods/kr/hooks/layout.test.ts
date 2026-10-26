import { expect, test } from 'claude-code/testing'

import { layoutFor } from './layout'

// Spec R3 and "Width rule": side by side from 105 columns, each column
// floor((columns − 2 − 3) / 2) cells, capped at 75.
test('below 105 columns the reply stacks', () => {
  expect([80, 100, 104].map(layoutFor)).toEqual([
    { mode: 'stacked' },
    { mode: 'stacked' },
    { mode: 'stacked' },
  ])
})

test('from 105 columns the reply goes side by side', () => {
  expect([105, 120].map(layoutFor)).toEqual([
    { mode: 'side', colWidth: 50 },
    { mode: 'side', colWidth: 57 },
  ])
})

test('columns stop at 75 cells', () => {
  expect([155, 200].map(layoutFor)).toEqual([
    { mode: 'side', colWidth: 75 },
    { mode: 'side', colWidth: 75 },
  ])
})

test('a surface with no viewport stacks', () => {
  expect(layoutFor(undefined)).toEqual({ mode: 'stacked' })
})
