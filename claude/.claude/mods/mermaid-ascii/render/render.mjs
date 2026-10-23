// Reads Mermaid source on stdin and writes text art to stdout.
// Exit 0: art. Exit 1: the library threw (invalid or unsupported diagram).
// Exit 3: beautiful-mermaid is not installed (`npm ci` has not run here).

let lib
try {
  // Dynamic, so a missing package is told apart from a bad diagram.
  lib = await import('beautiful-mermaid')
} catch (err) {
  if (err?.code === 'ERR_MODULE_NOT_FOUND') {
    process.stderr.write(`render.mjs: ${err.message}\n`)
    process.exit(3)
  }
  throw err
}

let source = ''
process.stdin.setEncoding('utf8')
for await (const chunk of process.stdin) source += chunk

let art
try {
  art = lib.renderMermaidASCII(source, { useAscii: false, colorMode: 'none' })
} catch (err) {
  process.stderr.write(`render.mjs: ${err?.message ?? err}\n`)
  process.exit(1)
}
process.stdout.write(art)
