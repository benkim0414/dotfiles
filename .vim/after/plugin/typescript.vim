let g:vimspector_configurations = {
\  "run": {
\    "adapter": "vscode-node",
\    "configuration": {
\      "request": "launch",
\      "program": "${workspaceRoot}/node_modules/.bin/jest",
\      "args": [
\        "${fileBasenameNoExtension}",
\        "--config",
\        "${workspaceRoot}/jest.config.js",
\      ],
\      "console": "integratedTerminal",
\      "cwd": "${workspaceRoot}",
\    },
\  }
\}
