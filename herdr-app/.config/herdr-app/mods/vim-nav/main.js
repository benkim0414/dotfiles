// vim-nav: vim-aware ctrl+h/j/k/l (port of vim-herdr-navigation for herdr-app).
// keys.json binds ctrl-h/j/k/l to "vim-nav.left|down|up|right".
// If the focused terminal runs vim/nvim, the key goes to vim (it moves between
// its splits, and at an edge calls `herdr-app do pane.go`). Else Herdr moves focus.
import { View, div } from "gpui-kit";
import { run, focused, terminals, hc, nextCommand } from "herdr";

const VIM = new Set(["nvim", "vim", "neovim"]);
const KEY = { left: "ctrl+h", down: "ctrl+j", up: "ctrl+k", right: "ctrl+l" };

export default class VimNav extends View {
  init(_props, cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const dir = await nextCommand();
        if (!KEY[dir]) {
          continue;
        }
        const f = focused();
        let t = null;
        if (f?.terminal) {
          t = terminals().find((x) => x.address === f.terminal);
        }
        if (t && VIM.has(t.program && t.program.key)) {
          await hc(["keys", f.terminal, KEY[dir]]);
        } else {
          run("pane.go", { direction: dir });
        }
        cx.notify();
      }
    });
  }

  render() {
    return div().size_full();
  }
}
