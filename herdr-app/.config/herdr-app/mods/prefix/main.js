// prefix: tmux-style ctrl-s prefix (matches the herdr TUI keymap).
// keys.json binds ctrl-s to "mod.open:prefix". This popup takes the keyboard,
// reads the next key, runs its command on the pane that had focus, then closes.
//   s = split down (stacked)   v = split right (side by side)   , = settings
// Any other key, or ctrl-s again, closes it.
import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { run, props, focused, closeOverlay, theme } from "herdr";

const ACTIONS = {
  s: (pane) => run("pane.split", pane ? { direction: "down", pane } : { direction: "down" }),
  v: (pane) => run("pane.split", pane ? { direction: "right", pane } : { direction: "right" }),
  ",": () => run("app.settings", {}),
};

export default class Prefix extends View {
  init(_props, cx) {
    const f = focused();
    this.pane = f ? f.pane : null;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  render() {
    const t = theme();
    return h_flex()
      .id("prefix")
      .track_focus(this.handle)
      .on_key_down((e, cx) => {
        cx.stop_propagation();
        const k = e.keystroke === "shift-," ? "," : e.keystroke;
        const action = ACTIONS[k] ?? ACTIONS[e.key_char];
        closeOverlay(props().overlay);
        if (action) action(this.pane);
      })
      .size_full()
      .px(14)
      .items_center()
      .gap(12)
      .rounded(8)
      .bg(t.popover)
      .text_size(12)
      .text_color(t.muted)
      .child(div().text_color(t.accent).font_semibold().child("ctrl-s"))
      .child(div().child("s split ↓   v split →   , settings"));
  }
}
