// PokeTokenBar battle bridge, evaluated by BattleEngine.swift in JavaScriptCore.
//
// The Pokémon Showdown simulator itself is NOT part of this repository or the app bundle: the app
// downloads the published npm packages (@pkmn/sim and friends, MIT) on first use, verifies their
// hashes, and caches them on the user's device. This file is only (1) a minimal CommonJS loader
// over that cache — the host supplies `__read(path)`, returning a file's text or null — and
// (2) a small synchronous JSON API on top of the simulator.

// MARK: CommonJS loader
(function () {
  const cache = {};
  const stubs = {fs: {}, path: {join: (...a) => a.join('/'), resolve: (...a) => a.join('/'), dirname: p => p}, assert: Object.assign(() => {}, {ok() {}})};
  const norm = p => { const out = []; for (const s of p.split('/')) { if (s === '..') out.pop(); else if (s && s !== '.') out.push(s); } return out.join('/'); };
  function resolveFile(p) {
    for (const c of [p, p + '.js', p + '/index.js']) if (/\.js(on)?$/.test(c) && __read(c) != null) return c;
    return null;
  }
  function resolve(from, id) {
    if (id[0] === '.') return resolveFile(norm(from + '/../' + id));
    const parts = id.split('/'); const name = id[0] === '@' ? parts.slice(0, 2).join('/') : parts[0];
    const rest = parts.slice(name.split('/').length).join('/');
    if (rest) return resolveFile(name + '/' + rest);
    const pkg = JSON.parse(__read(name + '/package.json'));
    return resolveFile(norm(name + '/' + (pkg.main || 'index.js')));
  }
  function load(file) {
    if (cache[file]) return cache[file].exports;
    const module = cache[file] = {exports: {}};
    let src = __read(file);
    // The log templates are private to @pkmn/view; hand them out so they can be localized below.
    if (file.startsWith('@pkmn/view/')) src += '\nif (typeof text_exports !== "undefined") module.exports.__text = text_exports;';
    if (file.endsWith('.json')) { module.exports = JSON.parse(src); return module.exports; }
    const fn = (0, eval)('(function(require,module,exports){' + src + '\n})\n//# sourceURL=' + file);
    fn(id => { if (stubs[id]) return stubs[id]; const f = resolve(file, id); if (!f) throw new Error('cannot find ' + id + ' from ' + file); return load(f); }, module, module.exports);
    return module.exports;
  }
  globalThis.__require = id => load(resolve('', id) || (() => { throw new Error('cannot find ' + id); })());
})();

// MARK: Battle API
const {Battle, Dex} = __require('@pkmn/sim');
const {Protocol} = __require('@pkmn/protocol');
const {LogFormatter, __text: Text} = __require('@pkmn/view');

// Gen 5 mechanics (the app's species/learnsets stop at Gen V). Teams are already picked, so no preview.
const FORMAT = 'gen5ubers@@@!Team Preview,!Sleep Clause Mod,!Species Clause,!Nickname Clause';
const TEAM_SIZE = 3;
const SIDES = ['p1', 'p2'];

let battle = null;
let cursor = 0;          // battle.log lines already delivered
let formatters = null;
let langs = {p1: 'en', p2: 'en'};

// Localized text (bundled with the app, one JSON per language): {log: {effect: {template: text}},
// moves: {moveid: description}}. English is the simulator's own text and the fallback for the rest.
const english = {};
for (const id of Object.keys(Text || {})) if (id !== 'default') english[id] = {...Text[id]};
const languages = {};
function useText(lang) {
  const log = languages[lang]?.log || {};
  for (const id in english) Object.assign(Text[id], english[id], log[id]);
}

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

// Type chart only: abilities such as Levitate are not counted.
const multiplier = (attack, types) => types.reduce((m, t) =>
  battle.dex.getImmunity(attack, t) ? m * 2 ** battle.dex.getEffectiveness(attack, t) : 0, 1);

/// What hits this Pokémon for how much, and what its own types hit (entries at x1 are left out).
function matchups(p) {
  const types = p.getTypes(), all = battle.dex.types.names();
  const notNeutral = entries => Object.fromEntries(entries.filter(([, m]) => m !== 1));
  return {
    defense: notNeutral(all.map(t => [t, multiplier(t, types)])),
    offense: Object.fromEntries(types.map(own => [own, notNeutral(all.map(t => [t, multiplier(own, [t])]))])),
  };
}

function mon(p, exact) {
  return {
    types: p.getTypes(),
    ...(p.isActive && !p.fainted ? matchups(p) : {}),
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

function request(side, lang) {
  const req = side.activeRequest;
  // A side that already locked in its choice waits for the other one (no undo).
  if (!req || req.wait || battle.ended || side.isChoiceDone()) return {kind: 'wait'};
  const switches = side.pokemon.map((p, i) => (!p.isActive && !p.fainted ? i + 1 : 0)).filter(Boolean);
  if (req.forceSwitch) return {kind: 'switch', switches};
  const active = req.active[0];
  return {
    kind: 'move',
    moves: active.moves.map((m, i) => {
      const move = battle.dex.moves.get(m.id), foe = side.foe.active[0];
      return {
        slot: i + 1,
        name: m.move,
        type: move.type,
        pp: m.pp ?? 0,
        maxpp: m.maxpp ?? 0,
        disabled: !!m.disabled,
        category: move.category,
        power: move.basePower || 0,
        accuracy: move.accuracy === true ? 0 : move.accuracy,   // 0 = never misses
        priority: move.priority || 0,
        desc: languages[lang]?.moves?.[move.id] || move.shortDesc || '',
        // Against the opponent on the field; absent for status moves and an empty field.
        ...(move.category !== 'Status' && foe && !foe.fainted ? {effect: multiplier(move.type, foe.getTypes())} : {}),
      };
    }),
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
    useText(langs[id]);
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
      request: request(side, langs[id]),
    };
  }
  return JSON.stringify(out);
}

globalThis.PTBBattle = {
  // Registers one language's text; a side that asks for an unknown language reads English.
  addLanguage(lang, json) {
    languages[lang] = JSON.parse(json);
  },
  // players: {p1: {name, lang, team}, p2: {...}} — returns {p1: snapshot, p2: snapshot} or throws.
  start(json) {
    const players = JSON.parse(json);
    langs = {p1: text(players.p1.lang, 8), p2: text(players.p2.lang, 8)};
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
