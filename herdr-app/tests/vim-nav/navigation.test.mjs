import { deepStrictEqual, equal } from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { it } from 'node:test';

const source = readFileSync(new URL('../../.config/herdr-app/mods/vim-nav/main.js', import.meta.url), 'utf8')
  .replace(/^import .*;$/gm, '').replace('export default ', '');
const load = new Function('View', 'run', 'focused', 'terminals', 'hc', 'nextCommand', 'notify', `${source}\nreturn VimNav;`);
const terminal = 'machine/t1';

async function navigate(commands, replies, program = 'program') {
  const closed = new Error('command channel closed');
  const calls = [];
  const moves = [];
  const notices = [];
  let focus = {pane: 'pane-a', terminal};
  let task;
  const VimNav = load(class {},
    (command, args) => moves.push([command, args]),
    () => focus,
    () => [{address: terminal, program: {key: program}}],
    async args => {
      calls.push(args);
      const reply = replies.shift();
      if (reply instanceof Error) {
        throw reply;
      }
      if (typeof reply === 'function') {
        return reply(nextFocus => { focus = nextFocus; });
      }
      return reply;
    },
    async () => {
      if (!commands.length) {
        throw closed;
      }
      return commands.shift();
    },
    notice => notices.push(notice));
  new VimNav().init({}, {spawn: work => { task = work({notify() {}}); }});
  await task.catch(error => {
    if (error !== closed) {
      throw error;
    }
  });
  return {calls, moves, notices};
}

const ok = {code: 0, stdout: '', stderr: ''};
const foreground = name => ({...ok, stdout: JSON.stringify({foreground: {name}})});

for (const name of ['vimdiff', 'gvim', 'nvimdiff', 'lvim', 'neovim']) {
  it(`forwards a chord to foreground ${name}`, async () => {
    const result = await navigate(['left'], [foreground(name), ok]);
    deepStrictEqual(result.calls, [['get', terminal, '--json'], ['keys', terminal, 'ctrl+h']]);
    deepStrictEqual(result.moves, []);
  });
}

it('moves pane focus for a non-editor even when the program table reports Vim', async () => {
  const result = await navigate(['right'], [foreground('bash')], 'vim');
  deepStrictEqual(result.calls, [['get', terminal, '--json']]);
  deepStrictEqual(result.moves, [['pane.go', {direction: 'right'}]]);
});

for (const failure of [
  {name: 'a rejected send', reply: new Error('send rejected'), message: 'send rejected'},
  {name: 'a non-zero send', reply: {code: 1, stdout: '', stderr: 'send failed'}, message: 'send failed'},
]) {
  it(`reports ${failure.name} and processes the next chord`, async () => {
    const result = await navigate(['left', 'down'], [foreground('vim'), failure.reply, foreground('bash')], 'vim');
    deepStrictEqual(result.calls, [['get', terminal, '--json'], ['keys', terminal, 'ctrl+h'], ['get', terminal, '--json']]);
    deepStrictEqual(result.moves, [['pane.go', {direction: 'down'}]]);
    equal(result.notices.length, 1);
    equal(result.notices[0].level, 'error');
    equal(result.notices[0].body, failure.message);
  });
}

it('reports a failed foreground lookup and processes the next chord', async () => {
  const result = await navigate(['left', 'right'], [{code: 1, stdout: '', stderr: 'lookup failed'}, foreground('bash')]);
  deepStrictEqual(result.moves, [['pane.go', {direction: 'right'}]]);
  equal(result.notices[0].body, 'lookup failed');
});

for (const name of ['vim', 'bash']) {
  it(`drops the chord when focus changes during the ${name} lookup`, async () => {
    const result = await navigate(['left'], [setFocus => {
      setFocus({pane: 'pane-b', terminal: 'machine/t2'});
      return foreground(name);
    }, ok]);
    deepStrictEqual(result.calls, [['get', terminal, '--json']]);
    deepStrictEqual(result.moves, []);
    deepStrictEqual(result.notices, []);
  });
}
