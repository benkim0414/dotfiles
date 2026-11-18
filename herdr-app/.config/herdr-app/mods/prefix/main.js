// The shared Ctrl+S keymap. Use the full keystroke so n and Shift+N differ.
import { View, div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { run, props, focused, closeOverlay, theme, spaces, panes, layout, window, shared, setShared } from "herdr";

const ACTIONS = {
  "shift-n": ["space.new", {}],
  w: ["mod.open", { name: "picker" }],
  "shift-w": ["space.rename", {}],
  "shift-d": ["space.close", {}],
  c: ["tab.new", {}],
  n: ["tab.next", {}],
  p: ["tab.prev", {}],
  "shift-t": ["tab.rename", {}],
  "shift-x": ["tab.close", {}],
  s: ["pane.split", { direction: "down" }],
  "-": ["pane.split", { direction: "down" }],
  minus: ["pane.split", { direction: "down" }],
  v: ["pane.split", { direction: "right" }],
  h: ["pane.go", { direction: "left" }],
  j: ["pane.go", { direction: "down" }],
  k: ["pane.go", { direction: "up" }],
  l: ["pane.go", { direction: "right" }],
  x: ["pane.close", {}],
  z: ["pane.zoom", {}],
  ",": ["app.settings", {}],
  comma: ["app.settings", {}],
  "?": ["app.help", {}],
  "shift-/": ["app.help", {}],
  "shift-?": ["app.help", {}],
};

const DIRECTIONS = { h: "left", l: "right", left: "left", right: "right", up: "up", down: "down" };

function findSidebar(node) {
  if (node?.id === "sidebar") {
    return node;
  }
  for (const child of node?.children ?? []) {
    const sidebar = findSidebar(child);
    if (sidebar) {
      return sidebar;
    }
  }
}

// Match the header button and share its saved width. Do not hide the sidebar.
function toggleSidebarRail() {
  const sidebar = findSidebar(layout());
  if (!sidebar) {
    return;
  }
  const width = sidebar.size?.px;
  const collapsed = (width ?? Infinity) < 160;
  if (!collapsed && width != null) {
    setShared("sidebar.width", width);
  }
  setShared("sidebar.collapsed", !collapsed);
  const platform = window()?.platform;
  let px = 44;
  if (collapsed) {
    px = shared("sidebar.width") ?? 268;
  } else if (platform === "macos") {
    px = 76;
  }
  run("layout.resize", { id: "sidebar", px });
}

function prefixAction(key) {
  if (/^[1-9]$/.test(key)) {
    return ["tab.select", { index: Number(key) }];
  }
  if (key === "tab" || key === "shift-tab") {
    const current = focused();
    if (!current) {
      return;
    }
    const inTab = panes().filter(p => p.tab === current.tab);
    const index = inTab.findIndex(p => p.pane === current.pane);
    if (index < 0 || inTab.length < 2) {
      return;
    }
    let step = 1;
    if (key === "shift-tab") {
      step = -1;
    }
    return ["pane.focus", { pane: inTab[(index + step + inTab.length) % inTab.length].pane }];
  }
  if (Object.hasOwn(ACTIONS, key)) {
    return ACTIONS[key];
  }
}

export default class Prefix extends View {
  init(_props, cx) {
    this.navigate = false;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  key(e, cx) {
    cx.stop_propagation();
    const key = e.keystroke;
    const overlay = props().overlay;
    if (e.key === "escape" || key === "ctrl-s") {
      return closeOverlay(overlay);
    }
    if (!this.navigate && key === "g") {
      this.navigate = true;
      cx.notify();
      return;
    }
    if (this.navigate) {
      if (key === "j" || key === "k") {
        const list = spaces();
        const index = list.findIndex(s => s.id === focused()?.space);
        let step = 1;
        if (key === "k") {
          step = -1;
        }
        const next = list[index + step];
        if (next) {
          run("space.select", { id: next.id });
        }
      } else if (Object.hasOwn(DIRECTIONS, key)) {
        run("pane.go", { direction: DIRECTIONS[key] });
      }
      this.handle.focus();
      return;
    }
    const action = prefixAction(key);
    closeOverlay(overlay);
    if (key === "b") {
      return toggleSidebarRail();
    }
    if (action) {
      run(...action);
    }
  }

  render() {
    const t = theme();
    const panel = v_flex()
      .id("prefix")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx))
      .size_full()
      .px(14)
      .gap(12)
      .rounded(8)
      .bg(t.popover)
      .text_size(12)
      .text_color(t.muted);
    if (this.navigate) {
      return panel.child("Navigate: j/k spaces · h/l/↑/↓ panes · Esc close");
    }
    return panel
      .child(div().text_color(t.accent).font_semibold().child("Ctrl+S"))
      .child("N new space · w picker · c new tab · n/p next/prev · 1–9 select")
      .child("s/v split · x close pane · z zoom · g navigate · b sidebar rail · , settings · ? help · Esc cancel");
  }
}
