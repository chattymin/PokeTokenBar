// PokeTokenBar battle bridge: wraps the Pokémon Showdown simulator (@pkmn/sim, MIT)
// behind a tiny synchronous JSON API that Swift drives through JavaScriptCore.
import {Battle, Dex} from '@pkmn/sim';
import {Protocol} from '@pkmn/protocol';
import {LogFormatter} from '@pkmn/view';

// Gen 5 mechanics (the app's species/learnsets stop at Gen V). Teams are already picked, so no preview.
const FORMAT = 'gen5ubers@@@!Team Preview,!Sleep Clause Mod,!Species Clause,!Nickname Clause';
const TEAM_SIZE = 3;
const SIDES = ['p1', 'p2'];

let battle = null;
let cursor = 0;          // battle.log lines already delivered
let formatters = null;

const text = (v, max) => String(v ?? '').slice(0, max);
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, Math.trunc(Number(v)) || lo));

// Team data arrives from the other Mac: never trust shape, species, or sizes.
function toSet(raw) {
  const species = Dex.species.all().find(s => s.num === Number(raw.dex) && s.name === s.baseSpecies && s.gen <= 5);
  if (!species) throw new Error(`unknown species #${raw.dex}`);
  const ivs = {};
  for (const stat of ['hp', 'atk', 'def', 'spa', 'spd', 'spe']) ivs[stat] = clamp(raw.ivs?.[stat], 0, 31);
  const nature = Dex.natures.get(text(raw.nature, 20));
  return {
    name: text(raw.name, 24) || species.name,
    species: species.name,
    level: clamp(raw.level, 1, 100),
    gender: ['M', 'F', 'N'].includes(raw.gender) ? raw.gender : '',
    shiny: !!raw.shiny,
    nature: nature.exists ? nature.name : 'Hardy',
    ability: Dex.abilities.get(text(raw.ability, 40)).exists ? text(raw.ability, 40) : species.abilities[0],
    item: '',
    moves: (Array.isArray(raw.moves) ? raw.moves : []).slice(0, 4).map(m => text(m, 40))
      .filter(m => Dex.moves.get(m).exists),
    ivs,
    evs: {hp: 0, atk: 0, def: 0, spa: 0, spd: 0, spe: 0},
    sprite: text(raw.sprite, 200),   // opaque to the sim; echoed back so Swift can draw the mon
  };
}

function toTeam(raw) {
  if (!Array.isArray(raw) || !raw.length) throw new Error('empty team');
  return raw.slice(0, TEAM_SIZE).map(toSet);
}

function mon(p, exact) {
  return {
    name: p.name,
    species: p.species.name,
    dex: p.species.num,
    sprite: p.set.sprite || '',
    shiny: !!p.set.shiny,
    level: p.level,
    hp: exact ? p.hp : Math.ceil(100 * p.hp / p.maxhp),
    maxhp: exact ? p.maxhp : 100,
    status: p.status || '',
    fainted: p.fainted,
    active: p.isActive,
  };
}

function request(side) {
  const req = side.activeRequest;
  // A side that already locked in its choice waits for the other one (no undo).
  if (!req || req.wait || battle.ended || side.isChoiceDone()) return {kind: 'wait'};
  const switches = side.pokemon.map((p, i) => (!p.isActive && !p.fainted ? i + 1 : 0)).filter(Boolean);
  if (req.forceSwitch) return {kind: 'switch', switches};
  const active = req.active[0];
  return {
    kind: 'move',
    moves: active.moves.map((m, i) => ({
      slot: i + 1,
      name: m.move,
      type: Dex.moves.get(m.id).type,
      pp: m.pp ?? 0,
      maxpp: m.maxpp ?? 0,
      disabled: !!m.disabled,
    })),
    switches: active.trapped ? [] : switches,
  };
}

function linesFor(id, lines) {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i];
    if (line.startsWith('|split|')) {
      // "|split|pX" is followed by the secret line (for pX) and then the public one.
      line = line.slice(7) === id ? lines[i + 1] : lines[i + 2];
      i += 2;
    }
    const {args, kwArgs} = Protocol.parseBattleLine(line);
    const formatted = formatters[id].formatText(args, kwArgs).replace(/\*\*/g, '').trim();
    if (formatted) out.push(...formatted.split('\n').map(s => s.trim()).filter(Boolean));
  }
  return out;
}

function snapshots() {
  const fresh = battle.log.slice(cursor);
  cursor = battle.log.length;
  const out = {};
  for (const id of SIDES) {
    const side = battle[id];
    out[id] = {
      turn: battle.turn,
      ended: battle.ended,
      winner: !battle.ended ? '' : battle.winner === side.name ? 'me' : battle.winner ? 'foe' : 'tie',
      log: linesFor(id, fresh),
      me: {name: side.name, team: side.pokemon.map(p => mon(p, true))},
      foe: {
        name: side.foe.name,
        left: side.foe.pokemonLeft,
        team: side.foe.pokemon.filter(p => p.isActive || p.previouslySwitchedIn > 0).map(p => mon(p, false)),
      },
      request: request(side),
    };
  }
  return JSON.stringify(out);
}

globalThis.PTBBattle = {
  // players: {p1: {name, team}, p2: {name, team}} — returns {p1: snapshot, p2: snapshot} or throws.
  start(json) {
    const players = JSON.parse(json);
    battle = new Battle({formatid: FORMAT});
    cursor = 0;
    formatters = {p1: new LogFormatter('p1'), p2: new LogFormatter('p2')};
    for (const id of SIDES) {
      battle.setPlayer(id, {name: text(players[id].name, 24) || id, team: toTeam(players[id].team)});
    }
    return snapshots();
  },
  // choice: "move N" | "switch N". Returns {error} for an illegal choice, else fresh snapshots.
  choose(id, choice) {
    if (!battle || !SIDES.includes(id) || !/^(move|switch) [1-6]$/.test(choice)) {
      return JSON.stringify({error: 'bad choice'});
    }
    try {
      if (!battle.choose(id, choice)) return JSON.stringify({error: battle[id].choice.error || 'invalid choice'});
      return snapshots();
    } catch (e) {
      return JSON.stringify({error: String(e.message || e)});
    }
  },
  forfeit(id) {
    if (!battle || battle.ended || !SIDES.includes(id)) return JSON.stringify({error: 'no battle'});
    battle.forceWin(id === 'p1' ? 'p2' : 'p1');
    return snapshots();
  },
};
