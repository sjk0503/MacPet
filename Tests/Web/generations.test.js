'use strict';
// 실행: node --test Tests/Web/generations.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const FILE = path.join(__dirname, '..', '..', 'web', 'generations.js');
const G = require(FILE);

const WHEN = '2026-11-24T03:00:00.000Z';
const WHEN2 = '2026-12-01T09:30:00.000Z';

// 앱의 fresh() 와 같은 모양의 알 (종·색은 테스트가 정한다)
const eggOf = (species, shiny) => () => ({
  v: 1, species, shiny: !!shiny, hatched: false, crack: 0, name: '', level: 0, exp: 0,
  done: Object.create(null), manual: Object.create(null), guide: null, petDay: '', pets: 0, lastSeen: 1,
});
// 예전 0.1 앱이 저장한 최고 레벨 펫 (collection 없음)
const legacyMax = (over) => Object.assign({
  v: 1, species: 'nyang', shiny: false, hatched: true, crack: 0, name: '모찌', level: 10, exp: 0,
  done: { spotlight: '2026-05-01T00:00:00.000Z', screenshot: true, 'retired-mission': 'x', skipped: false },
  manual: { spotlight: true }, guide: { id: 'dock', step: 2 }, petDay: '2026-11-24', pets: 3, lastSeen: 5,
}, over);
const reload = (state) => JSON.parse(JSON.stringify(state)); // 저장했다가 다시 읽기
const frozen = (x) => { if (x && typeof x === 'object') { Object.values(x).forEach(frozen); Object.freeze(x); } return x; };

test('예전 최고 레벨 저장(collection 없음)은 졸업하고, 레벨 9 는 졸업하지 않는다', () => {
  let eggs = 0;
  const lv9 = G.graduate(legacyMax({ level: 9, exp: 60 }), () => { eggs++; return eggOf('bam')(); }, WHEN);
  assert.equal(lv9, null);
  assert.equal(eggs, 0, '졸업하지 않으면 새 알도 만들지 않는다');
  assert.equal(G.graduate(legacyMax({ hatched: false }), eggOf('bam'), WHEN), null);
  assert.equal(G.graduate(null, eggOf('bam'), WHEN), null);

  const old = frozen(legacyMax()); // 얼려 두어 원본을 고치면 바로 실패한다
  const next = G.graduate(old, eggOf('bam', true), new Date(WHEN));
  assert.deepEqual(next.collection, [
    { species: 'nyang', name: '모찌', shiny: false, graduatedAt: WHEN, completed: ['spotlight', 'screenshot', 'retired-mission'] },
  ]);
  assert.equal('collection' in old, false);

  // 새 알: v:1 그대로, 펫마다의 진행은 모두 비어 있다
  assert.equal(next.v, 1);
  assert.deepEqual([next.species, next.shiny, next.hatched, next.level, next.exp, next.name, next.guide], ['bam', true, false, 0, 0, '', null]);
  assert.deepEqual(Object.keys(next.done), []);
  assert.deepEqual(Object.keys(next.manual), []);

  // 이름 없는 예전 펫은 종 id 를 이름으로 쓰고, hatched 플래그가 없어도 레벨로 판단한다
  const unnamed = legacyMax({ name: '  ', shiny: true });
  delete unnamed.hatched;
  const rec = G.graduate(unnamed, eggOf('peng'), WHEN).collection[0];
  assert.deepEqual([rec.name, rec.species, rec.shiny], ['nyang', 'nyang', true]);
});

test('최고 레벨 순간에 한 번만 졸업하고, 다시 불러온 알은 그대로다', () => {
  const max = legacyMax();
  const egg = G.graduate(max, eggOf('hammy'), WHEN);

  // 저장에 실패해 예전 상태로 다시 시도해도 같은 기록이 하나만 생긴다
  assert.deepEqual(G.graduate(max, eggOf('hammy'), WHEN), egg);

  // 저장 → 다시 불러오기: 알이고, 기록은 그대로이며, 또 졸업하지 않는다
  const loaded = reload(egg);
  assert.equal(loaded.v, 1);
  assert.equal(loaded.hatched, false);
  assert.deepEqual(G.normalizeCollection(loaded.collection), egg.collection);
  assert.equal(G.graduate(loaded, eggOf('mung'), WHEN2), null);
  assert.equal(G.graduate(egg, eggOf('mung'), WHEN2), null);
  assert.deepEqual([...G.learnedIds(loaded.collection)], ['spotlight', 'screenshot', 'retired-mission']);
});

test('두 세대를 이어 졸업하면 기록이 순서대로 쌓이고, 같은 미션을 다시 해도 된다', () => {
  const gen1 = G.graduate(legacyMax(), eggOf('bam'), WHEN);
  assert.equal(gen1.done.spotlight, undefined, '새 펫은 끝낸 미션이 없어 같은 미션을 다시 할 수 있다');

  // 2세대: 부화해서 같은 미션(spotlight)과 새 미션을 끝내고 최고 레벨이 된다
  const grown = Object.assign(reload(gen1), { hatched: true, name: '', level: 10, done: { spotlight: WHEN2, dock: WHEN2 } });
  grown.collection = G.normalizeCollection(grown.collection);
  const prior = frozen(grown.collection);
  const gen2 = G.graduate(grown, eggOf('peng'), Date.parse(WHEN2));

  assert.equal(gen2.collection.length, 2);
  assert.equal(gen2.collection[0], prior[0], '이미 정리된 기록은 다시 만들거나 검사하지 않고 그대로 쓴다');
  assert.equal(grown.collection.length, 1);
  assert.deepEqual(gen2.collection[1], { species: 'bam', name: 'bam', shiny: false, graduatedAt: WHEN2, completed: ['spotlight', 'dock'] });
  assert.deepEqual(gen2.collection.map((r) => r.graduatedAt), [WHEN, WHEN2]);
  assert.deepEqual(Object.keys(gen2.done), []);

  const learned = G.learnedIds(gen2.collection);
  assert.ok(learned instanceof Set);
  assert.deepEqual([...learned].sort(), ['dock', 'retired-mission', 'screenshot', 'spotlight']);
  assert.equal(G.graduate(gen2, eggOf('nyang'), WHEN2), null);
});

test('깨진 기록은 그것만 버리고, 모르는 종과 없어진 미션 id 는 남긴다', () => {
  const good = { species: 'nyang', name: '모찌', shiny: true, graduatedAt: WHEN, completed: ['a', 'b'] };
  const raw = [
    good,
    null, 'x', 7, [good],
    { name: '종 없음', graduatedAt: WHEN, completed: [] },
    { species: '   ', graduatedAt: WHEN },
    { species: 'bam', graduatedAt: '어제' },
    { species: 'bam', graduatedAt: 1764000000000 },
    { species: 'dragon-2099', name: '', shiny: 'yes', graduatedAt: '2026-12-01T18:30:00+09:00', completed: ['a', '', 'a', 3, null, 'retired-mission', '__proto__'] },
    { species: 'peng', name: ' 펭 ', graduatedAt: WHEN2, completed: { a: true } },
  ];
  const before = JSON.stringify(raw);
  assert.deepEqual(G.normalizeCollection(raw), [
    good,
    { species: 'dragon-2099', name: 'dragon-2099', shiny: false, graduatedAt: WHEN2, completed: ['a', 'retired-mission', '__proto__'] },
    { species: 'peng', name: '펭', shiny: false, graduatedAt: WHEN2, completed: [] },
  ]);
  assert.equal(JSON.stringify(raw), before, '입력은 고치지 않는다');
  assert.deepEqual([...G.learnedIds(G.normalizeCollection(raw))], ['a', 'b', 'retired-mission', '__proto__']);

  for (const junk of [undefined, null, 'x', 3, {}, { 0: good, length: 1 }]) assert.deepEqual(G.normalizeCollection(junk), []);
  assert.deepEqual([...G.learnedIds(undefined)], []);

  // 정리한 결과를 다시 정리해도 같다
  const once = G.normalizeCollection(raw);
  assert.deepEqual(G.normalizeCollection(reload(once)), once);
});

test('잘못된 인자는 조용히 넘기지 않는다', () => {
  assert.throws(() => G.graduate(legacyMax(), null, WHEN), TypeError);
  assert.throws(() => G.graduate(legacyMax(), eggOf('bam'), undefined), TypeError);
  assert.throws(() => G.graduate(legacyMax(), eggOf('bam'), 'not a date'), TypeError);
  assert.throws(() => G.graduate(legacyMax(), () => legacyMax(), WHEN), TypeError, '새 알 대신 다 자란 펫을 받으면 끝없이 졸업한다');
});

test('브라우저 일반 스크립트로 불러도 전역 MacPetGenerations 가 생긴다', () => {
  const ctx = vm.createContext({});
  vm.runInContext(fs.readFileSync(FILE, 'utf8'), ctx, { filename: FILE });
  const B = vm.runInContext('MacPetGenerations', ctx);
  assert.deepEqual(Object.keys(B).sort(), Object.keys(G).sort());
  assert.equal(B.graduate(legacyMax({ level: 9 }), eggOf('bam'), WHEN), null);
  assert.equal(B.graduate(legacyMax(), eggOf('bam'), WHEN).collection.length, 1);
});
