import { readFileSync } from 'node:fs';
import { strict as assert } from 'node:assert';
import { it } from 'node:test';

const app = new URL('../../.config/herdr-app/', import.meta.url);
const calls = [];
let keyDown;
let keycaps;
let prefix;
const div = () => {
  const el = { content: [] };
  for (const name of [
    'p', 'bg', 'text_color', 'track_focus', 'id', 'w_full', 'px', 'items_center',
    'justify_between', 'gap', 'rounded', 'text_size', 'font_semibold', 'border_color',
    'flex_none', 'h', 'max_h', 'overflow_y_scrollbar', 'pb', 'w',
  ]) {
    el[name] = () => el;
  }
  let bordered = false;
  el.border_1 = () => { bordered = true; return el; };
  el.child = text => {
    el.content.push(text);
    if (bordered && typeof text === 'string') {
      keycaps.push(text);
    }
    return el;
  };
  el.children = children => { el.content.push(...children); return el; };
  el.on_key_down = fn => { keyDown = fn; return el; };
  return el;
};
const theme = () => ({});
const props = () => ({overlay: 'test-overlay'});
const closeOverlay = id => calls.push(['close', id]);
let activeSpace;
const run = (...args) => {
  calls.push(args);
  if (args[0] === 'space.select') {
    activeSpace = args[1].id;
  }
};
const spaces = () => [{id: 'space-a'}, {id: 'space-b'}, {id: 'space-c'}];
const focused = () => ({space: activeSpace, tab: 'tab-a', pane: 'pane-a'});
const panes = () => [{tab: 'tab-a', pane: 'pane-a'}, {tab: 'tab-b', pane: 'pane-b'}, {tab: 'tab-a', pane: 'pane-c'}, {tab: 'tab-a', pane: 'pane-d'}];
const state = new Map();
let sidebar;
let platform = 'linux';
const layout = () => {
  const children = [];
  if (sidebar) {
    children.push(sidebar);
  }
  return {id: 'root', children};
};
const window = () => ({platform});
const shared = key => state.get(key);
const setShared = (key, value) => state.set(key, value);
const source = readFileSync(new URL('mods/prefix/main.js', app), 'utf8')
  .replace(/^import .*;$/gm, '').replace('export default ', '');
const Prefix = new Function('View', 'div', 'v_flex', 'h_flex', 'theme', 'props', 'closeOverlay', 'run', 'spaces', 'focused', 'panes', 'layout', 'window', 'shared', 'setShared', `${source}\nreturn Prefix;`)(class {}, div, div, div, theme, props, closeOverlay, run, spaces, focused, panes, layout, window, shared, setShared);
const ctx = {focus_handle: () => ({focus() {}}), stop_propagation() {}, notify() {}};
function renderKeys() {
  keycaps = [];
  prefix.render();
  return keycaps;
}

function press(key, keystroke = key) {
  calls.length = 0;
  activeSpace = 'space-a';
  prefix = new Prefix();
  prefix.init({}, ctx);
  renderKeys();
  keyDown({key, keystroke}, ctx);
}

it('creates a space on prefix Shift+N', () => {
  press('n', 'shift-n');
  assert.deepEqual(calls, [['close', 'test-overlay'], ['space.new', {}]]);
});

it('shows the prefix commands as keycaps without submenu-only keys', () => {
  press('unmapped');
  assert.deepEqual(renderKeys(), [
    'Esc', 'Ctrl+S',
    'N', 'w', 'W', 'D',
    'c', 'n', 'p', '1–9', 'T', 'X',
    's', 'v', 'h', 'j', 'k', 'l', 'Tab', 'Shift+Tab', 'x', 'z',
    'g', 'b', ',', '?',
  ]);
});

function textIn(element) {
  if (typeof element === 'string') {
    return [element];
  }
  return element.content.flatMap(textIn);
}

it('places keycaps before their command labels in the popup', () => {
  press('unmapped');
  const content = textIn(prefix.render()).join(' ');
  assert.match(content, /N New space w Browse spaces/);
  assert.match(content, /h Focus left j Focus down k Focus up l Focus right/);
  assert.match(content, /Shift\+Tab Previous pane/);
  assert.match(content, /Dismiss Esc \/ Ctrl\+S/);
});

it('shows the space navigation commands as keycaps after w', () => {
  press('w');
  assert.deepEqual(renderKeys(), ['Esc', 'Ctrl+S', '1–9', 'j', 'n', 'k', 'p', 'gg', 'G', '/', 'Enter']);
  assert.match(textIn(prefix.render()).join(' '), /j \/ n Next space k \/ p Previous space gg First space/);
});

it('shows the repeatable navigation commands as keycaps after g', () => {
  press('g');
  assert.deepEqual(renderKeys(), ['Esc', 'Ctrl+S', 'j', 'k', 'h', '←', 'l', '→', '↑', '↓']);
  assert.match(textIn(prefix.render()).join(' '), /h \/ ← Focus left l \/ → Focus right/);
});

it('dismisses the overlay without running an action for unmapped n chords', () => {
  for (const chord of ['alt-shift-n', 'ctrl-shift-n']) {
    press('n', chord);
    assert.deepEqual(calls, [['close', 'test-overlay']]);
  }
});

it('splits down on prefix s and right on prefix v', () => {
  for (const [key, direction] of [['s', 'down'], ['v', 'right']]) {
    press(key);
    assert.deepEqual(calls, [['close', 'test-overlay'], ['pane.split', {direction}]]);
  }
});

it('dismisses the overlay without splitting on prefix minus', () => {
  for (const chord of ['-', 'minus']) {
    press('-', chord);
    assert.deepEqual(calls, [['close', 'test-overlay']]);
  }
});

const aliases = {
  c: ['tab.new', {}], n: ['tab.next', {}], p: ['tab.prev', {}],
  'shift-t': ['tab.rename', {}], 'shift-x': ['tab.close', {}],
  'shift-w': ['space.rename', {}],
  'shift-d': ['space.close', {}], x: ['pane.close', {}], z: ['pane.zoom', {}],
  '?': ['app.help', {}], 'shift-/': ['app.help', {}], 'shift-?': ['app.help', {}],
  tab: ['pane.focus', {pane: 'pane-c'}], 'shift-tab': ['pane.focus', {pane: 'pane-d'}],
};
for (const [chord, action] of Object.entries(aliases)) {
  it(`runs ${action[0]} on prefix ${chord}`, () => {
    press(chord.replace(/^shift-/, ''), chord);
    assert.deepEqual(calls, [['close', 'test-overlay'], action]);
  });
}

it('selects only tabs 1 through 9 with prefix digits', () => {
  for (let index = 1; index <= 9; index++) {
    press(String(index));
    assert.deepEqual(calls, [['close', 'test-overlay'], ['tab.select', {index}]]);
  }
  press('0');
  assert.deepEqual(calls, [['close', 'test-overlay']]);
});

function send(key, keystroke = key, is_held = false) {
  keyDown({key, keystroke, is_held}, ctx);
}

it('jumps directly to a space by number on prefix w', () => {
  press('w');
  assert.deepEqual(calls, []);
  send('2');
  assert.deepEqual(calls, [['close', 'test-overlay'], ['space.select', {id: 'space-b'}]]);
});

it('keeps space mode open when a digit has no matching space', () => {
  press('w');
  send('0');
  send('9');
  send('2', 'alt-2');
  assert.deepEqual(calls, []);
  send('escape');
  assert.deepEqual(calls, [['close', 'test-overlay']]);
});

it('opens the original picker on prefix w then slash', () => {
  press('w');
  send('/');
  assert.deepEqual(calls, [['close', 'test-overlay'], ['mod.open', {name: 'picker'}]]);
});

it('steps through spaces with j and k without wrapping or closing', () => {
  press('w');
  send('k');
  for (const key of ['j', 'k']) {
    send(key);
    send(key, key, true);
    send(key, key, true);
  }
  assert.deepEqual(calls, ['space-b', 'space-c', 'space-b', 'space-a'].map(id => ['space.select', {id}]));
});

it('steps through spaces with n and p after prefix w', () => {
  press('w');
  send('p');
  send('n');
  send('n', 'n', true);
  send('n', 'n', true);
  send('p');
  send('p', 'p', true);
  assert.deepEqual(calls, ['space-b', 'space-c', 'space-b', 'space-a'].map(id => ['space.select', {id}]));
  send('escape');
  assert.deepEqual(calls.at(-1), ['close', 'test-overlay']);
});

it('confirms the current space with Enter without selecting it again', () => {
  for (const previous of ['k', 'p']) {
    press('w');
    send('j');
    send('n');
    send(previous);
    send('enter', 'shift-enter');
    assert.equal(calls.length, 3);
    send('enter');
    assert.equal(activeSpace, 'space-b');
    assert.deepEqual(calls, [
      ['space.select', {id: 'space-b'}],
      ['space.select', {id: 'space-c'}],
      ['space.select', {id: 'space-b'}],
      ['close', 'test-overlay'],
    ]);
  }
});

it('jumps to the bottom on Shift+G and to the top on gg', () => {
  press('w');
  send('g', 'shift-g');
  assert.deepEqual(calls, [['space.select', {id: 'space-c'}]]);
  send('g');
  assert.equal(calls.length, 1);
  send('g');
  assert.deepEqual(calls[1], ['space.select', {id: 'space-a'}]);
});

it('requires consecutive unmodified g presses to jump to the top', () => {
  press('w');
  send('j');
  send('g');
  send('g', 'ctrl-g');
  send('g');
  assert.deepEqual(calls, [['space.select', {id: 'space-b'}]]);
  send('g');
  assert.deepEqual(calls[1], ['space.select', {id: 'space-a'}]);
  send('g');
  assert.equal(calls.length, 2);
});

it('ignores held g events until a second distinct g press in space mode', () => {
  press('w');
  send('j');
  send('g');
  send('g', 'g', true);
  send('g', 'g', true);
  assert.deepEqual(calls, [['space.select', {id: 'space-b'}]]);
  send('g');
  assert.deepEqual(calls, [['space.select', {id: 'space-b'}], ['space.select', {id: 'space-a'}]]);
});

it('switches spaces in navigation mode without closing the overlay', () => {
  press('g');
  keyDown({key: 'j', keystroke: 'j'}, ctx);
  assert.deepEqual(calls, [['space.select', {id: 'space-b'}]]);
});

it('collapses the sidebar to a rail and restores its previous width on prefix b', () => {
  for (const [os, rail] of [['linux', 44], ['macos', 76]]) {
    platform = os;
    sidebar = {id: 'sidebar', size: {px: 315}};
    press('b');
    assert.deepEqual(calls, [['close', 'test-overlay'], ['layout.resize', {id: 'sidebar', px: rail}]]);
    assert.equal(shared('sidebar.collapsed'), true);
    sidebar.size.px = rail;
    press('b');
    assert.deepEqual(calls, [['close', 'test-overlay'], ['layout.resize', {id: 'sidebar', px: 315}]]);
    assert.equal(shared('sidebar.collapsed'), false);
  }
});

it('leaves layouts without a sidebar unchanged on prefix b', () => {
  sidebar = null;
  press('b');
  assert.deepEqual(calls, [['close', 'test-overlay']]);
});
