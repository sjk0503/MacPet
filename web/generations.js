// MacPet 세대(졸업) 로직 — 화면·저장·난수와 무관한 순수 함수만 둔다.
// 브라우저에서는 일반 스크립트로 불러 전역 MacPetGenerations 를 쓰고, Node 테스트는 module.exports 로 불러 쓴다.
// 저장 형식은 예전 앱이 읽는 v:1 그대로이고, 졸업한 펫 기록은 같은 객체의 collection 배열에 덧붙인다.
// eslint-disable-next-line no-var
var MacPetGenerations = (function () {
  'use strict';

  var WIRE_VERSION = 1;
  var MAX_LEVEL = 10;

  var isObj = function (x) { return !!x && typeof x === 'object' && !Array.isArray(x); };
  var text = function (x) { return typeof x === 'string' ? x.trim() : ''; };

  // 날짜 값(Date · 밀리초 · 문자열)을 ISO 문자열로. 날짜가 아니면 ''
  function toISO(x) {
    var t = x instanceof Date ? x.getTime() : typeof x === 'number' ? x : typeof x === 'string' && x.trim() ? Date.parse(x) : NaN;
    return Number.isFinite(t) && Math.abs(t) <= 8.64e15 ? new Date(t).toISOString() : '';
  }

  // 기록 하나를 검증한다. 종이나 졸업 시각을 알 수 없으면 null (그 기록만 버린다)
  function normalizeRecord(r) {
    if (!isObj(r)) return null;
    var species = text(r.species); // 지금 카탈로그에 없는 종도 남긴다 (그림은 화면 쪽이 대체한다)
    var graduatedAt = typeof r.graduatedAt === 'string' ? toISO(r.graduatedAt) : '';
    if (!species || !graduatedAt) return null;
    var seen = new Set();
    if (Array.isArray(r.completed)) {
      for (var i = 0; i < r.completed.length; i++) {
        var id = r.completed[i];
        if (typeof id === 'string' && id) seen.add(id); // 카탈로그에서 빠진 미션 id 도 그대로
      }
    }
    return { species: species, name: text(r.name) || species, shiny: r.shiny === true, graduatedAt: graduatedAt, completed: Array.from(seen) };
  }

  // 저장에서 읽은 collection → 올바른 기록만 저장된 순서(졸업한 순서)대로. 불러올 때 한 번만 부른다
  function normalizeCollection(raw) {
    var out = [];
    if (!Array.isArray(raw)) return out;
    for (var i = 0; i < raw.length; i++) {
      var rec = normalizeRecord(raw[i]);
      if (rec) out.push(rec);
    }
    return out;
  }

  // 부화했고 최고 레벨인 펫만 졸업한다 (hatched 플래그가 없는 예전 저장은 레벨로 판단한다)
  function canGraduate(state) {
    return isObj(state) && state.hatched !== false && typeof state.level === 'number' && state.level >= MAX_LEVEL && !!text(state.species);
  }

  // 졸업: 지금 펫을 collection 끝에 기록하고 새 알 상태를 돌려준다. 졸업할 수 없으면 null.
  // state 는 건드리지 않는다. state.collection 은 불러올 때 이미 정리된 것으로 보고 다시 검사하지 않는다.
  // 같은 state·when 으로 다시 불러도 같은 기록이 나오므로, 저장에 실패하면 앱이 그대로 다시 시도하면 된다.
  function graduate(state, freshEgg, when) {
    if (typeof freshEgg !== 'function') throw new TypeError('graduate: freshEgg 는 함수여야 해요');
    var graduatedAt = toISO(when);
    if (!graduatedAt) throw new TypeError('graduate: when 은 날짜여야 해요');
    if (!canGraduate(state)) return null;

    var species = text(state.species);
    var completed = [];
    if (isObj(state.done)) {
      var ids = Object.keys(state.done);
      for (var i = 0; i < ids.length; i++) if (ids[i] && state.done[ids[i]]) completed.push(ids[i]);
    }
    var record = { species: species, name: text(state.name) || species, shiny: state.shiny === true, graduatedAt: graduatedAt, completed: completed };

    var egg = freshEgg();
    if (!isObj(egg) || canGraduate(egg)) throw new TypeError('graduate: freshEgg 는 새 알 상태를 돌려줘야 해요');
    var prior = Array.isArray(state.collection) ? state.collection : [];
    return Object.assign({}, egg, { v: WIRE_VERSION, collection: prior.concat([record]) });
  }

  // 지금까지 한 번이라도 끝낸 미션 id. 불러올 때와 졸업할 때만 계산해서 들고 있는다
  function learnedIds(collection) {
    var out = new Set();
    if (!Array.isArray(collection)) return out;
    for (var i = 0; i < collection.length; i++) {
      var c = collection[i] && collection[i].completed;
      if (Array.isArray(c)) for (var j = 0; j < c.length; j++) out.add(c[j]);
    }
    return out;
  }

  return { MAX_LEVEL: MAX_LEVEL, normalizeCollection: normalizeCollection, canGraduate: canGraduate, graduate: graduate, learnedIds: learnedIds };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = MacPetGenerations;
