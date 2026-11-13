// jsc smoke test: load bundle, play a full random battle.
load(arguments[0]);
const mk = (dex, moves, lvl) => ({dex, level: lvl, moves, nature: 'adamant', ability: 'overgrow', gender: 'M',
  ivs: {hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31}, sprite: 'k' + dex});
const players = {
  p1: {name: 'Ash', team: [mk(3, ['vine-whip', 'sleep-powder', 'razor-leaf', 'tackle'], 50), mk(6, ['flamethrower', 'slash'], 40), mk(25, ['thunderbolt', 'quick-attack'], 30)]},
  p2: {name: 'Gary', team: [mk(9, ['surf', 'bite', 'protect'], 50), mk(150, ['psychic', 'recover'], 70), mk(143, ['body-slam', 'rest'], 45), mk(1, ['tackle'], 5)]},
};
let s = JSON.parse(PTBBattle.start(JSON.stringify(players)));
print(JSON.stringify(s.p1, null, 1).slice(0, 1800));
if (PTBBattle.choose('p1', 'move 9').indexOf('error') < 0) throw new Error('bad choice accepted');
if (JSON.parse(PTBBattle.choose('p1', 'switch 1')).error === undefined) throw new Error('illegal switch accepted');
let n = 0, log = [...s.p1.log];
while (!s.p1.ended && n++ < 500) {
  for (const id of ['p1', 'p2']) {
    const r = s[id].request;
    if (r.kind === 'wait') continue;
    const opts = r.kind === 'switch' ? r.switches.map(i => 'switch ' + i)
      : r.moves.filter(m => !m.disabled).map(m => 'move ' + m.slot);
    const res = JSON.parse(PTBBattle.choose(id, opts[Math.floor(Math.random() * opts.length)]));
    if (res.error) throw new Error(res.error);
    s = res; log.push(...s.p1.log);
  }
}
print(log.slice(0, 25).join('\n')); print('...'); print(log.slice(-6).join('\n'));
print('ended', s.p1.ended, 'winner p1:', s.p1.winner, 'p2:', s.p2.winner, 'turns', s.p1.turn, 'p2 team size', s.p2.me.team.length);
if (!s.p1.ended) throw new Error('battle did not end');
try { PTBBattle.start(JSON.stringify({p1: {team: [{dex: 99999}]}, p2: players.p2})); throw new Error('x'); } catch (e) { print('rejects:', e.message); }
