// The shared Ctrl+S keymap. Use the full keystroke so n and Shift+N differ.
import { View, div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { run, props, focused, closeOverlay, theme, spaces, panes, layout, window, shared, setShared } from "herdr";

const ACTIONS = {
  "shift-n": ["space.new", {}],
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
const SPACE_STEPS = { j: 1, n: 1, k: -1, p: -1 };

function adjacentSpace(list, key) {
  const index = list.findIndex(space => space.id === focused()?.space);
  return list[index + SPACE_STEPS[key]];
}

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
    this.mode = "prefix";
    this.pendingG = false;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  spaceKey(key, overlay) {
    const doubleG = key === "g" && this.pendingG;
    this.pendingG = key === "g" && !doubleG;
    if (this.pendingG) {
      return;
    }
    if (key === "/") {
      closeOverlay(overlay);
      return run("mod.open", { name: "picker" });
    }
    const list = spaces();
    if (/^[1-9]$/.test(key)) {
      const space = list[Number(key) - 1];
      if (space) {
        closeOverlay(overlay);
        return run("space.select", { id: space.id });
      }
      return;
    }
    let space;
    if (doubleG) {
      space = list[0];
    } else if (key === "shift-g") {
      space = list[list.length - 1];
    } else if (Object.hasOwn(SPACE_STEPS, key)) {
      space = adjacentSpace(list, key);
    }
    if (space) {
      run("space.select", { id: space.id });
      this.handle.focus();
    }
  }

  key(e, cx) {
    cx.stop_propagation();
    const key = e.keystroke;
    const overlay = props().overlay;
    if (e.key === "escape" || key === "ctrl-s") {
      return closeOverlay(overlay);
    }
    if (this.mode === "prefix" && (key === "w" || key === "g")) {
      this.mode = key === "w" ? "spaces" : "navigate";
      cx.notify();
      return;
    }
    if (this.mode === "spaces") {
      if (key === "g" && e.is_held) {
        return;
      }
      return this.spaceKey(key, overlay);
    }
    if (this.mode === "navigate") {
      if (key === "j" || key === "k") {
        const next = adjacentSpace(spaces(), key);
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
    if (this.mode === "spaces") {
      return panel.child("Spaces: 1–9 jump · j/n next · k/p previous · gg first · G last · / picker · Esc close");
    }
    if (this.mode === "navigate") {
      return panel.child("Navigate: j/k spaces · h/l/↑/↓ panes · Esc close");
    }
    return panel
      .child(div().text_color(t.accent).font_semibold().child("Ctrl+S"))
      .child("N new space · w spaces · c new tab · n/p next/prev · 1–9 select tab")
      .child("s/v split · x close pane · z zoom · g navigate · b sidebar rail · , settings · ? help · Esc cancel");
  }
}
