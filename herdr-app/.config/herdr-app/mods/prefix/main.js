// The shared Ctrl+S keymap. Use the full keystroke so n and Shift+N differ.
import { View, div } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
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

const CHEATSHEETS = {
  prefix: ["Ctrl+S · waiting for a key", [
    ["New space", "N"],
    ["Browse spaces", "w"],
    ["Rename space", "W"],
    ["Close space", "D"],
    ["New tab", "c"],
    ["Next tab", "n"],
    ["Previous tab", "p"],
    ["Select tab", "1–9"],
    ["Rename tab", "T"],
    ["Close tab", "X"],
    ["Split down", "s", "-"],
    ["Split right", "v"],
    ["Focus left", "h"],
    ["Focus down", "j"],
    ["Focus up", "k"],
    ["Focus right", "l"],
    ["Next pane", "Tab"],
    ["Previous pane", "Shift+Tab"],
    ["Close pane", "x"],
    ["Zoom pane", "z"],
    ["Navigation mode", "g"],
    ["Toggle sidebar rail", "b"],
    ["Settings", ","],
    ["Help", "?"],
  ]],
  spaces: ["Space navigation", [
    ["Jump to space", "1–9"],
    ["Next space", "j", "n"],
    ["Previous space", "k", "p"],
    ["First space", "g", "g"],
    ["Last space", "G"],
    ["Open picker", "/"],
    ["Confirm", "Enter"],
  ]],
  navigate: ["Navigation mode", [
    ["Next space", "j"],
    ["Previous space", "k"],
    ["Focus left", "h", "←"],
    ["Focus right", "l", "→"],
    ["Focus up", "↑"],
    ["Focus down", "↓"],
  ]],
};

function keycap(key, t) {
  return div().flex_none().px(5).rounded(4).border_1().border_color(t.border)
    .bg(t.surface).text_size(11).font_semibold().text_color(t.accent).child(key);
}

function shortcut([label, ...keys], t) {
  return h_flex().items_center().gap(12)
    .child(h_flex().w(68).flex_none().gap(3).children(keys.map(key => keycap(key, t))))
    .child(label);
}

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
      if (key === "enter") {
        return closeOverlay(overlay);
      }
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
    const [title, rows] = CHEATSHEETS[this.mode];
    return v_flex()
      .id("prefix")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx))
      .w_full()
      .p(14)
      .gap(8)
      .rounded(8)
      .bg(t.popover)
      .text_size(12)
      .text_color(t.foreground)
      .child(h_flex().flex_none().items_center().justify_between().gap(6)
        .child(div().font_semibold().child(title))
        .child(h_flex().items_center().gap(5)
          .child(div().text_color(t.muted).child("Dismiss"))
          .child(keycap("Esc", t))
          .child(keycap("Ctrl+S", t))))
      // Herdr sizes popups by content up to the manifest height.
      .child(v_flex().id("prefix-shortcuts").max_h(360).overflow_y_scrollbar()
        .child(v_flex().flex_none().gap(4).children(rows.map(row => shortcut(row, t)))));
  }
}
