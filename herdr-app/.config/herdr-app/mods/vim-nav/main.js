import { View, div } from "gpui-kit";
import { run, focused, terminals, hc, nextCommand, notify } from "herdr";

const VIM = new Set(["nvim", "vim", "neovim"]);
const KEY = { left: "ctrl+h", down: "ctrl+j", up: "ctrl+k", right: "ctrl+l" };

async function checkedHc(args) {
  const result = await hc(args);
  if (result.code !== 0) {
    throw new Error(result.stderr.trim() || `hc ${args[0]} exited with code ${result.code}`);
  }
  return result.stdout;
}

async function navigate(direction) {
  const terminal = focused()?.terminal;
  if (terminal) {
    const running = terminals().find(entry => entry.address === terminal);
    if (VIM.has(running?.program?.key)) {
      await checkedHc(["keys", terminal, KEY[direction]]);
      return;
    }
  }
  run("pane.go", { direction });
}

export default class VimNav extends View {
  init(_props, cx) {
    cx.spawn(async () => {
      for (;;) {
        let direction;
        try {
          direction = await nextCommand();
        } catch {
          return;
        }
        if (!Object.hasOwn(KEY, direction)) {
          continue;
        }
        try {
          await navigate(direction);
        } catch (error) {
          notify({ title: "Vim navigation failed", body: error?.message ?? String(error), level: "error" });
        }
      }
    });
  }

  render() {
    return div().size_full();
  }
}
