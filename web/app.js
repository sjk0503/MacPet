// MacPet 펫 화면 — 도트 펫 + 미션 카드. 엔진(engine.js)의 전역을 그대로 쓴다.
// 네이티브(Swift)와는 window.__MACPET__ / window.MacPet.onNative / webkit.messageHandlers.pet 으로만 주고받는다.
(function () {
  'use strict';

  const SAVE_VERSION = 1; // 쓰기는 예전 0.1 앱이 읽는 v:1 그대로다 (v 가 1 이 아닌 저장은 읽기 전용으로만 다룬다)
  const SAVE_KEY = 'macpet:save:v1';
  const PROT_KEY = '__macpetProtected'; // 네이티브가 "읽을 수 없는 저장"이라고 알릴 때 쓰는 표식 (SaveStore.swift 와 같다)
  const MAXLV = 10;
  const NEED = (l) => 20 + l * 5;
  const STAGE = (l) => (l >= MAXLV ? 3 : l >= 5 ? 2 : 1);

  // 두드릴 때 나오는 동작과 한마디 (동작 모양은 engine.js 의 pose)
  const TAP_POSES = [
    { s: 'pet', t: ['헤헤, 좋아요', '간지러워요', '더 해 주세요'] },
    { s: 'hop', t: ['깡총깡총!', '기분 최고예요!'] },
    { s: 'wink', t: ['찡긋!', '오늘도 파이팅이에요!'] },
    { s: 'shy', t: ['부끄러워요…', '헤헤, 몰라요'] },
    { s: 'wave', t: ['안녕하세요!', '반가워요!'] },
    { s: 'tilt', t: ['응? 불렀어요?', '왜요, 왜요?'] },
  ];

  let readOnly = false; // 저장을 건드리면 안 되는 실행 (아래 '저장' 참고)
  let readOnlyReason = '';

  /* ───────── 네이티브 연결 ───────── */
  const boot = window.__MACPET__ || null;
  const handler = () => {
    try { return window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pet; } catch (e) { return null; }
  };
  function post(msg) {
    if (readOnly && msg && msg.type === 'save') return; // 보호 중인 저장은 어떤 경로로도 쓰지 않는다
    const h = handler();
    if (!h) {
      // 개발 모드(브라우저): 보낸 메시지를 window.__posted 에 최근 50개까지 쌓는다
      try {
        const a = window.__posted || (window.__posted = []);
        a.push(JSON.parse(JSON.stringify(msg)));
        if (a.length > 50) a.splice(0, a.length - 50);
      } catch (e) { /* 무시 */ }
      return;
    }
    try { h.postMessage(msg); } catch (e) { /* 네이티브가 없으면 무시 */ }
  }
  window.addEventListener('error', (e) => post({ type: 'log', msg: String(e.message || e.error || 'error') + (e.filename ? ' @' + e.filename + ':' + e.lineno : '') }));
  window.addEventListener('unhandledrejection', (e) => post({ type: 'log', msg: 'unhandledrejection: ' + String((e.reason && e.reason.stack) || e.reason) }));

  // 네이티브 → JS. 초기화 전에 온 이벤트는 모아 두었다가 준비되면 처리한다
  let ready = false;
  const queue = [];
  window.MacPet = {
    onNative(ev) {
      if (!ready) { queue.push(ev); return; }
      handleNative(ev);
    },
  };

  /* ───────── 저장 ───────── */
  // 저장을 읽을 수 없거나(파싱 실패·권한) 더 새로운 버전이면 원본을 그대로 두고 이번 실행은 저장하지 않는다
  const statusText = () => (readOnlyReason === 'version'
    ? '더 새로운 버전의 저장이라 이번에는 저장하지 않아요. 새 버전의 MacPet을 열면 이어서 할 수 있어요'
    : '저장을 읽을 수 없어서 이번에는 저장하지 않아요. 이전 저장을 복원하고 MacPet을 다시 열어 주세요');
  const GEN = typeof MacPetGenerations === 'object' && MacPetGenerations ? MacPetGenerations : null; // generations.js (졸업·앨범 규칙)
  const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  const own = (o, k) => {
    if (!o || typeof o !== 'object') return undefined;
    const d = Object.getOwnPropertyDescriptor(o, k);
    return d && 'value' in d ? d.value : undefined;
  };
  const dict = () => Object.create(null); // 미션 id 가 __proto__ · constructor 여도 안전한 맵
  const intIn = (v, lo, hi, d) => (typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.floor(v))) : d);
  const localDay = () => { const d = new Date(); return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`; };
  function fresh() {
    return { v: SAVE_VERSION, species: pick(SPECIES), shiny: Math.random() < 1 / 64, hatched: false, crack: 0, name: '', level: 0, exp: 0, done: dict(), manual: dict(), guide: null, petDay: '', pets: 0, lastSeen: Date.now() };
  }
  // 아는 필드만 하나씩 검증해서 새 상태에 옮긴다. 틀린 필드는 그 필드만 기본값으로 (종이 틀려도 나머지는 살린다)
  function readFields(raw) {
    const n = fresh();
    const sp = own(raw, 'species');
    if (typeof sp === 'string' && hasOwn(SP, sp)) n.species = sp;
    n.shiny = own(raw, 'shiny') === true;
    const h = own(raw, 'hatched');
    n.level = intIn(own(raw, 'level'), 0, MAXLV, 0);
    n.hatched = h === true || (typeof h !== 'boolean' && n.level >= 1); // 플래그가 없거나 깨졌어도 레벨이 있으면 이미 자란 펫이다
    if (n.hatched) {
      n.crack = 0;
      if (n.level < 1) n.level = 1;
      n.exp = n.level >= MAXLV ? 0 : intIn(own(raw, 'exp'), 0, NEED(n.level) - 1, 0);
    } else {
      // 알: 레벨·경험치 없음. 금이 간 정도는 기억한다 (3 은 부화 연출 중이던 값이라 2 로 되돌린다)
      n.level = 0; n.exp = 0;
      n.crack = intIn(own(raw, 'crack'), 0, 2, 0);
    }
    const nm0 = own(raw, 'name');
    n.name = typeof nm0 === 'string' ? Array.from(nm0.trim()).slice(0, 8).join('') : '';
    const d = own(raw, 'done');
    if (d && typeof d === 'object' && !Array.isArray(d)) {
      Object.keys(d).forEach((k) => { const t = own(d, k); if (t === true || (typeof t === 'string' && t)) n.done[k] = t; }); // 카탈로그에서 빠진 미션도, 옛 true 플래그·"x" 같은 옛 시각도 그대로
    }
    const m = own(raw, 'manual');
    if (m && typeof m === 'object' && !Array.isArray(m)) {
      Object.keys(m).forEach((k) => { if (own(m, k) === true) n.manual[k] = true; });
    }
    const g = own(raw, 'guide');
    const gid = own(g, 'id'), gstep = own(g, 'step');
    n.guide = n.hatched && typeof gid === 'string' && gid && Number.isInteger(gstep) && gstep >= -1 ? { id: gid, step: Math.min(gstep, 999) } : null;
    const pd = own(raw, 'petDay');
    n.petDay = typeof pd === 'string' ? pd : '';
    n.pets = intIn(own(raw, 'pets'), 0, 5, 0);
    const ls = own(raw, 'lastSeen');
    n.lastSeen = typeof ls === 'number' && Number.isFinite(ls) && ls >= 0 ? ls : Date.now();
    return n;
  }
  // 졸업 앨범(collection)은 v:1 저장에 덧붙는 선택 필드다. 없거나 비어 있으면 상태에도 두지 않아 예전 저장과 똑같이 쓴다
  function readState(raw) {
    const n = readFields(raw);
    const c = own(raw, 'collection');
    if (!Array.isArray(c) || !c.length) return { state: n };
    // 앨범이 있는데 읽을 방법이 없으면 덮어써서 잃지 않도록 이번 실행은 저장하지 않는다
    if (!GEN) return { protect: 'collection' };
    let list;
    try { list = GEN.normalizeCollection(c); } catch (e) { return { protect: 'collection' }; }
    if (Array.isArray(list) && list.length) n.collection = list;
    return { state: n };
  }
  const KNOWN = ['species', 'shiny', 'hatched', 'crack', 'name', 'level', 'exp', 'done', 'manual', 'guide', 'petDay', 'pets', 'lastSeen'];
  // 저장 없음 → 새 상태. 알 수 없는 버전·모양 → { protect: 이유 } (쓰지 않는다)
  function decodeSave(raw) {
    if (raw === null || raw === undefined) return { state: fresh() };
    if (typeof raw !== 'object' || Array.isArray(raw)) return { protect: 'shape' };
    const mark = own(raw, PROT_KEY);
    if (mark !== undefined) return { protect: String(mark) };
    if (hasOwn(raw, 'v')) {
      return own(raw, 'v') === SAVE_VERSION ? readState(raw) : { protect: 'version' }; // 1 이 아닌 명시 버전(v:2 포함)은 건드리지 않는다
    }
    return KNOWN.some((k) => hasOwn(raw, k)) ? readState(raw) : { protect: 'shape' }; // 버전 없는 예전 저장은 호환해서 읽는다
  }
  // 브라우저 개발 모드: 없음(null 키)과 읽을 수 없음을 구분한다. seenRaw 는 마지막으로 읽거나 쓴 원문
  let seenRaw = null;
  function decodeText(t) {
    if (t === null) return { state: fresh() };
    let raw;
    try { raw = JSON.parse(t); } catch (e) { return { protect: 'unparseable' }; }
    return raw === null ? { protect: 'unparseable' } : decodeSave(raw);
  }
  function readLocal() {
    try { seenRaw = localStorage.getItem(SAVE_KEY); } catch (e) { return { protect: 'unreadable' }; }
    return decodeText(seenRaw);
  }
  // 저장·초기화 직전에만 확인한다: 실행 중에 다른 곳이 저장을 읽을 수 없는/더 새로운 것으로 바꿨다면 그 뒤로는 쓰지 않는다 (재실행 전까지).
  // 네이티브 실행은 SaveStore 가 같은 확인을 파일 바이트로 한다
  function saveBlocked() {
    if (!readOnly && !handler()) {
      let t;
      try { t = localStorage.getItem(SAVE_KEY); } catch (e) { t = undefined; }
      if (t !== seenRaw) {
        const r = t === undefined ? { protect: 'unreadable' } : decodeText(t);
        if (r.protect) {
          readOnly = true; readOnlyReason = r.protect;
          chip.title = statusText();
          post({ type: 'log', msg: 'save protected: ' + r.protect });
        } else seenRaw = t; // 읽을 수 있는 다른 저장이면 예전처럼 이어서 쓴다
      }
    }
    return readOnly;
  }
  // 키 순서·공백과 상관없이 같은 내용인지 비교하려고 키를 정렬해 직렬화한다 (__proto__ 키도 안전하게 null 프로토타입 사용)
  const canon = (x) => JSON.stringify(x, (k, v) => (v && typeof v === 'object' && !Array.isArray(v)
    ? Object.keys(v).sort().reduce((o, key) => { o[key] = v[key]; return o; }, Object.create(null)) : v));
  // 이미 저장된 원문과 내용이 같은가 (v 가 없던 예전 저장은 다르다고 보아 v:1 로 다시 쓴다. 불리언과 숫자도 구분한다)
  function sameAsSeen(text) {
    try {
      const p = JSON.parse(seenRaw);
      if (!p || typeof p !== 'object' || Array.isArray(p)) return false;
      return canon(p) === canon(JSON.parse(text));
    } catch (e) { return false; }
  }
  // 앨범은 졸업·초기화 때만 바뀐다(배열을 통째로 바꾼다). 저장할 때마다 다시 직렬화하지 않게 배열 단위로 기억해 둔다
  let colRef = null, colText = '', colPlain = null;
  function colCache(col) {
    if (col !== colRef) { colRef = col; colText = JSON.stringify(col); colPlain = JSON.parse(colText); }
  }
  // launch: 시작할 때의 저장. lastSeen 을 갱신하지 않고, 내용이 그대로면 디스크에 쓰지 않는다 (네이티브에는 항상 보낸다)
  function persist(launch) {
    if (!S) return;
    if (!launch) S.lastSeen = Date.now();
    if (saveBlocked()) return;
    const col = S.collection && S.collection.length ? S.collection : null;
    const core = Object.assign({}, S);
    delete core.collection;
    if (!S.hatched) core.crack = Math.min(S.crack, 2); // 부화 연출 중의 3 은 저장하지 않는다
    if (col) colCache(col);
    if (handler()) {
      const state = JSON.parse(JSON.stringify(core));
      if (col) state.collection = colPlain;
      post({ type: 'save', state });
      return;
    }
    let text = JSON.stringify(core);
    if (col) text = text.slice(0, -1) + ',"collection":' + colText + '}';
    if (text === seenRaw) return;
    // 키 순서·공백만 다른 저장과의 비교(전체 파싱·정렬)는 시작할 때 한 번만 한다. 그 뒤의 저장은 lastSeen 이 달라 어차피 쓴다
    if (launch && seenRaw !== null && sameAsSeen(text)) return;
    try { localStorage.setItem(SAVE_KEY, text); seenRaw = text; } catch (e) { /* 저장이 막혀 있으면 이번 실행 동안만 */ }
  }

  /* ───────── 상태 ───────── */
  let S = null;
  let missions = [];
  let pet = null;
  let tmp = null; // 잠깐 뜨는 말 { text, q? } (q: 대기열이 띄운 것)
  let bubbleMode = null; // 'form' | 'text' | 'offer' | 'guide' | null
  let bubbleTimer = 0;
  let formOpen = false;
  let visLevel = 0; // 화면에 보이는 모습의 레벨 (연출이 끝나야 따라간다)
  let gen = 0; // 초기화할 때마다 올려 예전 타이머를 무시한다
  let jobs = [], busy = false; // 연출 대기열
  let confirmId = null;
  let nameDraft = '';
  let cardOpen = false;
  let cardView = 'missions'; // 카드에 보이는 화면: 'missions' | 'collection'(졸업 앨범)
  let learned = new Set(); // 앞 세대가 한 번이라도 끝낸 미션 id (불러올 때·졸업·초기화 때만 다시 계산)
  let gradJob = null; // 대기열에 서 있는 졸업식 (항상 맨 뒤에 둔다)
  let gradQueued = false; // 이번 세대의 졸업식을 이미 줄 세웠다 (같은 펫을 두 번 졸업시키지 않는다)
  let gradActive = false; // 졸업식 연출 중
  let gradWait = false; // 졸업식이 창이 보이기를 기다리는 중 (보일 때 처음부터 다시 한다)
  let expandedId = null;
  let albumBack = null; // 미션 카드에서 연 앨범이 돌아갈 자리 { top }. 메뉴·이름표로 연 앨범은 null (닫으면 바로 사라진다)
  let focusWant = null; // 다음 renderCard 뒤에 포커스를 둘 곳 { id, cls }. 포커스가 카드 안에 있을 때만 쓴다
  let hatching = false;
  let taps = [];
  let tapBag = [];
  let lastTap = -1;
  let lastRects = '';
  let axGranted = false; // 손쉬운 사용 권한 (네이티브가 알려 줌, 저장하지 않음)
  let lastPointKey = 'null'; // 마지막으로 네이티브에 보낸 가리킬 대상(JSON)
  let nativeVisible = true; // 네이티브가 알려 주는 창 보임 여부

  const $ = (id) => document.getElementById(id);
  const stage = $('stage'), card = $('card'), mover = $('mover'), bubbleEl = $('bubble'), cv = $('cv'), chip = $('chip');

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  /* ───────── 포커스 ───────── */
  // 다시 그리면 포커스를 쥔 단추가 사라진다. 포커스가 그 상자 안에 있었을 때만 제자리(또는 이어지는 단추)로 돌려놓고,
  // 다른 곳에 있거나 마우스로 누른 때에는 건드리지 않는다 (알림·권한 같은 수동 갱신이 포커스를 뺏지 않게)
  const focusIn = (box) => { const a = document.activeElement; return !!a && a !== box && box.contains(a); };
  function focusOn(e) {
    if (!e) return false;
    try { e.focus({ preventScroll: true }); } catch (err) { e.focus(); }
    return document.activeElement === e;
  }
  const itemOf = (id) => Array.from(card.querySelectorAll('.m-item')).find((i) => i.dataset.missionId === String(id)) || null;
  // 카드 안에서 포커스를 쥔 단추를 미션 id + 첫 클래스 + 같은 클래스 중 몇 번째인지로 기억한다
  function cardMark() {
    if (!focusIn(card)) return null;
    const a = document.activeElement, it = a.closest('.m-item');
    const cls = a.classList[0] || '';
    return { id: it ? it.dataset.missionId : null, cls, n: cls ? Math.max(0, Array.from((it || card).querySelectorAll('.' + cls)).indexOf(a)) : 0 };
  }
  // 같은 단추 → 그 미션의 줄 → 닫기 단추 순으로 찾는다
  function restoreCardFocus(mark) {
    if (!mark) return;
    const it = mark.id != null ? itemOf(mark.id) : null;
    const t = (mark.cls && (it || card).querySelectorAll('.' + mark.cls)[mark.n || 0]) || (it && it.querySelector('.m-row')) || card.querySelector('.card-x');
    focusOn(t);
  }
  // 펼친 줄의 제목이 스크롤 밖으로 밀려났으면 보이게 한다
  function revealItem(it) {
    const body = card.querySelector('.card-body');
    if (!it || !body) return;
    const top = Math.max(0, it.offsetTop - 4), row = it.querySelector('.m-row');
    if (top < body.scrollTop || it.offsetTop + (row ? row.offsetHeight : 0) > body.scrollTop + body.clientHeight) body.scrollTop = top;
  }

  const specName = () => SP[S.species].name;
  const nm = () => S.name || specName();
  const specOf = () => ({ species: S.species, stage: S.hatched ? STAGE(visLevel) : 0, crack: S.crack, plump: 0, shiny: S.shiny });
  const remaining = () => missions.filter((m) => !S.done[m.id]).length;
  const firstTodo = () => missions.find((m) => !S.done[m.id]) || null;
  const isLocked = (m) => m.needs === 'accessibility' && !axGranted && !S.done[m.id];
  const NONE = [];
  const album = () => S.collection || NONE;
  const atMax = () => S.hatched && S.level >= MAXLV; // 다 자란 펫은 졸업을 앞두고 있다
  function syncLearned() {
    let ids = null;
    try { ids = GEN && album().length ? GEN.learnedIds(album()) : null; } catch (e) { ids = null; }
    learned = ids instanceof Set ? ids : new Set();
  }
  // 권할 다음 미션: 안 끝냈고 잠기지 않은 미션 중, 앞 세대가 배운 적 없는 것 먼저
  function nextOffer() {
    let seen = null;
    for (const m of missions) {
      if (S.done[m.id] || isLocked(m)) continue;
      if (!learned.has(m.id)) return m;
      if (!seen) seen = m;
    }
    return seen;
  }
  const stepsOf = (m) => (m.steps && m.steps.length ? m.steps : [m.why || m.title]);
  const stepText = (st) => (typeof st === 'string' ? st : st && typeof st.text === 'string' ? st.text : '');
  const stepPoint = (st) => (st && typeof st === 'object' && st.point && typeof st.point === 'object' ? st.point : null);
  const later = (fn, ms) => { const g = gen; return window.setTimeout(() => { if (g === gen) fn(); }, ms); };

  /* ───────── 눌릴 수 있는 영역을 네이티브에 알린다 ───────── */
  function rectOf(e, pad, up) {
    const r = e.getBoundingClientRect();
    return { x: Math.round(r.left - pad), y: Math.round(r.top - pad - (up || 0)), w: Math.round(r.width + pad * 2), h: Math.round(r.height + pad * 2 + (up || 0)) };
  }
  function syncRects() {
    if (!S || !nativeVisible) return; // 숨겨진 동안은 읽지도 보내지도 않는다 (직접 부르는 곳도 같다)
    const rects = [];
    rects.push(rectOf(mover, 0, 24)); // 펫 캔버스 (폴짝 뛰는 높이까지)
    rects.push(rectOf(chip, 3));
    if (bubbleMode && bubbleMode !== 'text' && !cardOpen && !bubbleEl.hidden) rects.push(rectOf(bubbleEl, 3));
    if (cardOpen) rects.push(rectOf(card, 3));
    const key = JSON.stringify(rects);
    if (key === lastRects) return;
    lastRects = key;
    post({ type: 'hitRects', rects });
  }
  // 이벤트(크기·내용·속성 변화)가 몰려도 한 프레임에 한 번만 계산한다. 화면이 가려져 rAF 가 멈춰도 타이머가 대신한다
  let rectPending = false, rectRaf = 0, rectTimer = 0;
  function cancelRects() {
    rectPending = false;
    window.cancelAnimationFrame(rectRaf);
    window.clearTimeout(rectTimer);
  }
  function flushRects() {
    if (!rectPending) return;
    cancelRects();
    syncRects();
  }
  function scheduleRects() {
    if (rectPending || !S || !nativeVisible) return; // 숨겨진 동안은 보내지 않고, 다시 보일 때 한 번에 보낸다
    rectPending = true;
    rectRaf = window.requestAnimationFrame(flushRects);
    rectTimer = window.setTimeout(flushRects, 100);
  }
  // 보이는 상태로 돌아올 때: 네이티브가 놓쳤을 수 있으니 영역과 가리킬 대상을 모두 다시 알린다
  function resync() {
    if (!S) return;
    cancelRects();
    lastRects = '';
    lastPointKey = '\0';
    fitBubble(); fitChip();
    syncRects();
    syncPoint();
    resumeGraduation();
  }
  function setNativeVisible(v) {
    const was = nativeVisible;
    nativeVisible = v;
    try { if (typeof setLoopVisible === 'function') setLoopVisible(v); } catch (e) { post({ type: 'log', msg: 'setLoopVisible 실패: ' + e }); }
    if (v) resync(); // 보일 때마다 영역과 현재 가리킬 대상을 다시 알린다 (네이티브가 기다린다)
    else if (was) { cancelRects(); syncPoint(); } // 가린 동안은 영역 계산을 멈추고 가리키기도 거둔다
  }
  function watchGeometry() {
    if (typeof ResizeObserver === 'function') {
      const ro = new ResizeObserver(scheduleRects);
      [stage, mover, chip, bubbleEl, card].forEach((e) => ro.observe(e));
    }
    if (typeof MutationObserver === 'function') {
      // 펫 캔버스(cv)는 엔진이 매 프레임 transform 을 바꾸므로 보지 않는다. 말풍선·카드·이름표의 내용과 속성만 본다
      const mo = new MutationObserver(scheduleRects);
      [bubbleEl, card, chip].forEach((e) => mo.observe(e, { attributes: true, childList: true, subtree: true, characterData: true }));
      mo.observe(stage, { attributes: true, attributeFilter: ['class', 'style', 'hidden'] });
    }
    document.addEventListener('visibilitychange', () => { if (!document.hidden && nativeVisible) resync(); });
    window.addEventListener('pageshow', () => { if (nativeVisible) resync(); });
    window.addEventListener('focus', scheduleRects);
  }

  /* ───────── 가리키기: 안내 중인 단계의 point 를 네이티브에 알린다 ───────── */
  function currentPoint() {
    if (!S || !nativeVisible || !axGranted || !S.guide || S.guide.step < 0) return null;
    const gm = missions.find((m) => m.id === S.guide.id);
    if (!gm) return null;
    const steps = stepsOf(gm);
    return stepPoint(steps[Math.min(S.guide.step, steps.length - 1)]);
  }
  function syncPoint() {
    const target = currentPoint();
    const key = JSON.stringify(target);
    if (key === lastPointKey) return;
    lastPointKey = key;
    post({ type: 'point', target });
  }

  /* ───────── 말풍선 ───────── */
  // 무대 밖으로 나가지 않게 옆으로 민다 (꼬리는 펫 머리 위를 가리킨다)
  function fitBubble() {
    if (bubbleEl.hidden || cardOpen) return;
    const sr = stage.getBoundingClientRect(), mr = mover.getBoundingClientRect();
    const w = bubbleEl.offsetWidth, m = 8;
    const center = mr.left + mr.width / 2;
    const lo = sr.left + m + w / 2, hi = sr.right - m - w / 2;
    const want = lo > hi ? (sr.left + sr.right) / 2 : Math.min(hi, Math.max(lo, center));
    const d = Math.round(want - center);
    bubbleEl.style.setProperty('--shift', d + 'px');
    bubbleEl.style.setProperty('--tail', Math.round(Math.min(w - 12, Math.max(12, w / 2 - d))) + 'px');
  }
  function fitChip() {
    const sr = stage.getBoundingClientRect(), mr = mover.getBoundingClientRect();
    const w = chip.offsetWidth;
    const center = mr.left + mr.width / 2;
    const d = Math.min(0, Math.round(sr.right - 8 - w / 2 - center));
    chip.style.setProperty('--cs', d + 'px');
  }
  // 우선순위: 이름 짓기 폼 > 잠깐 뜨는 말 > 권하기/안내
  function renderBubble() {
    syncPoint();
    // 포커스가 말풍선 안에 있었다면 다시 그린 뒤에도 같은 자리에 둔다 (이름 칸은 커서 위치까지)
    const a = focusIn(bubbleEl) ? document.activeElement : null;
    const held = a ? { cls: a.classList[0] || '', input: a.tagName === 'INPUT', s: a.selectionStart, e: a.selectionEnd } : null;
    bubbleEl.textContent = '';
    const gm = S && S.hatched && S.guide ? missions.find((m) => m.id === S.guide.id) : null;
    bubbleMode = formOpen ? 'form' : tmp ? 'text' : gm ? (S.guide.step < 0 ? 'offer' : 'guide') : null;
    bubbleEl.classList.toggle('has-form', bubbleMode === 'form');
    bubbleEl.classList.toggle('is-ui', bubbleMode === 'form' || bubbleMode === 'offer' || bubbleMode === 'guide');
    if (!bubbleMode) { bubbleEl.hidden = true; if (held) focusOn(chip); syncRects(); return; }
    if (bubbleMode === 'form') {
      const q = el('div', '', '이름을 지어 주세요');
      q.id = 'name-q';
      bubbleEl.appendChild(q);
      const f = el('form');
      f.setAttribute('aria-labelledby', 'name-q');
      const inp = el('input');
      inp.type = 'text'; inp.maxLength = 8; inp.value = nameDraft; inp.setAttribute('aria-label', '펫 이름');
      inp.name = 'pet-name'; inp.autocomplete = 'off'; inp.spellcheck = false; inp.setAttribute('autocapitalize', 'off'); inp.setAttribute('enterkeyhint', 'done');
      inp.placeholder = specName(); // 비워 두면 이 이름(종 이름)이 된다
      inp.title = `여덟 글자까지 쓸 수 있어요. 비워 두면 ${specName()}`;
      inp.setAttribute('aria-describedby', 'name-q');
      inp.addEventListener('input', () => { nameDraft = inp.value; });
      const ok = el('button', '', '확인');
      ok.type = 'submit';
      f.append(inp, ok);
      f.addEventListener('submit', submitName);
      bubbleEl.appendChild(f);
    } else if (bubbleMode === 'text') {
      bubbleEl.textContent = tmp.text;
    } else if (bubbleMode === 'offer') {
      bubbleEl.appendChild(el('div', 'b-hd', '다음 미션'));
      bubbleEl.appendChild(el('div', 'b-title', gm.title));
      bubbleEl.appendChild(el('div', 'b-xp', `+${gm.xp || 0} EXP`));
      const row = el('div', 'b-btns');
      row.append(btn('b-go', '알려 줘', () => guideTo(0)), btn('b-later', '나중에', closeGuide));
      bubbleEl.appendChild(row);
    } else {
      const steps = stepsOf(gm);
      const i = Math.min(S.guide.step, steps.length - 1), last = i >= steps.length - 1;
      const hd = el('div', 'b-hd');
      const count = el('span', 'b-step', `${i + 1} / ${steps.length}`);
      count.title = `${steps.length}단계 중 ${i + 1}단계`;
      hd.append(el('span', 'b-name', gm.title), count);
      bubbleEl.appendChild(hd);
      const x = btn('b-x', '×', closeGuide);
      x.setAttribute('aria-label', '안내 그만');
      bubbleEl.appendChild(x);
      bubbleEl.appendChild(el('p', 'b-body', stepText(steps[i])));
      const row = el('div', 'b-btns');
      if (gm.permission === 'accessibility') row.appendChild(btn('b-go', '권한 요청하기', () => post({ type: 'requestPermission', name: 'accessibility' })));
      if (i > 0) row.appendChild(btn('b-prev', '이전', () => guideTo(i - 1, 'b-prev')));
      if (!last) row.appendChild(btn('b-next', '다음', () => guideTo(i + 1, 'b-next')));
      if (gm.settingsURL) row.appendChild(btn('b-set', '설정 열기', () => post({ type: 'openSettings', url: gm.settingsURL })));
      if (row.children.length) bubbleEl.appendChild(row);
      if (last) bubbleEl.appendChild(el('div', 'b-note', '해 보면 제가 알아챌게요'));
    }
    bubbleEl.hidden = false;
    if (held) {
      // 같은 단추가 없어졌으면(안내가 끝남·이름을 정함) 포커스를 잃지 않게 이름표로 옮긴다
      const t = held.input ? bubbleEl.querySelector('input') : held.cls ? bubbleEl.querySelector('.' + held.cls) : null;
      if (!focusOn(t)) focusOn(chip);
      else if (held.input) { try { t.setSelectionRange(held.s, held.e); } catch (err) { /* 무시 */ } }
    }
    fitBubble();
    syncRects();
  }
  function btn(cls, text, fn) {
    const b = el('button', cls, text);
    b.type = 'button';
    b.addEventListener('click', fn);
    return b;
  }
  // 잠깐 뜨는 말. 연출 대기열이 도는 중에는 끼어들지 않는다
  function say(text, ms, force) {
    if (formOpen && !force) return; // 이름 짓는 중에는 폼을 지우지 않는다
    if (busy && !force) return;
    if (ms === undefined) ms = 2600;
    tmp = { text };
    window.clearTimeout(bubbleTimer);
    if (ms) bubbleTimer = window.setTimeout(() => { tmp = null; renderBubble(); }, ms);
    renderBubble();
  }
  function hideBubble() {
    window.clearTimeout(bubbleTimer);
    tmp = null;
    renderBubble();
  }

  /* ───────── 연출 대기열 ───────── */
  // job(done): 끝나면 done() 을 부른다. 이름 짓는 중에는 멈춰 있다가 폼이 닫히면 이어 간다
  function enqueue(job, front) {
    if (front) jobs.unshift(job); else jobs.push(job);
    // 졸업식은 먼저 줄 선 다른 연출(마지막 미션·레벨 업)이 다 끝난 뒤 맨 마지막에 한다
    if (gradJob && job !== gradJob) {
      const i = jobs.indexOf(gradJob);
      if (i >= 0 && i < jobs.length - 1) { jobs.splice(i, 1); jobs.push(gradJob); }
    }
    if (!busy) nextJob();
  }
  function nextJob() {
    if (formOpen) { busy = false; return; }
    const job = jobs.shift();
    if (!job) {
      busy = false;
      if (tmp && tmp.q) tmp = null;
      renderBubble(); // 권하기/안내가 있으면 다시 그린다
      return;
    }
    busy = true;
    const g = gen;
    let called = false;
    job(() => { if (called || g !== gen) return; called = true; nextJob(); });
  }
  // 한 줄을 ms 동안 보여 주고 done
  function step(text, ms, done) {
    tmp = { text, q: true };
    window.clearTimeout(bubbleTimer);
    renderBubble();
    if (done) later(done, ms);
  }
  // 여러 줄을 차례로: announce([{text, ms}, …], done)
  function announce(lines, done, front) {
    enqueue((fin) => {
      let i = 0;
      const go = () => {
        if (i >= lines.length) { if (done) done(); fin(); return; }
        const l = lines[i++];
        step(l.text, l.ms || 2600, go);
      };
      go();
    }, front);
  }

  /* ───────── 권하기 · 안내 ───────── */
  // 안 끝낸 첫 미션을 권한다 (폼이 떠 있거나 이미 안내 중이면 하지 않는다)
  function offerNext() {
    if (!S.hatched || formOpen || S.guide || atMax()) return; // 졸업을 앞둔 펫에게는 새 미션을 권하지 않는다
    const m = nextOffer();
    if (!m) return;
    S.guide = { id: m.id, step: -1 };
    persist();
    renderBubble();
  }
  function guideTo(i, focusCls) {
    if (!S.guide) return;
    S.guide = { id: S.guide.id, step: i };
    persist();
    renderBubble();
    const b = (focusCls && bubbleEl.querySelector('.' + focusCls)) || bubbleEl.querySelector('.b-btns button');
    if (b) b.focus();
  }
  function closeGuide() {
    S.guide = null;
    persist();
    renderBubble();
  }

  /* ───────── 효과 ───────── */
  function floatText(txt) {
    const e = el('span', 'wpet-fx wpet-txt', txt);
    // 펫 왼쪽 옆에서 떠오른다 (머리 위에 두면 말풍선 글자와 겹친다)
    e.style.right = 'calc(100% - 14px)';
    e.style.top = '56px';
    mover.appendChild(e);
    window.setTimeout(() => e.remove(), 1600);
  }
  function flash() {
    const e = el('div', 'wpet-flash');
    stage.appendChild(e);
    window.setTimeout(() => e.remove(), 800);
  }

  /* ───────── 이름표 ───────── */
  function renderChip() {
    chip.textContent = '';
    if (!S.hatched) {
      chip.appendChild(el('span', '', '알'));
      const shown = cardOpen && cardView === 'collection';
      chip.setAttribute('aria-label', album().length || shown ? `알. 누르면 졸업 앨범을 ${shown ? '닫아요' : '열어요'}` : '알. 펫을 두드리면 깨어나요');
    } else {
      chip.appendChild(el('span', '', nm()));
      chip.appendChild(el('span', 'lv', 'LV' + S.level));
      const n = remaining();
      if (n > 0) {
        const dot = el('span', 'dot', String(n));
        dot.title = `남은 미션 ${n}개`;
        chip.appendChild(dot);
      }
      const left = !missions.length ? '' : n > 0 ? `, 남은 미션 ${n}개` : ', 미션을 모두 끝냈어요';
      chip.setAttribute('aria-label', `${nm()} 레벨 ${S.level}${left}. 누르면 미션 카드를 ${cardOpen && cardView === 'missions' ? '닫아요' : '열어요'}`);
    }
    chip.setAttribute('aria-controls', 'card');
    chip.classList.toggle('is-open', cardOpen);
    chip.setAttribute('aria-expanded', String(cardOpen));
    fitChip();
  }

  /* ───────── 미션 카드 ───────── */
  function renderCard() {
    const keep = card.querySelector('.card-body');
    const top = keep ? keep.scrollTop : 0;
    const mark = cardMark(), want = focusWant;
    focusWant = null;
    card.textContent = '';
    card.removeAttribute('data-view');
    card.setAttribute('aria-label', '미션 카드');
    if (!S.hatched) return;
    if (missions.length && remaining() === 0) card.appendChild(el('p', 'card-done', '미션을 모두 끝냈어요!'));

    const hd = el('div', 'card-hd');
    hd.appendChild(el('b', '', nm()));
    hd.appendChild(el('span', 'sub', `LV ${S.level} · ${ST[STAGE(S.level)].label}`));
    const bar = el('div', 'wpet-bar');
    bar.setAttribute('role', 'img');
    const need = NEED(S.level);
    const on = S.level >= MAXLV ? 20 : Math.min(20, Math.round((S.exp / need) * 20));
    bar.setAttribute('aria-label', `경험치 ${S.exp} / ${need}`);
    for (let i = 0; i < 20; i++) bar.appendChild(el('i', i < on ? 'on' : ''));
    hd.appendChild(bar);
    hd.appendChild(el('span', 'nx', S.level >= MAXLV ? '최고 레벨이에요!' : `다음 레벨까지 ${need - S.exp} EXP`));
    hd.appendChild(el('span', 'prog', `미션 ${missions.length - remaining()} / ${missions.length}`));
    const x = el('button', 'card-x', '×');
    x.type = 'button'; x.setAttribute('aria-label', '미션 카드 닫기');
    x.addEventListener('click', () => closeCard());
    hd.appendChild(x);
    if (album().length) {
      const a = btn('open-collection', `졸업 앨범 ${album().length}`, () => openCollection(true));
      a.setAttribute('aria-label', `졸업 앨범 열기, 졸업한 펫 ${album().length}마리`);
      hd.appendChild(a);
    }
    card.appendChild(hd);

    const body = el('div', 'card-body');
    // 묶음 이름별로, 처음 나온 순서대로
    const groups = [];
    missions.forEach((m) => {
      const name = m.group || '';
      let g = groups.find((x) => x.name === name);
      if (!g) { g = { name, list: [] }; groups.push(g); }
      g.list.push(m);
    });
    const nextM = atMax() ? null : nextOffer(); // 지금 권하는 미션 (말풍선이 권하는 것과 같은 규칙)
    groups.forEach((g) => {
      if (g.name) body.appendChild(el('h3', 'm-group', g.name));
      g.list.forEach((m) => body.appendChild(missionItem(m, m === nextM)));
    });
    card.appendChild(body);
    body.scrollTop = top;
    if (mark) restoreCardFocus(want || mark);
    syncRects();
  }
  // 줄을 여닫거나 다른 미션으로 옮긴 뒤: 그 줄이 보이게 한다 (포커스는 renderCard 가 돌려놓는다)
  function showItem(id, want) {
    focusWant = want || null;
    renderCard();
    revealItem(itemOf(id));
  }
  function missionItem(m, isNext) {
    const permissionMission = m.permission === 'accessibility';
    const needsPermissionAgain = !!S.done[m.id] && permissionMission && !axGranted;
    const done = !!S.done[m.id] && !needsPermissionAgain;
    const open = expandedId === m.id;
    const item = el('div', 'm-item' + (done ? ' is-done' : '') + (open ? ' is-open' : ''));
    const locked = isLocked(m);
    const needsAx = locked || needsPermissionAgain;
    const title = m.title || '미션', xp = m.xp || 0;
    item.dataset.missionId = String(m.id);
    item.dataset.state = done ? 'done' : needsAx ? 'locked' : 'todo';
    if (isNext && !done) item.dataset.next = 'true';
    const row = el('button', 'm-row');
    row.type = 'button';
    row.setAttribute('aria-expanded', String(open));
    row.appendChild(el('span', 't', title));
    row.appendChild(done ? el('span', 'tag ok', '✓ 완료') : needsAx ? el('span', 'tag lock', '권한 필요') : el('span', 'tag xp', `+${xp} EXP`));
    // 읽어 주는 이름: 제목 + 상태(완료 · 권한 필요 · 받을 경험치) + 지금 권하는 미션인지
    row.setAttribute('aria-label', `${title}, ${done ? '완료' : needsAx ? '권한 필요' : `경험치 +${xp} EXP`}${item.dataset.next ? ', 다음에 할 미션' : ''}`);
    if (item.dataset.next) row.setAttribute('aria-current', 'step');
    row.addEventListener('click', () => { expandedId = open ? null : m.id; confirmId = null; showItem(m.id); });
    item.appendChild(row);
    if (!open) return item;
    const d = el('div', 'm-detail');
    d.id = 'm-detail'; // 펼친 줄은 하나뿐이다
    row.setAttribute('aria-controls', 'm-detail');
    if (m.why) d.appendChild(el('p', '', m.why));
    if (m.steps && m.steps.length) {
      const ol = el('ol');
      ol.setAttribute('aria-label', '하는 방법');
      m.steps.forEach((t) => ol.appendChild(el('li', '', stepText(t))));
      d.appendChild(ol);
    }
    if (done) {
      if (m.after) d.appendChild(el('p', 'm-tip', '팁: ' + m.after));
      item.appendChild(d);
      return item;
    }
    if (locked) {
      const pm = missions.find((x) => x.permission === 'accessibility');
      d.appendChild(el('p', 'm-lock', pm && pm.title ? `먼저 “${pm.title}” 미션을 해 주세요` : '먼저 ‘펫에게 손쉬운 사용 권한 주기’ 미션을 해 주세요'));
      if (pm) {
        const la = el('div', 'm-acts');
        la.appendChild(btn('m-set', '권한 미션 보기', () => {
          expandedId = pm.id; confirmId = null;
          focusWant = { id: String(pm.id), cls: 'm-row' }; // 포커스도 권한 미션의 줄로 따라간다
          renderCard();
          const it = card.querySelector('.m-item.is-open'), body = card.querySelector('.card-body');
          if (it && body) body.scrollTop = Math.max(0, it.offsetTop - 4);
        }));
        d.appendChild(la);
      }
      item.appendChild(d);
      return item;
    }
    const acts = el('div', 'm-acts');
    if (permissionMission) acts.appendChild(btn('m-go', '권한 요청하기', () => post({ type: 'requestPermission', name: 'accessibility' })));
    if (!needsPermissionAgain) acts.appendChild(btn('m-go', '같이 하기', () => {
      const had = focusIn(card);
      closeCard();
      startGuide(m.id);
      if (had) focusOn(bubbleEl.querySelector('.b-btns button')); // 안내 말풍선의 첫 단추로 (없으면 closeCard 가 둔 이름표)
    }));
    if (m.settingsURL) acts.appendChild(btn('m-set', '설정 열기', () => post({ type: 'openSettings', url: m.settingsURL })));
    d.appendChild(acts);
    item.appendChild(d);
    if (permissionMission) return item;
    if (confirmId === m.id) {
      const c = el('div', 'm-confirm');
      c.setAttribute('role', 'group');
      c.setAttribute('aria-label', `${title} 미션을 직접 완료로 표시할까요?`);
      const yes = btn('m-yes', '정말 해 봤어요', () => { confirmId = null; closeCard(); completeMission(m.id, true); });
      yes.addEventListener('keydown', (e) => { if (e.repeat) e.preventDefault(); }); // 앞 단추에서 누르고 있던 Enter 가 그대로 확인까지 넘어가지 않게
      c.appendChild(yes);
      c.appendChild(btn('m-no', '취소', () => { confirmId = null; showItem(m.id, { id: String(m.id), cls: 'm-skip' }); }));
      d.appendChild(c);
    } else {
      d.appendChild(btn('m-skip', '해 봤는데 반응이 없어요', () => { confirmId = m.id; showItem(m.id, { id: String(m.id), cls: 'm-yes' }); }));
    }
    return item;
  }
  // 카드에서 고른 미션의 1단계부터 안내
  function startGuide(id) {
    S.guide = { id, step: 0 };
    persist();
    renderBubble();
  }
  function openCard() {
    if (!S.hatched) { say('먼저 알을 깨워 주세요'); return; }
    if (formOpen || gradActive) return; // 졸업식 중인 펫의 미션은 열지 않는다
    // 앨범에서 넘어오거나 이름표에 포커스를 둔 채 열면(키보드) 포커스를 카드 안으로 옮긴다. 메뉴·단축키로 연 때는 그대로 둔다
    const moved = (cardOpen && focusIn(card)) || document.activeElement === chip;
    cardOpen = true;
    cardView = 'missions';
    confirmId = null;
    albumBack = null;
    focusWant = null;
    const g = S.guide && missions.find((m) => m.id === S.guide.id);
    const m = g || nextOffer() || firstTodo();
    expandedId = m ? m.id : null;
    card.hidden = false;
    stage.classList.add('card-open');
    renderCard();
    renderChip();
    const it = card.querySelector('.m-item.is-open'), body = card.querySelector('.card-body');
    if (it && body) body.scrollTop = Math.max(0, it.offsetTop - 4); // 펼친 줄이 보이게
    if (moved) focusOn(card.querySelector('.m-item.is-open .m-row') || card.querySelector('.card-x')); // 펼친 줄에서 바로 이어 갈 수 있게
    syncRects();
  }
  function closeCard() {
    if (!cardOpen) return;
    const back = focusIn(card);
    cardOpen = false;
    cardView = 'missions';
    albumBack = null;
    focusWant = null;
    card.hidden = true;
    stage.classList.remove('card-open');
    renderChip();
    renderBubble(); // 숨겨 둔 말풍선(이름 짓기 폼 포함)을 다시 그린다
    if (back) focusOn((formOpen && bubbleEl.querySelector('input')) || chip); // 카드를 닫으면 하던 곳(이름 칸·이름표)으로
    syncRects();
  }
  // 앨범이 떠 있을 때는 미션으로 바꾸고, 미션을 열 수 없는 때(알·이름 짓기·졸업식)면 닫는다
  function toggleCard() {
    if (cardOpen && cardView === 'collection' && S.hatched && !formOpen && !gradActive) {
      if (canBack()) leaveCollection(); else openCard(); // 미션에서 연 앨범이면 보던 자리로 돌아간다
      return;
    }
    if (cardOpen) closeCard(); else openCard();
  }
  // 열려 있는 카드를 지금 상태로 다시 그린다
  function refreshCard() {
    if (!cardOpen) return;
    if (cardView === 'collection') renderCollection(); else renderCard();
  }

  /* ───────── 졸업 앨범 ───────── */
  // 그리기는 collection.js 가 한다 (card.dataset.view = 'collection', aria-label, .collection-close, .collection-entry)
  function renderCollection() {
    card.textContent = '';
    try {
      MacPetCollection.render(card, album(), leaveCollection, { back: canBack() });
    } catch (e) {
      post({ type: 'log', msg: '졸업 앨범 그리기 실패: ' + e });
    }
    if (card.dataset.view !== 'collection') card.dataset.view = 'collection';
  }
  // 알(첫 알 포함)·이름 짓는 중·졸업식 중에도 열 수 있다. 이미 열려 있으면 쪽·포커스를 그대로 둔다
  // fromMissions: 미션 카드의 앨범 단추로 열었다. 그때만 닫기 단추가 '미션으로 돌아가기'가 된다
  function openCollection(fromMissions) {
    if (!S || (cardOpen && cardView === 'collection')) return;
    if (typeof MacPetCollection !== 'object' || !MacPetCollection || typeof MacPetCollection.render !== 'function') {
      post({ type: 'log', msg: '졸업 앨범을 열 수 없음: collection.js 없음' });
      return;
    }
    const from = fromMissions === true && cardOpen && cardView === 'missions' ? card.querySelector('.card-body') : null;
    albumBack = from ? { top: from.scrollTop } : null;
    cardOpen = true;
    cardView = 'collection';
    confirmId = null;
    focusWant = null;
    card.hidden = false;
    stage.classList.add('card-open');
    renderCollection();
    renderChip();
    const x = card.querySelector('.collection-close');
    if (x) x.focus();
    syncRects();
  }
  const canBack = () => !!albumBack && cardOpen && cardView === 'collection' && S.hatched && !formOpen && !gradActive;
  // 앨범의 닫기 단추·Esc: 미션 카드에서 열었으면 펼친 줄·스크롤을 그대로 둔 채 돌아가고, 아니면 바로 닫는다
  function leaveCollection() {
    if (!canBack()) { closeCard(); return; }
    const top = albumBack.top;
    albumBack = null;
    cardView = 'missions';
    focusWant = null;
    renderCard();
    renderChip();
    // 돌아가기는 사용자가 직접 한 동작이다. WK 는 pointerdown 에서 포커스를 떨어뜨리기도 하므로 앨범 안에 있었는지 따지지 않고 들어온 단추로 돌려놓는다
    focusOn(card.querySelector('.open-collection') || card.querySelector('.card-x'));
    const body = card.querySelector('.card-body');
    if (body) body.scrollTop = top;
    syncRects();
  }

  /* ───────── 저장 + 다시 그리기 ───────── */
  function commit() {
    persist();
    if (pet) { pet.spec = specOf(); pet.key = ''; }
    renderChip();
    if (cardOpen && cardView === 'missions') renderCard(); // 앨범은 졸업할 때만 바뀐다
    syncPoint();
    syncRects();
  }

  /* ───────── 경험치와 진화 ───────── */
  // 경험치는 바로 넣고, 레벨 업·진화 연출은 대기열에서 차례로 보여 준다
  function grantExp(n) {
    const c = S;
    if (!c.hatched || c.level >= MAXLV || !n) return null;
    const from = c.level;
    c.exp += n;
    while (c.level < MAXLV && c.exp >= NEED(c.level)) { c.exp -= NEED(c.level); c.level++; }
    if (c.level >= MAXLV) c.exp = 0;
    return { leveled: c.level > from, from, to: c.level, evolved: STAGE(c.level) > STAGE(from) };
  }
  // 레벨 업 문구, 진화면 진화 연출. 끝나면 done
  function levelScene(ev, done) {
    const p = pet;
    if (!ev || !ev.leveled || !p) { done(); return; }
    if (!ev.evolved) {
      visLevel = ev.to; p.spec = specOf(); p.key = '';
      p.play('celebrate');
      step(`레벨 업! LV${ev.to}`, 2000, done);
      return;
    }
    const after = STAGE(ev.to);
    p.evolveFrom = Object.assign({}, specOf(), { stage: STAGE(ev.from) });
    visLevel = ev.to; p.spec = specOf(); p.key = '';
    p.play('evolve');
    step('어? 몸이 이상해요…', 2400);
    let fin = false;
    const after1 = () => {
      if (fin) return;
      fin = true;
      p.hooks.end = null;
      flash();
      p.play('celebrate');
      step(after < 3 ? '성장기가 됐어요! 무럭무럭 크는 중' : '완성형이 됐어요! 그동안 고마워요', 3200, done);
    };
    p.hooks.end = (d) => { if (d === 'evolve') after1(); };
    later(after1, 7000); // 혹시 끝 알림이 안 오면 그대로 넘어간다
  }

  /* ───────── 졸업 ───────── */
  // Lv10 이 된 펫은 그 모습 그대로 먼저 저장되고(commit), 연출이 끝나면 앨범에 들어가며 새 알이 온다.
  // 졸업 전에 앱이 꺼졌다면 저장에는 Lv10 펫이 남아 있으니 다음 실행의 greet 가 졸업식부터 이어 간다 (따로 표시를 저장하지 않는다)
  function scheduleGraduation() {
    if (gradQueued || !S || !atMax() || !GEN) return;
    gradQueued = true;
    gradJob = graduationScene;
    enqueue(gradJob);
  }
  function graduationScene(fin) {
    gradJob = null;
    const p = pet;
    if (!atMax() || !p) { gradQueued = false; fin(); return; }
    // 창이 가려져 있으면 졸업식을 미룬다. 저장에는 Lv10 펫이 그대로 남고, 다시 보일 때(resync) 처음부터 한다
    const unseen = () => { if (shown()) return false; gradActive = false; gradWait = true; fin(); return true; };
    if (unseen()) return;
    gradActive = true;
    closeCard(); // 떠나는 펫의 미션 카드·앨범을 닫아 졸업식이 보이게 한다
    if (S.guide) { S.guide = null; syncPoint(); } // 하던 안내와 가리키기는 여기서 끝 (저장은 졸업 때 한 번만)
    visLevel = S.level; p.spec = specOf(); p.key = ''; // 다 자란 모습으로 보낸다
    p.play('celebrate');
    step(`${nm()}, 다 자랐어요! 졸업을 축하해요`, 2600, () => {
      if (unseen()) return; // 도중에 가려졌으면 앨범에 넣지 않고 물러난다
      p.play('wave');
      step('졸업 앨범에서 기다릴게요. 새 알을 잘 부탁해요!', 2600, () => { if (!unseen()) graduateNow(fin); });
    });
  }
  const shown = () => nativeVisible && !document.hidden;
  // 창이 다시 보이면 미뤄 둔 졸업식을 줄 맨 뒤에 다시 세운다 (타이머로 살피지 않고 보임 이벤트에서만 부른다)
  function resumeGraduation() {
    if (!gradWait || !shown()) return;
    gradWait = false;
    gradJob = graduationScene;
    enqueue(gradJob);
  }
  // 앨범에 기록하고 새 알로 바꾼 뒤 한 번에 저장한다
  function graduateNow(fin) {
    let next = null;
    // 이름을 짓기 전에 다 자란 예전 저장은 묻지 않고 종 이름으로 기록한다
    try { next = GEN.graduate(S.name ? S : Object.assign({}, S, { name: specName() }), fresh, new Date().toISOString()); } catch (e) { post({ type: 'log', msg: '졸업 실패: ' + e }); }
    const before = album().length;
    if (!next || next.hatched !== false || !Array.isArray(next.collection) || next.collection.length !== before + 1) {
      // 기록하지 못했으면 펫을 그대로 둔다 (이번 실행에서는 다시 시도하지 않고, 다음 실행이 이어 간다)
      if (next) post({ type: 'log', msg: '졸업 실패: 새 상태가 올바르지 않음' });
      gradActive = false;
      fin();
      return;
    }
    flash();
    startGeneration(next); // 저장을 쓸 수 없는 실행이면 persist 가 건너뛰고 이번 실행 동안만 이어진다
    say(eggHint(), 0, true);
  }
  const eggHint = () => (album().length
    ? '새 알이 왔어요! 톡톡 두드려서 깨워 주세요. 졸업한 친구는 ‘알’ 이름표를 누르면 졸업 앨범에서 만날 수 있어요'
    : '알이 도착했어요! 톡톡 두드려서 깨워 주세요');

  /* ───────── 알 깨기 · 이름 짓기 ───────── */
  function tapEgg() {
    if (hatching) return;
    const c = S, p = pet;
    c.crack++;
    if (c.crack < 3) {
      commit();
      p.play('eggtap');
      say(c.crack === 1 ? '꿈틀…!' : '조금만 더!', 0);
      return;
    }
    // 세 번째: 부화 연출. 부화가 끝나기 전에는 저장하지 않는다 (중간에 끝나면 금 2 인 알로 돌아온다)
    p.spec = specOf(); p.key = '';
    p.play('eggtap');
    hatching = true;
    hideBubble();
    // 연출 도중 초기화되면 gen 이 바뀌어 아래 콜백은 모두 무시된다
    later(() => {
      flash();
      c.hatched = true; c.crack = 0; c.level = 1; c.exp = 0; visLevel = 1;
      commit();
      p.play('surprise');
      later(() => {
        p.play('pet');
        if (c.shiny) for (let i = 0; i < 6; i++) later(() => p.emit('spark'), i * 120);
        hatching = false;
        askName(true);
      }, 700);
    }, 420);
  }
  // focus: 방금 두드려 깨운 알이면 이름 칸으로 바로 간다. 시작할 때 이어 묻는 경우에는 포커스를 옮기지 않는다
  function askName(focus) {
    closeCard();
    nameDraft = S.name || specName();
    formOpen = true;
    window.clearTimeout(bubbleTimer);
    tmp = null;
    renderBubble();
    const inp = focus ? bubbleEl.querySelector('input') : null;
    if (inp && focusOn(inp)) { try { inp.setSelectionRange(inp.value.length, inp.value.length); } catch (err) { /* 무시 */ } }
  }
  function submitName(e) {
    e.preventDefault();
    S.name = Array.from(nameDraft.trim()).slice(0, 8).join('') || specName();
    formOpen = false;
    commit();
    pet.play('celebrate');
    announce([{ text: `${S.name}! 잘 부탁해요`, ms: 2600 }], afterIntro, true);
    reconcileAccessibility(); // 인사 뒤에 줄을 세워 두되 경험치는 지금 저장한다
  }
  // 개발용: 두드리지 않고 바로 부화 (이름은 종 이름)
  function hatchNow() {
    S.hatched = true; S.crack = 0; S.level = 1; S.exp = 0; visLevel = 1;
    if (!S.name) S.name = specName();
    formOpen = false; hatching = false;
    hideBubble();
    flash();
    commit();
    pet.play('surprise');
    announce([{ text: `${S.name}! 잘 부탁해요`, ms: 2600 }], afterIntro, true);
    reconcileAccessibility();
  }

  /* ───────── 펫 두드리기 ───────── */
  function petIt() {
    const c = S, p = pet;
    if (!p || hatching || gradActive) return; // 졸업식 중에는 인사만 받는다
    if (!c.hatched) { tapEgg(); return; }
    if (p.state === 'sulk') { p.play('reunion'); say('보고 싶었어요!'); return; }
    if (p.state === 'sleep') { p.play('surprise'); say('음냐… 깼어요'); return; }
    if (['evolve', 'eat', 'dizzy'].includes(p.state)) return;
    // 이스터에그: 3초 안에 10번 누르면 어지러워한다
    const now = performance.now();
    taps = taps.filter((t) => now - t < 3000);
    taps.push(now);
    if (taps.length >= 10) { taps = []; p.play('dizzy'); say('어지러워요~ @_@', 2400); return; }
    // 섞어서 하나씩 꺼내 같은 동작이 연달아 나오지 않게 한다
    if (!tapBag.length) {
      const bag = TAP_POSES.map((_, i) => i);
      for (let i = bag.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = bag[i]; bag[i] = bag[j]; bag[j] = t; }
      if (bag[bag.length - 1] === lastTap) { const t = bag[0]; bag[0] = bag[bag.length - 1]; bag[bag.length - 1] = t; }
      tapBag = bag;
    }
    const idx = tapBag.pop();
    const pose = TAP_POSES[idx];
    lastTap = idx;
    p.play(pose.s);
    const day = localDay();
    if (c.petDay !== day) { c.petDay = day; c.pets = 0; }
    let ev = null;
    if (c.pets < 5) { c.pets++; ev = grantExp(2); if (ev) floatText('+2 EXP'); }
    commit();
    if (ev && ev.leveled) enqueue((fin) => levelScene(ev, fin));
    scheduleGraduation(); // Lv10 이 됐다면 위 연출 뒤에 졸업식
    say(pick(pose.t));
  }

  /* ───────── 미션 ───────── */
  // 성공 연출: 성공 문구 → 레벨 업(진화) → after 팁 → 다음 권하기
  function missionScene(m, xp, ev, done) {
    if (pet && !(ev && ev.evolved)) pet.play('celebrate');
    if (xp) floatText(`+${xp} EXP`);
    step(`${m.title} 성공! +${xp} EXP`, 2400, () => {
      levelScene(ev, () => {
        const end = () => {
          // 다른 미션을 안내 중이면 그대로 돌아가고, 뒤에 이어질 연출이 있으면 그쪽이 마무리한다
          if (jobs.length || S.guide) { done(); return; }
          if (remaining() === 0) step('미션을 모두 끝냈어요! 대단해요', 2600, done);
          else { offerNext(); done(); }
        };
        if (m.after) step(m.after, 4200, end); else end();
      });
    });
  }
  function completeMission(id, manual) {
    const m = missions.find((x) => x.id === id);
    if (!S.hatched || !m || S.done[id] || gradActive) return false; // 졸업식 중에 온 신호는 다음 세대가 다시 배운다
    if (m.permission === 'accessibility' && (!axGranted || !S.name || formOpen || hatching)) return false; // 이름을 짓기 전의 권한 신호는 기다렸다가 reconcile 이 처리한다
    S.done[id] = new Date().toISOString();
    if (manual) S.manual[id] = true;
    if (S.guide && S.guide.id === id) S.guide = null;
    syncPoint();
    const xp = m.xp || 0;
    const ev = grantExp(xp);
    commit();
    enqueue((fin) => missionScene(m, xp, ev, fin));
    scheduleGraduation(); // Lv10 이 됐다면 위 연출 뒤에 졸업식
    return true;
  }

  /* ───────── 네이티브 이벤트 ───────── */
  // 알일 때 건너뛴 권한 미션을 현재 권한 상태로 맞춘다. 부화·이름 짓기가 끝난 뒤에만, 권한이 켜져 있을 때만, 한 번만 준다
  function reconcileAccessibility() {
    if (!S || !S.hatched || !S.name || formOpen || hatching || !axGranted) return;
    const m = missions.find((x) => x.permission === 'accessibility');
    if (m && !S.done[m.id]) completeMission(m.id);
  }
  // 이름 짓기·인사 연출이 끝난 뒤: 놓친 권한 미션을 맞추고 다음 미션을 권한다
  function afterIntro() { reconcileAccessibility(); offerNext(); }
  function onPermission(ev) {
    if (ev.name !== 'accessibility') return;
    const g = !!ev.granted;
    if (g === axGranted) return;
    axGranted = g;
    if (!S) return;
    renderChip();
    if (cardOpen && cardView === 'missions') renderCard();
    syncPoint();
    reconcileAccessibility();
    // 권하기가 비어 있고 연출 중이 아니면 다음 미션을 권한다 (풀린 미션을 억지로 권하진 않음: 연출 중이면 그쪽 흐름에 맡김)
    if (S.hatched && !busy && !formOpen && !S.guide) offerNext();
  }
  function handleNative(ev) {
    if (!ev) return;
    if (ev.type === 'mission') { completeMission(ev.id); return; }
    if (ev.type === 'permission') { onPermission(ev); return; }
    if (ev.type === 'visibility') {
      if (typeof ev.visible === 'boolean') setNativeVisible(ev.visible); // 문서화된 {type:"visibility", visible:boolean} 만 받는다
      return;
    }
    if (ev.type !== 'command') return;
    if (ev.name === 'toggleMissions') toggleCard();
    else if (ev.name === 'showMissions') { if (!cardOpen || cardView !== 'missions') openCard(); } // 이미 열려 있으면 선택·스크롤·포커스를 그대로 둔다. 앨범이 떠 있으면 미션으로 바꾼다
    else if (ev.name === 'showCollection') openCollection(); // 첫 알이어도(빈 앨범) 열린다. 이미 열려 있으면 그대로
    else if (ev.name === 'reset') resetAll();
    else if (ev.name === 'devCompleteNext') {
      if (!S.hatched) { hatchNow(); return; }
      const next = missions.find((m) => !S.done[m.id] && !isLocked(m) && (m.permission !== 'accessibility' || axGranted));
      if (next) completeMission(next.id);
    }
  }

  /* ───────── 펫 만들기 · 초기화 ───────── */
  function greet() {
    const note = readOnly ? [{ text: statusText(), ms: 5000 }] : [];
    if (!S.hatched) {
      const egg = () => { if (!S.crack) say(eggHint(), 0, true); };
      if (note.length) announce(note, egg); else egg();
      return;
    }
    if (atMax()) {
      // 졸업식 전에 끝났던 실행: 이름이 없어도 묻지 않고(종 이름으로) 졸업식을 이어 간다
      if (note.length) announce(note);
      scheduleGraduation();
      if (gradQueued) return;
    }
    if (!S.name) { askName(); return; } // 이름을 짓기 전에 끝났다면 이어서 묻는다
    const n = remaining(), total = missions.length;
    let t;
    if (!total) t = `${nm()}예요. 반가워요!`;
    else if (n === 0) t = '미션을 모두 끝냈어요! 대단해요';
    else if (n === total) t = `같이 macOS 기능을 써 봐요! 미션이 ${n}개 있어요`;
    else t = `미션이 ${n}개 남았어요. 천천히 해요`;
    announce(note.concat([{ text: t, ms: 2600 }]), afterIntro);
  }
  function makePet() {
    pet = new Pet(mover, cv, specOf(), { scale: 3, autoSpecial: true });
  }
  function dispose(p) {
    if (!p) return;
    const i = PETS.indexOf(p);
    if (i >= 0) PETS.splice(i, 1);
  }
  // 세대 바꾸기(초기화·졸업): gen 을 올려 예전 타이머·연출·안내를 모두 끊고 새 알로 화면을 다시 만든다. 저장은 한 번만 한다
  function startGeneration(state) {
    dispose(pet);
    window.clearTimeout(bubbleTimer);
    gen++; jobs = []; busy = false; confirmId = null; albumBack = null; focusWant = null;
    gradJob = null; gradQueued = false; gradActive = false; gradWait = false;
    S = state;
    syncLearned();
    visLevel = 0;
    tmp = null; formOpen = false; hatching = false; expandedId = null; taps = []; tapBag = []; lastTap = -1;
    if (cardOpen && cardView === 'missions') closeCard(); // 지난 펫의 미션 카드는 닫는다
    if (cardOpen) {
      // 열어 둔 앨범은 그대로 두고 내용만 맞춘다
      const had = focusIn(card);
      refreshCard();
      const x = had && card.querySelector('.collection-close');
      if (x) x.focus();
    }
    renderBubble();
    makePet();
    persist();
    renderChip();
    syncRects();
  }
  function resetAll() {
    // 보호 중인 저장은 지우지 않는다 (네이티브 delete 도 건너뛴 상태). 이번 실행의 상태도 그대로 둔다
    if (saveBlocked()) { say(statusText(), 4000, true); return; }
    closeCard();
    startGeneration(fresh()); // 앨범까지 모두 지우고 첫 알부터
    later(greet, 700);
  }

  // 끌어서 옮기기: 5px 넘게 움직이면 dragStart 를 한 번 보내고, 뒤따르는 click 은 두드리기로 치지 않는다
  let dn = null; // 누르고 있는 중 { id, x, y }
  let dragged = false, dragAt = 0, dragUpAt = 0;
  function dragEnd() {
    dn = null;
    cv.classList.remove('is-dragging');
  }
  cv.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    dragged = false; dragAt = 0; dragUpAt = 0; // 새로 누르면 이전 끌기 표시는 확실히 푼다
    cv.classList.remove('is-dragging');
    dn = { id: e.pointerId, x: e.clientX, y: e.clientY };
    try { cv.setPointerCapture(e.pointerId); } catch (err) { /* 무시 */ }
  });
  cv.addEventListener('pointermove', (e) => {
    if (!dn || dragged || e.pointerId !== dn.id) return;
    if (Math.hypot(e.clientX - dn.x, e.clientY - dn.y) <= 5) return;
    dragged = true;
    dragAt = performance.now();
    cv.classList.add('is-dragging');
    post({ type: 'dragStart' });
  });
  const pointerEnd = () => {
    if (dragged) dragUpAt = performance.now();
    dragEnd();
  };
  cv.addEventListener('pointerup', pointerEnd);
  cv.addEventListener('pointercancel', pointerEnd);
  cv.addEventListener('click', () => {
    if (dragged) {
      const now = performance.now();
      const fresh = now - dragAt < 400 || (dragUpAt && now - dragUpAt < 60);
      dragged = false; dragAt = 0; dragUpAt = 0;
      dragEnd();
      if (fresh) return; // 끌기의 끝에 따라온 click
    }
    petIt();
  });
  cv.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); petIt(); } });
  chip.addEventListener('click', () => {
    if (!S.hatched) {
      // 알: 앨범이 있으면 앨범을 여닫고, 첫 알이면 깨우는 법을 알려 준다
      if (cardOpen) closeCard();
      else if (album().length) openCollection();
      else say('먼저 알을 깨워 주세요');
      return;
    }
    toggleCard();
  });
  // Esc: 확인 묻기 → 앨범(돌아가기) → 카드 순으로 한 겹씩 닫는다
  card.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || e.defaultPrevented || e.isComposing || !cardOpen) return;
    e.preventDefault();
    if (cardView === 'collection') leaveCollection();
    else if (confirmId) { const id = String(confirmId); confirmId = null; showItem(id, { id, cls: 'm-skip' }); }
    else closeCard();
  });
  window.addEventListener('resize', () => { fitBubble(); fitChip(); scheduleRects(); });

  async function init() {
    makeIcons();
    let loaded;
    if (boot) {
      missions = Array.isArray(boot.missions) ? boot.missions : [];
      loaded = decodeSave(boot.save);
    } else {
      try {
        const r = await fetch('missions.json');
        missions = await r.json();
      } catch (e) {
        missions = [];
        post({ type: 'log', msg: 'missions.json 읽기 실패: ' + e });
      }
      loaded = readLocal();
    }
    if (loaded.protect) {
      // 원본은 그대로 두고, 이번 실행은 저장하지 않는 임시 상태로만 논다
      readOnly = true; readOnlyReason = loaded.protect;
      S = fresh();
      post({ type: 'log', msg: 'save protected: ' + loaded.protect });
    } else {
      S = loaded.state;
    }
    // 저장된 안내가 없는 미션·끝난 미션을 가리키면 버리고, 단계가 끝을 넘으면 마지막 단계로 맞춘다
    if (S.guide) {
      const gm = missions.find((m) => m.id === S.guide.id);
      if (!S.hatched || !gm || S.done[S.guide.id] || atMax()) S.guide = null; // 졸업을 앞둔 펫은 안내를 이어 가지 않는다
      else S.guide.step = Math.min(S.guide.step, stepsOf(gm).length - 1);
    }
    visLevel = S.level;
    syncLearned();
    syncPoint(); // 저장된 안내를 복원한 경우(권한이 이미 왔다면) 가리킬 대상을 알린다
    makePet();
    startLoop();
    renderChip();
    if (readOnly) chip.title = statusText();
    persist(true); // 네이티브는 ready 전에 정리된 상태를 받아야 감시를 시작한다. 읽기 전용이면 아무것도 쓰지 않고, 바뀐 게 없으면 디스크도 건드리지 않는다
    post({ type: 'ready' });
    syncRects();
    watchGeometry();
    ready = true;
    while (queue.length) handleNative(queue.shift());
    later(greet, 700);
  }
  init().catch((e) => post({ type: 'log', msg: 'init 실패: ' + ((e && e.stack) || e) }));
})();
