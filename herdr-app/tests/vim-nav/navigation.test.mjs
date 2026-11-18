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
  let task;
  const VimNav = load(class {},
    (command, args) => moves.push([command, args]),
    () => ({terminal}),
    () => [{address: terminal, program: {key: program}}],
    async args => {
      calls.push(args);
      const reply = replies.shift();
      if (reply instanceof Error) {
        throw reply;
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
for (const failure of [
  {name: 'a rejected send', reply: new Error('send rejected'), message: 'send rejected'},
  {name: 'a non-zero send', reply: {code: 1, stdout: '', stderr: 'send failed'}, message: 'send failed'},
]) {
  it(`reports ${failure.name} and processes the next chord`, async () => {
    const result = await navigate(['left', 'down'], [failure.reply, ok], 'vim');
    deepStrictEqual(result.calls, [['keys', terminal, 'ctrl+h'], ['keys', terminal, 'ctrl+j']]);
    deepStrictEqual(result.moves, []);
    equal(result.notices.length, 1);
    equal(result.notices[0].level, 'error');
    equal(result.notices[0].body, failure.message);
  });
}
