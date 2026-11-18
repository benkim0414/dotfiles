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
