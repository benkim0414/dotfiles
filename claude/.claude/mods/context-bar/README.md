# context-bar

Draws what fills the context window as a band above the prompt:

- a header, for example `90k of 1M · compacts at 99%`
- one bar, coloured by category
- a legend

## Use

The band is off by default. `/context-bar` toggles it; `/context-bar on` and
`/context-bar off` set it. The choice is kept user-wide in the mod's
`$.store`. Nothing to install.

## Tests

`claude plugin test claude/.claude/mods/context-bar`

## Design

Intent, spec and plan: [`intent/show-context-breakdown/`](intent/show-context-breakdown/).
