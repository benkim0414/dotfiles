import { View, div } from "gpui-kit";
import { run, focused, hc, nextCommand, notify } from "herdr";

// Match the foreground process name, not the app's program-table key.
const VIM = /^(g?(view|l?n?vim?x?)(diff)?|neovim)$/i;
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
    const stdout = await checkedHc(["get", terminal, "--json"]);
    const name = JSON.parse(stdout).foreground?.name ?? "";
    if (VIM.test(name)) {
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
