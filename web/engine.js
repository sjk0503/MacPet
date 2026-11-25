// 웍스+ 펫 도트 엔진(engine.ts)을 그대로 옮긴 파일. export 만 지워 일반 스크립트로 쓴다. 그리기 로직은 고치지 않는다.
/* eslint-disable */
// 시안에서 옮겨 온 그리기 엔진이라 린트·타입 검사를 끈다 (WrksPet.tsx 가 감싼다)
// @ts-nocheck
/**
 * 웍스+ 펫 도트 엔진 — 32x32 픽셀 캐릭터를 캔버스에 프레임 단위로 그린다.
 * 시안(웍스+ 펫 시안)에서 쓰던 엔진을 그대로 옮겨 왔다. 타입 검사는 끄고 WrksPet.tsx 가 감싼다.
 */
const reducedMQ = typeof matchMedia !== 'undefined' ? matchMedia('(prefers-reduced-motion: reduce)') : null;
let reduced = !!(reducedMQ && reducedMQ.matches);
if (reducedMQ) {
  const onReduced = (e) => { reduced = e.matches; };
  if (reducedMQ.addEventListener) reducedMQ.addEventListener('change', onReduced); else if (reducedMQ.addListener) reducedMQ.addListener(onReduced);
}
const rnd = (a, b) => a + Math.random() * (b - a);
const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const josa = (w, withB, noB) => { const c = w.charCodeAt(w.length - 1); return (c >= 0xac00 && c <= 0xd7a3 && (c - 0xac00) % 28 === 0) ? noB : withB; };
const OUT = '#3d2c35';

const SP = {
  nyang: { name: '찹냥이', kind: '찹쌀고양이', feature: 'cat', exp: 2.2, desc: '하얀 찹쌀 고양이. 머리와 왼쪽 귀, 꼬리 끝이 귤색이에요. 성장기부터 방울 목걸이를 하고, 완성형이 되면 수염이 나고 꼬리가 복슬해지며 방울이 커져요.',
    body: '#fffaf2', shade: '#efdcc8', hi: '#ffffff', patch: '#f8a24f', patchShade: '#e08137', inner: '#ffa9bb', eye: '#33232c', blush: '#ff98ad', acc: '#f0606f', bell: '#ffd23f', feet: '#ffd3da', egg: '#f8a24f' },
  bam: { name: '밤팅이', kind: '군밤', feature: 'chestnut', eyeStyle: 'googly', desc: '갓 구운 군밤. 정수리가 톡 갈라져 노란 속이 보이고, 눈이 살짝 몰려 있어 늘 멍해 보여요. 완성형이 되면 짙은 눈썹이 생기고 껍질이 더 크게 벌어져요.',
    body: '#c27445', shade: '#97512b', hi: '#e09a66', cap: '#f6dfae', capShade: '#e3c58b', capDot: '#c9a46a', crack: '#ffd36a', eye: '#2a1812', blush: '#ff8f80', egg: '#c27445' },
  hammy: { name: '볼빵이', kind: '햄스터', feature: 'hamster', desc: '볼주머니가 빵빵한 햄스터. 성장기부터 넥타이를 매고 출근하다가, 완성형이 되면 해바라기 꽃을 통째로 안고 다녀요.',
    body: '#f3b46a', shade: '#d9924a', hi: '#ffd9a6', cream: '#fff4df', creamShade: '#f0dcbc', inner: '#ffb0a3', tie: '#4a6fd1', tieKnot: '#34519e', eye: '#2d1f1a', blush: '#ff8f8f', feet: '#ffc9c0', arm: '#fff4df', egg: '#f3b46a' },
  mung: { name: '멍뭉콩', kind: '강아지', feature: 'puppy', exp: 2.2, desc: '귀가 쫑긋한 강아지. 오른쪽 눈가에 연한 얼룩이 있어요. 성장기부터 하늘색 손수건을 두르고, 완성형이 되면 귀가 더 넓어지고 늘 혀를 빼꼼 내밀어요.',
    body: '#fbe6c4', shade: '#ecc790', hi: '#fff6e6', ear: '#a8673a', earShade: '#86502b', earIn: '#f2a99a', spot: '#e6b580', nose: '#2d1f1a', eye: '#2d1f1a', blush: '#ff9d9d', acc: '#5fb4f0', accShade: '#3d8fd0', egg: '#a8673a' },
  peng: { name: '펭글이', kind: '아기펭귄', feature: 'penguin', adj: { gap: -1 }, desc: '뒤뚱뒤뚱 아기 펭귄. 성장기부터 빨간 목도리를 하고, 완성형이 되면 얼굴 옆에 노란 깃털이 나요.',
    body: '#4a5a8c', shade: '#36436d', hi: '#6d7fb5', face: '#fdfcff', faceShade: '#e4e6f2', beak: '#ffa73a', beakShade: '#e9831a', eye: '#22202a', blush: '#ff9db0', feet: '#ffa73a', acc: '#ef4a3c', accShade: '#c7342a', egg: '#4a5a8c' },
  chick: { name: '삐약이', kind: '병아리', feature: 'chick', desc: '갓 태어난 병아리. 아기 때는 알껍데기 모자를 쓰고, 성장기에 껍데기를 벗으면 깃털이 솟아요. 완성형이 되면 빨간 벼슬과 꽁지깃이 나요.',
    body: '#ffe36e', shade: '#f4c13a', hi: '#fff7c8', beak: '#ff9a2e', beakShade: '#e57a12', eye: '#2a2018', blush: '#ff9a8a', feet: '#ff9a2e', shell: '#fffaf0', shellShade: '#ecdcc0', comb: '#ff4b4b', combShade: '#d92f3a', egg: '#f4c13a' },
  rabbit: { name: '토실이', kind: '아기토끼', feature: 'bunny', exp: 2.2, desc: '하얀 솜뭉치 토끼. 성장기부터 당근을 손에 꼭 쥐고, 완성형이 되면 한쪽 귀가 폭 접히고 귀에 꽃을 꽂아요.',
    body: '#fffdfa', shade: '#ebdfd6', hi: '#ffffff', inner: '#ffb0c4', eye: '#33232c', blush: '#ff9fb4', carrot: '#ff8a2a', carrotShade: '#e06a12', leaf: '#5fbf4a', egg: '#ffb0c4' },
  panda: { name: '판돌이', kind: '아기판다', feature: 'panda', eyeStyle: 'panda', exp: 2.2, desc: '눈가에 까만 무늬가 있는 아기 판다. 성장기부터 대나무 가지를 손에 들고 다니고, 완성형이 되면 굵은 대나무 줄기를 들어요.',
    body: '#ffffff', shade: '#e2e3ea', hi: '#ffffff', dark: '#4a4a56', eye: '#ffffff', blush: '#ffb0bf', leaf: '#6cc24a', bamboo: '#9bd36a', bambooShade: '#5f9f3a', arm: '#34343d', feet: '#34343d', egg: '#34343d' },
  seal: { name: '뽀물이', kind: '아기물범', feature: 'seal', adj: { w: 2 }, desc: '솜털이 하얀 아기 물범. 성장기부터 머리에 비치볼을 올리고 다녀요. 완성형이 되면 솜털이 빠지고 은회색 털이 나요.',
    body: '#f5f7fb', shade: '#d6dce8', hi: '#ffffff', nose: '#2d2a33', whisker: '#b8c0cc', whiskerDots: [[-7, 0], [-5, 0]], eye: '#22202a', blush: '#ffadc0', belly: '#ffffff',
    adult: { body: '#c3cddb', shade: '#9eabbf', hi: '#e3e9f2', belly: '#eef2f7' }, egg: '#c3cddb' },
  uni: { name: '별콘이', kind: '아기유니콘', feature: 'unicorn', exp: 2.2, desc: '뿔이 자라는 아기 유니콘. 발굽이 분홍색이고, 아기 때 뿔은 콩알만 해요. 성장기에 무지개 앞머리와 짧은 꼬리가 나고, 완성형이 되면 뿔이 길어지고 갈기와 꼬리까지 무지개색이 돼요.',
    body: '#fffbfd', shade: '#f0dbe8', hi: '#ffffff', inner: '#ffc2dd', horn: '#ffd45a', hornShade: '#f0a93a', mane: ['#ff9ccf', '#8fd3ff', '#ffe27a', '#ffc49a'], eye: '#33232c', blush: '#ff9fc4', feet: '#ffd3e6', egg: '#ff9ccf' },
};
const SPECIES = ['nyang', 'bam', 'hammy', 'mung', 'peng', 'chick', 'rabbit', 'panda', 'seal', 'uni'];
// 이스터에그: 아주 드물게 태어나는 반짝이 색
const SHINY = {
  nyang: { label: '검정 얼룩', patch: '#46404d', patchShade: '#35303c', patchArea: [-.44, -.74, .08], patchRim: true, egg: '#46404d' },
  bam: { label: '황금 군밤', body: '#e2b04a', shade: '#b5832a', hi: '#f6d27e' },
  hammy: { label: '주황 털', body: '#f7943a', shade: '#dc7424', hi: '#ffbe7a', cream: '#fffaf2', creamShade: '#f2e0c8', arm: '#fffaf2', egg: '#f7943a' },
  mung: { label: '초코 귀', body: '#fffaf3', shade: '#efdcc4', hi: '#ffffff', ear: '#6b4535', earShade: '#4e3027', spot: null, egg: '#6b4535' },
  peng: { label: '하늘 펭귄', body: '#a6d8f5', shade: '#82bde6', hi: '#cdeafb', egg: '#a6d8f5' },
  chick: { label: '하얀 병아리', body: '#fffdf5', shade: '#efe4cc', hi: '#ffffff' },
  rabbit: { label: '연분홍 토끼', body: '#ffeef4', shade: '#f5d3e0', hi: '#fffafc', inner: '#ff9dbb', egg: '#ffc2d6' },
  panda: { label: '아이보리 판다', body: '#fff7e6', shade: '#eedfc0', hi: '#fffdf6' },
  seal: { label: '파란 물범', body: '#e6f2ff', shade: '#bdd7f4', hi: '#ffffff', egg: '#7fb3ec', adult: { body: '#86b8ee', shade: '#6497d6', hi: '#b9d9fb', belly: '#eef6ff' } },
  uni: { label: '별무늬 유니콘', body: '#f6f1ff', shade: '#e2d8f6', hi: '#ffffff', feet: '#e6d6ff', stars: ['#ffc93c', '#ff8fc8'], egg: '#c9b3ff' },
};
const ST = [
  { label: '알' },
  { label: '아기', w: 16, h: 13, eh: 4, gap: 2, eo: 4 },
  { label: '성장기', w: 20, h: 16, eh: 4, gap: 3, eo: 5 },
  { label: '완성형', w: 22, h: 19, eh: 4, gap: 3, eo: 6 },
];

function G() { return { c: new Array(1024).fill(null), o: new Uint8Array(1024) }; }
function S(g, x, y, c, ol) { if (x < 0 || y < 0 || x > 31 || y > 31) return; const i = y * 32 + x; g.c[i] = c; g.o[i] = ol ? 1 : 0; }
function isFill(g, x, y) { return !(x < 0 || y < 0 || x > 31 || y > 31) && g.o[y * 32 + x] === 1; }
function isEmpty(g, x, y) { return !(x < 0 || y < 0 || x > 31 || y > 31) && !g.c[y * 32 + x]; }
function onBody(g, x, y, c) { if (isFill(g, x, y)) g.c[y * 32 + x] = c; }
function outline(g) {
  const add = [];
  for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) {
    if (g.c[y * 32 + x]) continue;
    if (isFill(g, x - 1, y) || isFill(g, x + 1, y) || isFill(g, x, y - 1) || isFill(g, x, y + 1)) add.push(y * 32 + x);
  }
  add.forEach(i => { g.c[i] = OUT; g.o[i] = 0; });
}
function rowExtent(g, y) {
  let a = -1, b = -1;
  for (let x = 0; x < 32; x++) if (isFill(g, x, y)) { if (a < 0) a = x; b = x; }
  return [a, b];
}
// 덧그린 조각을 자기 외곽선과 함께 찍는다 (몸 위에 겹쳐도 경계가 보이게)
function stamp(g, cells) {
  const set = new Set(cells.map(([x, y]) => y * 32 + x));
  cells.forEach(([x, y, c]) => { if (x >= 0 && y >= 0 && x < 32 && y < 32) { g.c[y * 32 + x] = c; g.o[y * 32 + x] = 0; } });
  cells.forEach(([x, y]) => [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([dx, dy]) => {
    const X = x + dx, Y = y + dy;
    if (X < 0 || Y < 0 || X > 31 || Y > 31 || set.has(Y * 32 + X)) return;
    g.c[Y * 32 + X] = OUT; g.o[Y * 32 + X] = 0;
  }));
}

// 손에 쥐는 소품: rows 안의 'H' 가 손 위치(hand)에 오도록 찍는다. H 칸은 팔 색으로 칠해 손가락이 감싼 것처럼 보이게 하고,
// 외곽선은 빈 칸과 닿는 곳에만 긋는다 (몸·팔 테두리를 지우지 않게)
function hold(g, hand, armColor, rows, col) {
  let hx = 0, hy = 0;
  rows.forEach((r, y) => { const x = r.indexOf('H'); if (x >= 0) { hx = x; hy = y; } });
  const cells = [];
  rows.forEach((r, y) => r.split('').forEach((ch, x) => { if (ch !== '.') cells.push([hand.x + x - hx, hand.y + y - hy, ch === 'H' ? armColor : col[ch]]); }));
  const set = new Set(cells.map(([x, y]) => y * 32 + x));
  cells.forEach(([x, y, c]) => { if (x >= 0 && y >= 0 && x < 32 && y < 32) { g.c[y * 32 + x] = c; g.o[y * 32 + x] = 1; } });
  cells.forEach(([x, y]) => [[1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([dx, dy]) => {
    const X = x + dx, Y = y + dy;
    if (!set.has(Y * 32 + X) && isEmpty(g, X, Y)) S(g, X, Y, OUT, 0);
  }));
}

function drawBody(g, sp, cx, top, bottom, w, h, st) {
  const rx = w / 2, ry = h / 2, cy = top + ry, f = sp.feature, ex = sp.exp || 2.4;
  for (let y = top; y <= bottom; y++) for (let x = 0; x < 32; x++) {
    const ny = (y + .5 - cy) / ry;
    const k = f === 'chestnut' && ny < 0 ? 1 - .42 * Math.pow(-ny, 1.5) : 1;
    const nx = (x + .5 - cx) / (rx * k);
    if (Math.pow(Math.abs(nx), ex) + Math.pow(Math.abs(ny), ex) > 1) continue;
    const sh = nx * .42 + ny * .86 > .64;
    const hiZone = nx > -.64 && nx < -.36 && ny > -.8 && ny < -.52;
    let c = sp.body;
    if (f === 'chestnut' && ny > .5) {
      c = ((x * 7 + y * 3) % 5 === 0) ? sp.capDot : sp.cap;
      if (nx * .42 + ny * .86 > .9) c = sp.capShade;
      S(g, x, y, c, 1); continue;
    }
    if (f === 'hamster' && nx * nx / .5 + (ny - .38) ** 2 / .62 < 1) { S(g, x, y, sh ? sp.creamShade : sp.cream, 1); continue; }
    if (f === 'penguin' && nx * nx / .52 + (ny - .12) ** 2 / .78 < 1) { S(g, x, y, sh ? sp.faceShade : sp.face, 1); continue; }
    if (f === 'seal' && st === 3 && nx * nx / .42 + (ny - .45) ** 2 / .45 < 1) { S(g, x, y, sp.belly, 1); continue; }
    // 머리 얼룩: [가로 중심, 세로 중심, 크기]. 검정 얼룩은 눈에 닿으면 눈이 묻혀서 조금 작고 위로
    const [pa, pb, pr] = sp.patchArea || [-.42, -.62, .13];
    const inPatch = sp.patch && ((nx - pa) ** 2 * 1.3 + (ny - pb) ** 2 < pr);
    if (inPatch) c = sp.patch;
    if (sh) c = inPatch ? sp.patchShade : sp.shade;
    else if (!inPatch && hiZone) c = sp.hi;
    S(g, x, y, c, 1);
  }
}

function drawEgg(g, sp, P, crack) {
  // 줄마다 좌우 대칭 폭을 정해서 매끈한 달걀 모양을 만든다 (위가 살짝 좁다)
  const h = 19, bottom = 29, top = bottom - h + 1, cx = 16, rx = 6.7, ry = 9.5, cy = top + ry + .7;
  const spots = [[-3, -3, 2, 2], [1, -6, 2, 2], [1, 0, 3, 2], [-4, 3, 2, 2], [1, 5, 2, 1]];
  for (let y = top; y <= bottom; y++) {
    const ny = Math.max(-1, Math.min(1, (y + .5 - cy) / ry));
    const half = Math.round(rx * Math.sqrt(1 - ny * ny) * (1 + .16 * ny));
    if (half <= 0) continue;
    const shift = Math.round((P.tilt || 0) * (bottom - y) / h * 1.6);
    for (let x = cx - half; x < cx + half; x++) {
      const dx = x - cx, dy = y - Math.round(cy);
      const nx = (dx + .5) / rx;
      let c = '#fffaf0';
      for (const [sx, sy, sw, shh] of spots) if (dx >= sx && dx < sx + sw && dy >= sy && dy < sy + shh) c = sp.egg;
      if (c !== sp.egg) {
        if (nx * .5 + ny * .85 > .66) c = '#efe1c6';
        else if (dx >= -5 && dx <= -4 && dy >= -6 && dy <= -5) c = '#ffffff';
      }
      S(g, x + shift, y, c, 1);
    }
  }
  outline(g);
  if (crack > 0) {
    const shift = Math.round((P.tilt || 0) * .7);
    const zig = [[11, 0], [12, -1], [13, 0], [14, 1], [15, 0], [16, -1], [17, 0], [18, 1], [19, 0], [20, -1], [21, 0]];
    const n = Math.min(zig.length, crack * 4);
    const y0 = Math.round(cy) - 1;
    for (let i = 0; i < n; i++) { const [x, dy] = zig[i]; if (isFill(g, x + shift, y0 + dy)) g.c[(y0 + dy) * 32 + x + shift] = OUT; }
    if (crack >= 3) { onBody(g, 15 + shift, y0 - 2, OUT); onBody(g, 15 + shift, y0 - 3, OUT); onBody(g, 18 + shift, y0 + 2, OUT); }
  }
}

function eye(g, x0, y0, type, sp, look, side) {
  const D = sp.eye;
  const px = (x, y, c) => onBody(g, x0 + x, y0 + y, c);
  // 밤팅이는 흰자가 큰 눈에 눈동자가 안쪽으로 살짝 몰려 있다
  if (sp.eyeStyle === 'googly' && (type === 'open' || type === 'wide')) {
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) {
      const corner = (y === 0 || y === 3) && (x === 0 || x === 3);
      if (!corner) px(x, y, '#ffffff');
    }
    const lk = look < 0 ? -1 : look > 0 ? 1 : 0;
    if (type === 'wide') { px(side < 0 ? 2 : 1, 1, D); return; }
    const bx = Math.max(0, Math.min(2, (side < 0 ? 2 : 0) + lk));
    px(bx, 1, D); px(bx + 1, 1, D); px(bx, 2, D); px(bx + 1, 2, D);
    return;
  }
  // 판다는 까만 무늬 안에 반짝이는 눈
  if (sp.eyeStyle === 'panda' && (type === 'open' || type === 'wide')) {
    px(1, 1, '#ffffff'); px(2, 1, '#ffffff'); px(1, 2, '#ffffff'); px(2, 2, '#ffffff');
    if (type !== 'wide') px(side < 0 ? 2 : 1, 2, '#111116');
    return;
  }
  if (sp.eyeStyle === 'panda') {
    // 판다는 감은 눈·웃는 눈을 흰 선으로 그린다
    const W = '#ffffff';
    if (type === 'blink') for (let x = 0; x < 4; x++) px(x, 2, W);
    else if (type === 'happy') { px(0, 2, W); px(1, 1, W); px(2, 1, W); px(3, 2, W); }
    else if (type === 'sleep') { px(0, 1, W); px(1, 2, W); px(2, 2, W); px(3, 1, W); }
    else if (type === 'sulk') { for (let x = 0; x < 4; x++) px(x, 1, W); const s2 = look < 0 ? 0 : 2; px(s2, 2, '#111116'); px(s2 + 1, 2, '#111116'); }
    else if (type === 'dizzy') { [[1, 0], [2, 0], [0, 1], [3, 1], [0, 2], [3, 2], [1, 3], [2, 3]].forEach(([x, y]) => px(x, y, W)); }
    return;
  }
  if (type === 'dizzy') {
    // 이스터에그: 빙글빙글 눈 (◎)
    [[1, 0], [2, 0], [0, 1], [3, 1], [0, 2], [3, 2], [1, 3], [2, 3], [2, 2]].forEach(([x, y]) => px(x, y, D));
    return;
  }
  // 기본 눈은 4x4 둥근 눈에 반짝임 한 점
  if (type === 'open' || type === 'wide') {
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) {
      const corner = (y === 0 || y === 3) && (x === 0 || x === 3);
      if (!corner) px(x, y, D);
    }
    px(1, 1, '#ffffff');
    if (type === 'wide') { px(2, 1, '#ffffff'); px(2, 2, '#8a6f86'); }
  } else if (type === 'blink') {
    for (let x = 0; x < 4; x++) px(x, 2, D);
  } else if (type === 'happy') {
    px(0, 2, D); px(1, 1, D); px(2, 1, D); px(3, 2, D);
  } else if (type === 'sleep') {
    px(0, 1, D); px(1, 2, D); px(2, 2, D); px(3, 1, D);
  } else if (type === 'sulk') {
    for (let x = 0; x < 4; x++) px(x, 1, D);
    const s2 = look < 0 ? 0 : 2;
    px(s2, 2, D); px(s2 + 1, 2, D); px(s2, 3, D); px(s2 + 1, 3, D);
  }
}

function mouth(g, cx, my, type, small, sp) {
  const d = '#3a2430', pink = '#ff7b9c';
  const p = (x, y, c = d) => onBody(g, x, y, c);
  if (sp.beak) {
    // 펭귄·병아리는 입 대신 부리
    const open = type === 'open' || type === 'grin' || type === 'o' || type === 'pant';
    for (let x = cx - 2; x <= cx + 1; x++) p(x, my, sp.beak);
    if (open) { p(cx - 1, my + 1); p(cx, my + 1); p(cx - 1, my + 2, sp.beakShade); p(cx, my + 2, sp.beakShade); }
    else if (type !== 'tiny') { p(cx - 1, my + 1, sp.beakShade); p(cx, my + 1, sp.beakShade); }
    return;
  }
  switch (type) {
    case 'smile': p(cx - 2, my); p(cx - 1, my + 1); p(cx, my + 1); p(cx + 1, my); break;
    case 'grin':
      if (small) { p(cx - 1, my); p(cx, my); p(cx - 1, my + 1, '#ffffff'); p(cx, my + 1); }
      else { p(cx - 2, my); p(cx - 1, my); p(cx, my); p(cx + 1, my); p(cx - 2, my + 1); p(cx - 1, my + 1, '#ffffff'); p(cx, my + 1, '#e2566e'); p(cx + 1, my + 1); p(cx - 1, my + 2); p(cx, my + 2); }
      break;
    case 'cat':
      if (small) { p(cx - 2, my); p(cx - 1, my + 1); p(cx, my + 1); p(cx + 1, my); p(cx - 1, my); p(cx, my); }
      else { p(cx - 3, my); p(cx - 2, my + 1); p(cx - 1, my); p(cx, my); p(cx + 1, my + 1); p(cx + 2, my); }
      break;
    case 'pant':
      p(cx - 3, my); p(cx - 2, my + 1); p(cx - 1, my); p(cx, my); p(cx + 1, my + 1); p(cx + 2, my);
      p(cx - 1, my + 1, pink); p(cx, my + 1, pink); p(cx - 1, my + 2, pink); p(cx, my + 2, '#f0607f');
      break;
    case 'open':
      if (small) { p(cx - 1, my); p(cx, my); p(cx - 1, my + 1, pink); p(cx, my + 1, pink); }
      else { p(cx - 2, my); p(cx - 1, my); p(cx, my); p(cx + 1, my); p(cx - 2, my + 1); p(cx - 1, my + 1, pink); p(cx, my + 1, pink); p(cx + 1, my + 1); p(cx - 1, my + 2); p(cx, my + 2); }
      break;
    case 'yawn':
      p(cx - 1, my); p(cx, my); p(cx - 2, my + 1); p(cx - 1, my + 1, pink); p(cx, my + 1, pink); p(cx + 1, my + 1); p(cx - 1, my + 2); p(cx, my + 2);
      break;
    case 'chew': p(cx - 1, my + 1); p(cx, my + 1); break;
    case 'o': p(cx - 1, my); p(cx, my); p(cx - 1, my + 1); p(cx, my + 1); break;
    case 'tiny': p(cx - 1, my + 1); break;
  }
}

function build(spec, P) {
  const g = G();
  const base = SP[spec.species];
  const st = spec.stage;
  if (st === 0) { drawEgg(g, spec.shiny ? { ...base, ...SHINY[spec.species] } : base, P, spec.crack || 0); return g; }
  const sh = spec.shiny ? SHINY[spec.species] : null;
  let sp = st === 3 && base.adult ? { ...base, ...base.adult } : base;
  if (sh) sp = { ...sp, ...sh, ...(st === 3 && sh.adult ? sh.adult : {}) };
  const A = sp.adj || {}, B = ST[st], pl = spec.plump || 0;
  // 몸매: 홀쭉(-1)은 좁고 살짝 길게, 빵빵(+1)은 넓고 둥글게
  const D = { w: B.w + (A.w || 0) + (pl > 0 ? 4 : pl < 0 ? -2 : 0), h: B.h + (A.h || 0) + (pl !== 0 ? 1 : 0), gap: Math.max(1, B.gap + (A.gap || 0)), eo: B.eo + (A.eo || 0) };
  const w = D.w + (P.dw || 0), h = D.h + (P.dh || 0);
  const bottom = st === 3 ? 27 : 28, top = bottom - h + 1, cx = 16, rx = w / 2;
  const L = P.look || 0;
  const f = sp.feature, adult = st === 3, teen = st >= 2;
  const nosed = f === 'puppy' || f === 'seal';
  const eyeY = top + D.eo, my = eyeY + 4 + (nosed ? 1 : 0), by = my + 2;
  const s = P.sway || 0;

  // ── 몸 뒤쪽 부품 ──
  if (f === 'cat') {
    const ax = Math.round(cx - rx * .74), bx = Math.round(cx + rx * .74) - 1;
    const tw = st === 1 ? 3 : 4;
    for (let i = 0; i < tw; i++) {
      const y = top - (tw - 2) + i;
      for (let k = 0; k <= i; k++) {
        const inner = i >= 2 && k >= 1 && k < i;
        S(g, ax + k, y, inner ? sp.inner : sp.patch, 1);
        S(g, bx - k, y, inner ? sp.inner : sp.body, 1);
      }
    }
    const tx = Math.round(cx + rx) - 1, wag = P.tail ? 1 : 0;
    const tail = st === 1 ? [[0, -3], [1, -4], [1, -5], [1 + wag, -6]] : [[0, -4], [1, -4], [2, -5], [2, -6], [2, -7], [2 + wag, -8]];
    tail.forEach(([dx, dy], i) => {
      const c = i >= tail.length - 2 ? sp.patch : sp.body;
      S(g, tx + dx, bottom + dy, c, 1);
      if (adult && i >= 2) S(g, tx + dx + 1, bottom + dy, c, 1);
    });
  }
  if (f === 'chestnut') {
    S(g, cx - 1, top - 1, sp.body, 1); S(g, cx, top - 1, sp.body, 1); S(g, cx, top - 2, sp.shade, 1);
  }
  if (f === 'chick' && st === 2) {
    S(g, cx - 1, top - 1, sp.body, 1); S(g, cx, top - 1, sp.body, 1);
    S(g, cx - 2, top - 2, sp.body, 1); S(g, cx, top - 2, sp.body, 1);
    S(g, cx + 1 + s, top - 3, sp.body, 1);
  }
  if (f === 'chick' && adult) {
    // 완성형: 빨간 벼슬
    [[-2, -1], [-1, -1], [0, -1], [1, -1], [-2, -2], [0, -2], [-1, -3], [1, -3 + (s > 0 ? 1 : 0)]].forEach(([dx, dy], i) => S(g, cx + dx, top + dy, i < 4 ? sp.combShade : sp.comb, 1));
  }
  if (f === 'puppy') {
    // 쫑긋 선 귀: 머리 양옆 위에 서서 바깥으로 살짝 기운다. 신나면 끝이 팔랑, 졸리거나 삐지면 옆으로 눕는다
    const droop = P.droop ? 1 : 0;
    const H = [0, 3, 4, 4][st] - droop * 2, wid = [0, 3, 4, 5][st], ax = Math.round(cx - rx * .82);
    for (let k = 0; k <= H; k++) {
      const y = top + 1 - k + droop, tip = k === H;
      const shift = -Math.floor(k / (droop ? 1 : 2)) - (P.earFlop && k >= H - 1 ? 1 : 0);
      for (let j = 0; j < wid; j++) {
        if (tip && (j === 0 || j === wid - 1)) continue;
        const inner = !tip && k >= 1 && j >= 1 && j <= wid - 2;
        const x = ax + j + shift, c = inner ? sp.earIn : sp.ear;
        S(g, x, y, c, 1); S(g, 31 - x, y, c, 1);
      }
    }
  }
  if (f === 'hamster') {
    const x0 = Math.round(cx - rx * .62) - 1, x1 = Math.round(cx + rx * .62) - 2;
    [x0, x1].forEach(xe => { for (let x = xe; x <= xe + 2; x++) { S(g, x, top - 1, sp.body, 1); S(g, x, top, sp.body, 1); } S(g, xe + 1, top - 1, sp.inner, 1); });
  }
  if (f === 'panda') {
    const x0 = Math.round(cx - rx * .66) - 2, x1 = Math.round(cx + rx * .66) - 2;
    [x0, x1].forEach(xe => {
      S(g, xe + 1, top - 2, sp.dark, 1); S(g, xe + 2, top - 2, sp.dark, 1);
      for (let x = xe; x <= xe + 3; x++) { S(g, x, top - 1, sp.dark, 1); S(g, x, top, sp.dark, 1); }
    });
  }
  if (f === 'bunny') {
    const len = [0, 6, 8, 9][st];
    const lx = st === 1 ? cx - 5 : cx - 6, rx2 = st === 1 ? cx + 2 : cx + 3;
    [[lx, -1], [rx2, 1]].forEach(([ex, side], ei) => {
      // 완성형은 오른쪽 귀 끝이 바깥으로 폭 접힌다. 졸리거나 삐지면 두 귀가 처진다
      if (adult && ei === 1 && !P.droop) {
        for (let y = top - 3; y <= top + 1; y++) { S(g, ex, y, sp.body, 1); S(g, ex + 1, y, y >= top - 2 && y <= top ? sp.inner : sp.body, 1); S(g, ex + 2, y, sp.body, 1); }
        for (let x = ex + 1; x <= ex + 5; x++) S(g, x, top - 4, sp.body, 1);
        for (let x = ex + 3; x <= ex + 6; x++) S(g, x, top - 3, sp.body, 1);
        S(g, ex + 6, top - 2, sp.body, 1);
        return;
      }
      const fold = (P.droop ? 1 : 0) || (ei === 1 && P.earFlop ? 1 : 0);
      for (let i = 0; i < len; i++) {
        const y = top + 1 - len + 1 + i;
        const bend = fold && i < 4 ? side * Math.ceil((4 - i) / 1.3) : 0;
        const yy = fold && i < 4 ? y + Math.ceil((4 - i) / 2) : y;
        const x = ex + bend;
        if (i === 0) { S(g, x + 1, yy, sp.body, 1); continue; }
        S(g, x, yy, sp.body, 1); S(g, x + 1, yy, (i >= 2 && i < len - 2) ? sp.inner : sp.body, 1); S(g, x + 2, yy, sp.body, 1);
      }
    });
    if (adult) {
      const fx = lx + 1, fy = top - 1;
      [[-1, 0], [1, 0], [0, -1], [0, 1]].forEach(([dx, dy]) => S(g, fx + dx, fy + dy, '#ff9ccf', 1));
      S(g, fx, fy, '#ffd23f', 1);
    }
  }
  if (f === 'unicorn') {
    const ax = Math.round(cx - rx * .7), bx = Math.round(cx + rx * .7) - 1;
    for (let i = 0; i < 3; i++) for (let k = 0; k <= i; k++) {
      const inner = i === 2 && k === 1;
      S(g, ax + k, top - 1 + i, inner ? sp.inner : sp.body, 1);
      S(g, bx - k, top - 1 + i, inner ? sp.inner : sp.body, 1);
    }
    const hl = [0, 2, 4, 6][st];
    for (let i = 0; i < hl; i++) {
      const y = top - 1 - i, c = P.hornGlow && i >= hl - 2 ? '#ffffff' : i % 2 ? sp.hornShade : sp.horn;
      S(g, cx - 1, y, c, 1);
      if (i < hl - 2 || st === 1) S(g, cx, y, i % 2 ? sp.horn : sp.hornShade, 1);
    }
  }

  drawBody(g, sp, cx, top, bottom, w, h, st);
  if (f === 'unicorn' && sp.stars) {
    // 반짝이: 작은 별을 좌우 대칭으로 규칙적으로 (얼굴은 비운다)
    const pts = st === 1 ? [[-5, 0], [4, 0]] : [[-6, 1], [5, 1], [-3, 4], [2, 4]];
    pts.forEach(([dx, dy], i) => [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]].forEach(([a, b]) => onBody(g, cx + dx + a, by + dy + b, a || b ? sp.stars[(i >> 1) % 2] : '#ffffff')));
  }

  // ── 몸에 붙는 부품(외곽선 안쪽) ──
  if (f === 'hamster') {
    const puff = 1 + (P.mouth === 'chew' || P.blush === 'big' ? 1 : 0) + (pl > 0 ? 1 : 0);
    for (let y = my - 1; y <= my + 1; y++) {
      const [a, b] = rowExtent(g, y);
      const n = y === my ? puff : Math.max(1, puff - 1);
      for (let k = 1; k <= n; k++) { S(g, a - k, y, sp.cream, 1); S(g, b + k, y, sp.cream, 1); }
    }
  }
  if (f === 'puppy') {
    const [, tb] = rowExtent(g, bottom - 3);
    S(g, tb + 1, bottom - 3, sp.body, 1); S(g, tb + 2, bottom - 4 - (P.tail ? 1 : 0), sp.body, 1);
  }
  if (f === 'chick' && st === 1) {
    for (let x = cx - 3; x <= cx + 2; x++) S(g, x, top - 2, sp.shell, 1);
    for (let x = cx - 4; x <= cx + 3; x++) S(g, x, top - 1, x >= cx + 1 ? sp.shellShade : sp.shell, 1);
    for (let x = cx - 5; x <= cx + 4; x++) S(g, x, top, x >= cx + 2 ? sp.shellShade : sp.shell, 1);
    for (let x = cx - 5; x <= cx + 4; x += 2) S(g, x, top + 1, sp.shell, 1);
  }
  if (f === 'chick' && adult) {
    // 완성형: 꽁지깃
    const [, tb] = rowExtent(g, by - 2), wag = P.tail ? 1 : 0;
    [[1, -1], [2, -2], [3, -3 - wag], [1, -2], [2, -3], [2, -4 - wag]].forEach(([dx, dy]) => S(g, tb + dx, by + dy, sp.body, 1));
  }
  if (f === 'bunny' && st >= 2) {
    const [, tb] = rowExtent(g, bottom - 3);
    const n = adult ? 3 : 2;
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) S(g, tb + 1 + x, bottom - 4 + y, '#ffffff', 1);
  }
  if (f === 'unicorn' && teen) {
    // 무지개 꼬리: 성장기는 짧게, 완성형은 길게
    const [, tb] = rowExtent(g, bottom - 4), wag = P.tail ? 1 : 0;
    const tail = adult ? [[1, -4], [2, -5], [3, -6 - wag], [2, -4], [3, -5], [4, -6 - wag], [3, -4], [4, -5]] : [[1, -4], [2, -5], [2, -4], [3, -5 - wag]];
    tail.forEach(([dx, dy], i) => S(g, tb + dx, bottom + dy, sp.mane[i % 4], 1));
  }
  if (f === 'seal' && teen) {
    const bx = cx - 3 + s, byy = top - 6 - (P.ballY || 0);
    // 비치볼: 노랑·하양·분홍 세로 줄 (빨강·파랑 반반은 태극 무늬처럼 보였다)
    const ball = ['.ywp.', 'hywpp', 'yywpp', 'yywpq', '.ywq.'];
    const col = { y: '#ffd84d', w: '#ffffff', p: '#ff93b6', q: '#ec7aa0', h: '#fff3b0' };
    ball.forEach((row, y) => row.split('').forEach((ch, x) => { if (ch !== '.') S(g, bx + x, byy + y, col[ch], 1); }));
  }

  // 발 (완성형은 두 줄로 두툼하게)
  const fy = bottom + 1, feet = sp.feet || sp.shade;
  const footRows = adult ? 2 : 1;
  const footL = st === 1 ? [cx - 5, cx - 3] : [cx - Math.round(rx * .5) - 3, cx - Math.round(rx * .5)];
  const footR = st === 1 ? [cx + 2, cx + 4] : [cx + Math.round(rx * .5) - 1, cx + Math.round(rx * .5) + 2];
  for (let r = 0; r < footRows; r++) {
    if (P.foot !== -1) for (let x = footL[0]; x <= footL[1]; x++) S(g, x, fy + r, feet, 1);
    if (P.foot !== 1) for (let x = footR[0]; x <= footR[1]; x++) S(g, x, fy + r, feet, 1);
  }

  // 팔 (소품은 몸통 폭 안에서만 칠하려고 팔 그리기 전에 폭을 재 둔다)
  const bandExt = [rowExtent(g, by), rowExtent(g, by + 1)];
  // 오른손(화면 오른쪽) 끝 칸. 당근·대나무처럼 손에 쥐는 소품의 기준점
  const hand = { x: bandExt[0][1] + 2, y: P.arms === 'up' ? by - 2 : by + 1 };
  if (teen) {
    const ay = by, arm = sp.arm || sp.body;
    const [lx, rxx] = bandExt[0];
    const draw = (side, mode) => {
      const ex = side < 0 ? lx : rxx;
      if (mode === 'up') { S(g, ex + side, ay - 1, arm, 1); S(g, ex + side * 2, ay - 2, arm, 1); S(g, ex + side, ay - 2, arm, 1); }
      else { S(g, ex + side, ay, arm, 1); S(g, ex + side, ay + 1, arm, 1); S(g, ex + side * 2, ay + 1, arm, 1); }
    };
    draw(-1, P.arms === 'up' || P.arms === 'wave' ? 'up' : 'down');
    draw(1, P.arms === 'up' ? 'up' : 'down');
  }

  outline(g);

  // ── 외곽선 뒤에 덧그리는 것 ──
  if (f === 'cat' && adult) {
    // 수염: 몸 밖으로 짧게
    const [a, b] = rowExtent(g, my);
    [[a - 2, my - 1], [a - 3, my - 1], [a - 2, my + 1], [a - 3, my + 2]].forEach(([x, y]) => { if (isEmpty(g, x, y)) S(g, x, y, OUT, 0); });
    [[b + 2, my - 1], [b + 3, my - 1], [b + 2, my + 1], [b + 3, my + 2]].forEach(([x, y]) => { if (isEmpty(g, x, y)) S(g, x, y, OUT, 0); });
  }

  // 성장기부터 붙는 소품
  if (teen) {
    if (f === 'cat') {
      // 목걸이: 입에서 한 줄 띄운 아래에 몸 폭 끝까지 곧게, 가운데에 방울 (완성형은 방울이 크다)
      const ky = by + 1;
      for (let x = bandExt[1][0]; x <= bandExt[1][1]; x++) onBody(g, x, ky, sp.acc);
      if (adult) {
        for (let x = cx - 2; x <= cx + 1; x++) onBody(g, x, ky + 1, sp.bell);
        onBody(g, cx - 2, ky + 1, '#fff1a8');
        for (let x = cx - 1; x <= cx; x++) onBody(g, x, ky + 2, '#e0a800');
      } else {
        onBody(g, cx - 1, ky + 1, sp.bell); onBody(g, cx, ky + 1, sp.bell); onBody(g, cx - 1, ky + 2, '#e0a800'); onBody(g, cx, ky + 2, '#e0a800');
      }
    }
    if (f === 'puppy') {
      for (let x = bandExt[0][0]; x <= bandExt[0][1]; x++) onBody(g, x, by, sp.acc);
      for (let x = bandExt[1][0]; x <= bandExt[1][1]; x++) onBody(g, x, by + 1, sp.accShade);
      for (let x = cx - 2; x <= cx + 1; x++) { onBody(g, x, by + 1, sp.acc); onBody(g, x, by + 2, sp.acc); }
      onBody(g, cx - 1, by + 3, sp.accShade); onBody(g, cx, by + 3, sp.accShade);
      onBody(g, cx - 1, by + 1, '#ffffff'); onBody(g, cx - 6, by, '#ffffff'); onBody(g, cx + 5, by, '#ffffff');
    }
    if (f === 'penguin') {
      for (let x = bandExt[0][0]; x <= bandExt[0][1]; x++) onBody(g, x, by, sp.acc);
      for (let x = bandExt[1][0]; x <= bandExt[1][1]; x++) onBody(g, x, by + 1, sp.accShade);
      const r = bandExt[0][1], n = adult ? 5 : 3;
      for (let i = 0; i < n; i++) { onBody(g, r - 4, by + 2 + i, i % 2 ? sp.accShade : sp.acc); onBody(g, r - 3, by + 2 + i, sp.acc); }
    }
    if (f === 'hamster') {
      if (!adult) {
        // 넥타이: 입에서 한 줄 띄운 가슴에 흰 깃·매듭, 아래로 넓어졌다 뾰족하게 (입 바로 밑에 붙이면 턱수염처럼 보였다)
        const x0 = cx - 2, y0 = by + 2, col = { w: '#ffffff', k: sp.tieKnot, t: sp.tie };
        ['wkkw', '.tt.', 'tttt'].forEach((row, y) => row.split('').forEach((ch, x) => { if (ch !== '.') onBody(g, x0 + x, y0 + y, col[ch]); }));
      } else {
        const ye = '#ffcf33', br = '#8a5a2b';
        for (let x = cx - 2; x <= cx + 1; x++) { onBody(g, x, by, ye); onBody(g, x, by + 3, ye); }
        [[-3, 1], [-3, 2], [2, 1], [2, 2]].forEach(([dx, dy]) => onBody(g, cx + dx, by + dy, ye));
        [[-2, 1], [-1, 1], [0, 1], [1, 1], [-2, 2], [-1, 2], [0, 2], [1, 2]].forEach(([dx, dy]) => onBody(g, cx + dx, by + dy, br));
        onBody(g, cx - 1, by + 1, '#b07a3f');
      }
    }
    if (f === 'bunny') {
      // 당근은 오른손에 세워 쥔다 (입 밑에 두면 입에 붙은 것처럼 보였다)
      const col = { g: sp.leaf, o: sp.carrot, s: sp.carrotShade };
      hold(g, hand, sp.arm || sp.body, adult
        ? ['g.g', '.g.', 'oo.', 'os.', 'oo.', 'Hs.', 'oo.', '.o.']
        : ['g.g', '.g.', 'oo.', 'os.', 'Ho.', '.o.'], col);
    }
    if (f === 'panda') {
      // 대나무는 오른손에 쥔다 (입가에 물리면 담배처럼 보였다). 성장기는 잎 달린 가지, 완성형은 굵은 줄기
      const col = { g: sp.leaf, b: sp.bamboo, d: sp.bambooShade };
      hold(g, hand, sp.arm || sp.body, adult
        ? ['gg..', '.gb.', '.bd.', '.dd.', '.bd.', '.Hd.', '.bd.', '.dd.', '.bd.']
        : ['g.g.', '.gb.', '..b.', '..d.', '.Hb.', '..b.'], col);
    }
    if (f === 'unicorn') {
      // 무지개 앞머리, 완성형은 갈기가 옆으로 길게
      for (let x = cx - 4; x <= cx + 1; x++) onBody(g, x, top + 1, sp.mane[(x + 8) % 4]);
      for (let x = cx - 4; x <= cx - 1; x++) onBody(g, x, top + 2, sp.mane[(x + 9) % 4]);
      if (adult) for (let y = top + 2; y <= top + 9; y++) { const [a] = rowExtent(g, y); onBody(g, a, y, sp.mane[y % 4]); onBody(g, a + 1, y, sp.mane[(y + 1) % 4]); }
    }
  }

  // 밤팅이: 정수리 갈라진 틈, 완성형 눈썹 (머리 위 김은 똥처럼 보여서 뺐다)
  if (f === 'chestnut') {
    const cr = adult ? [[-3, 0], [2, 0], [-2, 1], [-1, 1], [0, 1], [1, 1], [-2, 2], [-1, 2], [0, 2], [1, 2], [-3, 3], [2, 3]] : [[-2, 0], [1, 0], [-1, 1], [0, 1], [-2, 2], [1, 2]];
    cr.forEach(([dx, dy]) => onBody(g, cx + dx, top + 1 + dy, sp.crack));
  }

  // ── 얼굴 ──
  const x0L = cx - D.gap - 4 + L, x0R = cx + D.gap + L;
  if (f === 'puppy' && sp.spot) {
    for (let y = eyeY - 1; y <= eyeY + 4; y++) for (let x = x0R - 1; x <= x0R + 4; x++)
      if (((x - (x0R + 1.5)) / 3) ** 2 + ((y - (eyeY + 1.5)) / 3.2) ** 2 < 1) onBody(g, x, y, sp.spot);
  }
  if (f === 'panda') {
    // 눈 무늬: 둥근 5x5에 바깥 아래로 한 칸 처진 눈물 모양
    [[x0L, -1], [x0R, 1]].forEach(([x0, sd]) => {
      for (let y = 0; y < 5; y++) for (let x = 0; x < 5; x++) {
        if ((y === 0 || y === 4) && (x === 0 || x === 4)) continue;
        onBody(g, (sd < 0 ? x0 - 1 : x0) + x, eyeY - 1 + y, sp.dark);
      }
      onBody(g, sd < 0 ? x0 - 1 : x0 + 4, eyeY + 4, sp.dark);
    });
  }
  eye(g, x0L, eyeY, P.eyes, sp, L, -1);
  eye(g, x0R, eyeY, P.eyesR || P.eyes, sp, L, 1); // 윙크면 오른쪽 눈만 다르다
  if (sp.patchRim) {
    // 검정 얼룩: 눈과 맞닿은 얼룩 칸은 흰 털로 남겨 눈이 얼룩에 묻히지 않게
    const isPatch = (c) => c === sp.patch || c === sp.patchShade;
    for (let y = eyeY - 1; y <= eyeY + 4; y++) for (let x = x0L - 1; x <= x0R + 4; x++) {
      if (!isPatch(g.c[y * 32 + x])) continue;
      if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => g.c[(y + dy) * 32 + x + dx] === sp.eye)) g.c[y * 32 + x] = sp.body;
    }
  }
  // 별콘이 속눈썹: 눈 바깥 위로 한 칸 띄워 톡 올린다 (눈에 붙이면 찡그린 눈처럼 보였다)
  if (f === 'unicorn' && teen && (P.eyes === 'open' || P.eyes === 'wide')) { onBody(g, x0L - 1, eyeY - 1, OUT); onBody(g, x0R + 4, eyeY - 1, OUT); }
  if (f === 'chestnut' && adult) {
    [[0, -1], [1, -1], [2, -2], [3, -2]].forEach(([dx, dy]) => onBody(g, x0L + dx, eyeY + dy, '#3a1d10'));
    [[0, -2], [1, -2], [2, -1], [3, -1]].forEach(([dx, dy]) => onBody(g, x0R + dx, eyeY + dy, '#3a1d10'));
  }
  if (f === 'penguin' && adult) {
    for (let y = eyeY; y <= eyeY + 3; y++) {
      const [a, b] = rowExtent(g, y);
      let fl = -1, fr = -1;
      for (let x = a; x <= b; x++) if (g.c[y * 32 + x] === sp.face || g.c[y * 32 + x] === sp.faceShade) { if (fl < 0) fl = x; fr = x; }
      if (fl > 0) { onBody(g, fl - 1, y, '#ffc94a'); onBody(g, fr + 1, y, '#ffc94a'); if (y > eyeY) { onBody(g, fl - 2, y, '#ffb020'); onBody(g, fr + 2, y, '#ffb020'); } }
    }
  }
  const bRow = eyeY + 4;
  const big = P.blush === 'big';
  const blushL = big ? [[-2, 0], [-1, 0], [0, 0], [-1, 1], [0, 1]] : [[-1, 0], [0, 0]];
  const blushR = big ? [[3, 0], [4, 0], [5, 0], [3, 1], [4, 1]] : [[3, 0], [4, 0]];
  blushL.forEach(([dx, dy]) => onBody(g, x0L + dx, bRow + dy, sp.blush));
  blushR.forEach(([dx, dy]) => onBody(g, x0R + dx, bRow + dy, sp.blush));
  if (nosed) { onBody(g, cx - 1 + L, my - 1, sp.nose); onBody(g, cx + L, my - 1, sp.nose); }
  if (f === 'seal' && sp.whiskerDots) {
    sp.whiskerDots.forEach(([dx, dy]) => { onBody(g, cx + L + dx, my + dy, sp.whisker); onBody(g, cx + L - 1 - dx, my + dy, sp.whisker); });
  }
  mouth(g, cx + L, my, P.mouth, st === 1, sp);
  if (f === 'chick' && adult) { onBody(g, cx - 1 + L, my + 2, sp.comb); onBody(g, cx + L, my + 2, sp.comb); onBody(g, cx - 1 + L, my + 3, sp.combShade); }
  return P.lean ? shear(g, P.lean, bottom + 2) : g;
}

// 뒤뚱거림: 발은 그대로 두고 위로 갈수록 옆으로 민다
function shear(g, lean, base) {
  const n = G();
  for (let y = 0; y < 32; y++) {
    const d = Math.round(lean * Math.max(0, base - y) / 9);
    for (let x = 0; x < 32; x++) {
      const sx = x - d;
      if (sx < 0 || sx > 31) continue;
      n.c[y * 32 + x] = g.c[y * 32 + sx]; n.o[y * 32 + x] = g.o[y * 32 + sx];
    }
  }
  return n;
}


function paint(ctx, g, s, silh) {
  ctx.clearRect(0, 0, 32 * s, 32 * s);
  for (let i = 0; i < 1024; i++) {
    const c = g.c[i];
    if (!c) continue;
    ctx.fillStyle = silh ? (silh === true ? (c === OUT ? OUT : '#ffffff') : silh) : c;
    ctx.fillRect((i % 32) * s, ((i / 32) | 0) * s, s, s);
  }
}

/* 작은 도트 아이콘 */
function iconURL(rows, map, s, ol) {
  const h = rows.length, w = rows[0].length, pad = ol ? 1 : 0;
  const cv = document.createElement('canvas');
  cv.width = (w + pad * 2) * s; cv.height = (h + pad * 2) * s;
  const ctx = cv.getContext('2d');
  const at = (x, y) => (y >= 0 && y < h && x >= 0 && x < w && rows[y][x] !== '.') ? rows[y][x] : null;
  if (ol) {
    ctx.fillStyle = typeof ol === 'string' ? ol : OUT;
    for (let y = -1; y <= h; y++) for (let x = -1; x <= w; x++) {
      if (at(x, y)) continue;
      if (at(x - 1, y) || at(x + 1, y) || at(x, y - 1) || at(x, y + 1)) ctx.fillRect((x + pad) * s, (y + pad) * s, s, s);
    }
  }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const k = at(x, y); if (!k) continue;
    ctx.fillStyle = map[k]; ctx.fillRect((x + pad) * s, (y + pad) * s, s, s);
  }
  return cv.toDataURL();
}

const HEART = ['.aa.aa.', 'abaaaaa', 'aaaaaaa', '.aaaaa.', '..aaa..', '...a...'];
const SPARK = ['...a...', '...a...', '..aba..', 'aabbbaa', '..aba..', '...a...', '...a...'];
const ZED = ['aaaa', '..a.', '.a..', 'aaaa'];
const NOTE = ['..aa', '..ab', '..a.', '..a.', 'aaa.', 'aaa.'];
const PUFF = ['.aa.', 'aaaa', 'aaaa', '.aa.'];

/* 캐릭터마다 좋아하는 음식 (앞이 제일 좋아하는 것) */
const FOOD = {
  fish: { n: '생선', rows: ['....aaa...', '.aaaaaaa.a', 'aeaaaaaaaa', 'aaaaaaaaaa', '.abbbbba.a', '....bb....'], map: { a: '#8db4dc', b: '#6d93c0', e: '#2d2a33' } },
  milk: { n: '우유', rows: ['..aa..', '.aaaa.', 'aaaaaa', 'wwwwww', 'wbbbbw', 'wbwwbw', 'wbbbbw', 'wwwwww'], map: { a: '#7cc0ff', w: '#ffffff', b: '#4f9cf5' } },
  potato: { n: '군고구마', rows: ['...pppp...', '.ppppyppp.', 'ppppyyyppp', '.pppyypppp', '..pppppp..'], map: { p: '#a8507e', y: '#ffcf5a' } },
  seed: { n: '해바라기씨', rows: ['.aa.', 'abwa', 'abwa', 'abwa', 'abwa', '.aa.'], map: { a: '#3d3633', b: '#5a504c', w: '#efe7da' } },
  strawberry: { n: '딸기', rows: ['..g..g..', '...gg...', '.rrrrrr.', 'rryrrryr', 'rrrrrrrr', '.rryrrr.', '..rrrr..', '...rr...'], map: { r: '#ff4d5e', y: '#ffe08a', g: '#5fbf4a' } },
  bone: { n: '뼈다귀 간식', rows: ['ww......ww', 'www....www', '.wwwwwwww.', 'www....www', 'ww......ww'], map: { w: '#fff3df' } },
  icecream: { n: '아이스크림', rows: ['.pppp.', 'pppppp', 'pwpppp', 'pppppp', 'cccccc', '.cccc.', '.cccc.', '..cc..', '..cc..'], map: { p: '#ffb3c8', w: '#ffffff', c: '#e8a85a' } },
  corn: { n: '옥수수', rows: ['..yy..', '.gyyg.', 'gyyyyg', 'gyyyyg', 'gyyyyg', '.gyyg.', '..gg..'], map: { y: '#ffd43a', g: '#7cc95a' } },
  carrot: { n: '당근', rows: ['......gg', '.....gg.', '....ooo.', '...oooo.', '..oooo..', '.oooo...', '.ooo....', 'oo......'], map: { o: '#ff8a2a', g: '#5fbf4a' } },
  bamboo: { n: '대나무', rows: ['...g.g', '....gg', '.bb...', '.bb...', '.dd...', '.bb...', '.bb...', '.dd...', '.bb...'], map: { b: '#9bd36a', d: '#5f9f3a', g: '#6cc24a' } },
  apple: { n: '사과', rows: ['....s...', '...sgg..', '.rrrrrr.', 'rwrrrrrr', 'rwrrrrrr', 'rrrrrrrr', '.rrrrrr.', '..rr.rr.'], map: { r: '#ff5a4f', w: '#ffb3ab', s: '#7a5230', g: '#5fbf4a' } },
  macaron: { n: '마카롱', rows: ['.pppppp.', 'pppppppp', 'cccccccc', 'pppppppp', '.pppppp.'], map: { p: '#ff9ccf', c: '#fff4e0' } },
};
const FAV = {
  nyang: ['fish', 'milk'], bam: ['potato', 'milk'], hammy: ['seed', 'strawberry'], mung: ['bone', 'potato'], peng: ['fish', 'icecream'],
  chick: ['corn', 'strawberry'], rabbit: ['carrot', 'strawberry'], panda: ['bamboo', 'apple'], seal: ['fish', 'icecream'], uni: ['macaron', 'strawberry'],
};
/* 캐릭터마다 다른 고유 동작 (가만히 있을 때 가끔 나와요) */
const SPECIAL = {
  nyang: ['하품·기지개', '쭉 늘어나며 하품하고 꼬리를 살랑'],
  bam: ['김 뿜기', '부르르 떨다가 머리에서 김을 퐁'],
  hammy: ['볼 빵빵', '볼주머니를 부풀렸다 뺐다'],
  mung: ['제자리 콩콩', '귀를 팔랑이며 콩콩 뛰고 꼬리를 붕붕'],
  peng: ['뒤뚱뒤뚱', '날개를 파닥이며 좌우로 뒤뚱'],
  chick: ['파닥파닥 콕콕', '날개를 파닥이다가 바닥을 콕콕'],
  rabbit: ['깡총', '높이 깡총 뛰고 코를 씰룩'],
  panda: ['데굴데굴', '그 자리에서 데굴데굴 두 바퀴'],
  seal: ['공 튕기기', '머리 위 공을 통통 튕기며 박수'],
  uni: ['반짝 마법', '뿔이 반짝이며 별가루가 퐁퐁'],
};
function bite(rows, n) { const w = rows[0].length, step = Math.ceil(w / 3); return rows.map((r, y) => r.split('').map((ch, x) => (x >= w - n * step + (y % 2)) ? '.' : ch).join('')); }
const IC = {};
function makeIcons() {
  IC.heart = iconURL(HEART, { a: '#ff5f86', b: '#ffffff' }, 3, true);
  IC.spark = iconURL(SPARK, { a: '#ffcc33', b: '#ffffff' }, 3, false);
  IC.z = iconURL(ZED, { a: '#7c83e8' }, 3, false);
  IC.note = iconURL(NOTE, { a: '#5c61f0', b: '#9a9eff' }, 3, false);
  IC.puff = iconURL(PUFF, { a: '#eee8e1' }, 3, '#cfc6be');
  IC.heartS = iconURL(HEART, { a: '#ff5f86', b: '#ffffff' }, 2, true);
  IC.heartE = iconURL(HEART, { a: '#d9dce2', b: '#d9dce2' }, 2, '#b5bac3');
  IC.food = {};
  Object.entries(FOOD).forEach(([k, f]) => {
    const gray = {}; Object.keys(f.map).forEach(c => { gray[c] = '#dfe2e7'; });
    IC.food[k] = { n: f.n, w: f.rows[0].length, bites: [0, 1, 2].map(n => iconURL(bite(f.rows, n), f.map, 3, true)), s: iconURL(f.rows, f.map, 2, true), e: iconURL(f.rows, gray, 2, '#b5bac3') };
  });
}

/* ───────── 펫 동작 ───────── */
const DUR = { pet: 1500, hop: 1300, wink: 1400, shy: 1700, wave: 1600, tilt: 1500, eat: 2900, full: 2000, celebrate: 1700, reunion: 1900, surprise: 700, evolve: 2700, eggtap: 420, special: 1800, dizzy: 2200, dance: 2600 };
const EMIT = {
  pet: [[0, 'heart'], [380, 'heart'], [760, 'heart']],
  hop: [[200, 'heart'], [720, 'heart']],
  wink: [[260, 'twinkle'], [380, 'twinkle'], [520, 'twinkle']],
  shy: [[450, 'heart']],
  wave: [[100, 'note'], [800, 'note']],
  celebrate: [[250, 'spark'], [420, 'spark'], [600, 'spark'], [1000, 'spark']],
  reunion: [[500, 'heart'], [820, 'heart'], [1150, 'heart']],
  evolve: [[2350, 'spark'], [2400, 'spark'], [2450, 'spark'], [2500, 'spark'], [2550, 'spark']],
  eat: [[2500, 'heart']],
  dance: [[0, 'note'], [500, 'note'], [1000, 'note'], [1500, 'note'], [2000, 'note']],
  dizzy: [[100, 'spark'], [900, 'spark']],
};
const EMIT_SPECIAL = {
  bam: [[820, 'puff'], [880, 'puff'], [960, 'puff']],
  uni: [[0, 'spark'], [300, 'spark'], [600, 'spark'], [900, 'spark'], [1200, 'spark']],
  nyang: [[700, 'z']],
  mung: [[200, 'heart']],
};
const defaultMouth = (s) => s.species === 'bam' ? 'grin' : (s.species === 'mung' && s.stage === 3) ? 'pant' : ['nyang', 'mung', 'hammy', 'seal'].includes(s.species) ? 'cat' : 'smile';
const jump = (t, dur, hgt) => (t < 0 || t > dur) ? 0 : Math.round(hgt * Math.sin(Math.PI * t / dur));
const PETS = [];
/* display:none 감지: 폴링 대신 공유 ResizeObserver 하나로 한다(display:none → 0x0 으로 통지된다).
 * 캔버스는 WeakMap 으로만 펫과 잇고, 루프가 분리된 캔버스를 PETS 에서 뺄 때 unobserve 한다. */
const PET_BY_CV = new WeakMap();
const sizeObserver = typeof ResizeObserver !== 'undefined'
  ? new ResizeObserver((entries) => {
      for (const e of entries) { const p = PET_BY_CV.get(e.target); if (p) p._vis = e.contentRect.width > 0 || e.contentRect.height > 0; }
    })
  : null;

class Pet {
  constructor(host, cv, spec, o = {}) {
    this.host = host; this.cv = cv; this.ctx = cv.getContext('2d');
    this.spec = { ...spec }; this.scale = o.scale || 3; this.loop = o.loop || null;
    this.hooks = o.hooks || {}; this.autoSpecial = !!o.autoSpecial;
    cv.width = cv.height = 32 * this.scale;
    this.t = rnd(0, 3000); this.state = 'idle'; this.st = 0; this.ei = 0;
    this.nextBlink = rnd(800, 3000); this.blink = 0; this.dbl = false;
    this.look = 0; this.nextLook = rnd(3000, 7000); this.lastZ = 0; this.nextSpecial = rnd(9000, 16000);
    this.key = ''; this.dir = 1; this.loopWait = 0; this.food = null; this.bite = -1; this.foodKey = null;
    PETS.push(this);
    PET_BY_CV.set(cv, this);
    if (sizeObserver) sizeObserver.observe(cv);
    if (this.loop) this.play(this.loop);
    this.render();
  }
  play(state, opts = {}) {
    if (this.food) this.dropFood();
    this.state = state; this.st = 0; this.ei = 0; this.lastZ = -2000;
    if (state === 'eat') this.showFood(opts.food);
    this.key = '';
  }
  showFood(k) {
    const fav = FAV[this.spec.species] || ['strawberry'];
    k = k || (Math.random() < .6 ? fav[0] : fav[1]);
    this.foodKey = k;
    const f = IC.food[k];
    const img = document.createElement('img');
    img.className = 'wpet-food'; img.alt = '';
    const s = this.scale / 3;
    img.style.width = ((f.w + 2) * 3 * s) + 'px';
    img.style.left = (this.dir > 0 ? 32 * this.scale - 10 * s : -(f.w + 2) * 3 * s + 10 * s) + 'px';
    img.src = f.bites[0];
    this.host.appendChild(img); this.food = img; this.bite = 0;
  }
  dropFood() { this.food.remove(); this.food = null; }
  emit(kind) { (this.hooks.fx || spawnFx)(this, kind); }
  update(dt) {
    this.t += dt; this.st += dt;
    this.nextBlink -= dt;
    if (this.nextBlink <= 0) { this.blink = 130; this.nextBlink = rnd(2000, 5000); if (Math.random() < .25) this.dbl = true; }
    if (this.blink > 0) { this.blink -= dt; if (this.blink <= 0 && this.dbl) { this.dbl = false; this.nextBlink = 160; } }
    if (this.state === 'idle') {
      this.nextLook -= dt;
      if (this.nextLook <= 0) { this.look = this.look ? 0 : pick([-1, 1]); this.nextLook = this.look ? rnd(900, 1500) : rnd(4000, 9000); }
      if (this.loop && this.loop !== 'idle' && DUR[this.loop]) { this.loopWait -= dt; if (this.loopWait <= 0) this.play(this.loop); }
      if (this.autoSpecial && this.spec.stage > 0) { this.nextSpecial -= dt; if (this.nextSpecial <= 0) { this.nextSpecial = rnd(14000, 24000); this.play('special'); } }
    } else if (this.look && this.state !== 'idle') this.look = 0;
    const em = this.state === 'special' ? EMIT_SPECIAL[this.spec.species] : EMIT[this.state];
    if (em) while (this.ei < em.length && this.st >= em[this.ei][0]) { this.emit(em[this.ei][1]); this.ei++; }
    if (this.state === 'sleep' && this.st - this.lastZ > 1500) { this.lastZ = this.st; this.emit('z'); }
    if (this.spec.shiny && this.spec.stage > 0 && Math.random() < dt / 1800) this.emit('twinkle');
    if (this.state === 'eat' && this.food) {
      const b = Math.max(0, Math.min(3, Math.floor((this.st - 700) / 560)));
      if (b !== this.bite) { this.bite = b; if (b >= 3) this.dropFood(); else this.food.src = IC.food[this.foodKey].bites[b]; }
    }
    const d = DUR[this.state];
    if (d && this.st >= d) {
      const done = this.state;
      if (done === 'evolve' && this.evolveFrom) this.evolveFrom = null;
      this.play('idle');
      if (this.loop) this.loopWait = 900;
      this.hooks.end && this.hooks.end(done);
    }
    this.render();
  }
  special(P, st) {
    const f2 = (ms) => Math.floor(st / ms) % 2;
    switch (this.spec.species) {
      case 'nyang':
        if (st < 600) { P.dh = 2; P.dw = -2; P.arms = 'up'; P.eyes = 'sleep'; P.mouth = 'o'; }
        else if (st < 1200) { P.eyes = 'sleep'; P.mouth = 'yawn'; P.dh = 1; }
        else { P.eyes = 'happy'; P.tail = f2(110); }
        break;
      case 'bam':
        if (st < 800) { P.look = f2(70) ? 1 : -1; P.eyes = 'blink'; P.mouth = 'o'; }
        else if (st < 1100) { P.dh = -2; P.dw = 2; P.eyes = 'happy'; P.mouth = 'grin'; P.y = 1; }
        else { P.eyes = 'happy'; }
        break;
      case 'hammy': P.mouth = f2(220) ? 'chew' : 'cat'; P.blush = f2(220) ? 'big' : 'n'; P.eyes = 'happy'; P.y = jump(st % 440, 440, 3); P.dw = f2(220) ? 2 : 0; P.arms = f2(220) ? 'up' : 'down'; break;
      case 'mung': P.y = jump(st % 320, 320, 3); P.earFlop = f2(160); P.tail = f2(80); P.eyes = 'happy'; P.mouth = 'pant'; break;
      case 'peng': P.lean = f2(260) ? 1 : -1; P.foot = f2(260) ? 1 : -1; P.arms = f2(130) ? 'up' : 'down'; P.eyes = 'happy'; break;
      case 'chick':
        if (st < 800) { P.arms = f2(90) ? 'up' : 'down'; P.y = jump(st, 800, 2); P.eyes = 'happy'; }
        else { const k = Math.floor((st - 800) / 160) % 2; P.lean = k; P.dh = k ? -1 : 0; P.mouth = k ? 'open' : 'smile'; }
        break;
      case 'rabbit':
        if (st < 250) { P.dh = -2; P.dw = 2; }
        else if (st < 1050) { P.y = jump(st - 250, 800, 10); P.droop = st < 650 ? 1 : 0; P.eyes = 'happy'; P.arms = 'up'; }
        else P.mouth = f2(100) ? 'tiny' : 'smile';
        break;
      case 'panda': P.rot = st < 1600 ? (Math.floor(st / 200) % 4) * 90 : 0; P.eyes = 'happy'; P.mouth = 'open'; break;
      case 'seal': P.ballY = jump(st % 450, 450, 5); P.arms = f2(150) ? 'up' : 'down'; P.eyes = 'happy'; P.mouth = 'open'; break;
      case 'uni': P.eyes = 'happy'; P.hornGlow = f2(150); P.y = jump(st % 600, 600, 4); P.lean = f2(300) ? 1 : -1; P.blush = 'big'; break;
    }
  }
  pose() {
    const s = this.state, st = this.st;
    const slow = s === 'sleep' || s === 'sulk';
    const BR = slow ? 600 : 340;
    const ph = Math.floor(this.t / BR) % 4;
    const P = {
      dh: [0, 1, 0, -1][ph], dw: 0, lag: [-1, 0, 1, 0][ph],
      eyes: this.blink > 0 ? 'blink' : 'open',
      mouth: defaultMouth(this.spec),
      look: this.look, blush: 'n', arms: 'down', y: 0, foot: 0,
      sway: [0, 0, 1, 1, 0, 0, -1, -1][Math.floor(this.t / 260) % 8], droop: 0,
      tail: Math.floor(this.t / 450) % 2, tilt: 0, silh: false, alt: false, earFlop: 0, lean: 0, rot: 0, ballY: 0, hornGlow: 0,
      wave: Math.floor(this.t / (s === 'special' || s === 'pet' ? 70 : 140)) % 8,
    };
    if (this.spec.stage === 0) {
      const cyc = this.t % 2800;
      if (s === 'eggtap') P.tilt = [-1, 1, -1, 1, 0][Math.floor(st / 85) % 5];
      else if (cyc < 520) P.tilt = [-1, 0, 1, 0, -1, 0][Math.floor(cyc / 90) % 6];
      P.dh = 0;
      return P;
    }
    switch (s) {
      case 'walk': { const f = Math.floor(this.t / 170) % 2; P.foot = f ? 1 : -1; P.dh = f ? 0 : 1; P.look = 0; P.sway = f ? 1 : -1; if (this.spec.species === 'peng') P.lean = f ? 1 : -1; break; }
      case 'pet': { const f = Math.floor(st / 110) % 2; P.eyes = 'happy'; P.mouth = 'open'; P.blush = 'big'; P.dw = f ? 2 : 0; P.dh = f ? -1 : 1; P.arms = st < 1000 ? (f ? 'up' : 'down') : 'down'; P.earFlop = 1; break; }
      /* 두드릴 때 번갈아 나오는 동작들 (WrksPet.tsx 의 TAP_POSES) */
      // 깡총: 움츠렸다가 두 번 뛴다
      case 'hop': {
        P.eyes = 'happy'; P.mouth = 'open'; P.blush = 'big'; P.arms = 'up'; P.earFlop = 1;
        if (st < 160) { P.dh = -2; P.dw = 2; P.arms = 'down'; }
        else { const j = st - 160; P.y = jump(j, 480, 6) || jump(j - 520, 420, 4); if ((j > 470 && j < 530) || j > 940) { P.dh = -1; P.dw = 2; } }
        break;
      }
      // 윙크: 한쪽 눈을 찡긋하며 살짝 기울인다
      case 'wink': { P.look = 0; if (st < 220) { P.dh = 1; } else { P.eyesR = 'happy'; P.mouth = 'grin'; P.blush = 'big'; P.lean = st < 1100 ? 1 : 0; P.arms = st < 1100 ? 'wave' : 'down'; } break; }
      // 부끄: 눈을 옆으로 피하며 볼이 빨개지고 몸을 꼰다
      case 'shy': { P.blush = 'big'; P.mouth = 'tiny'; P.droop = 1; if (st < 1000) { P.look = -2; P.lean = Math.floor(st / 260) % 2 ? -1 : 0; } else { P.eyes = 'happy'; P.mouth = 'cat'; } break; }
      // 손 흔들기: 한 손을 흔들며 인사
      case 'wave': { const f = Math.floor(st / 180) % 2; P.eyes = 'open'; P.mouth = 'open'; P.look = 0; P.arms = st < 1300 ? (f ? 'wave' : 'down') : 'down'; P.lean = st < 1300 ? (f ? -1 : 0) : 0; P.blush = 'big'; break; }
      // 갸웃: 놀라서 두리번거리다 고개를 갸웃한다
      case 'tilt': { if (st < 700) { P.eyes = 'wide'; P.mouth = 'o'; P.look = Math.floor(st / 175) % 2 ? 1 : -1; } else { P.lean = -1; P.look = 1; P.mouth = 'smile'; P.eyes = st > 1050 && st < 1180 ? 'blink' : 'open'; } break; }
      case 'eat': {
        if (st < 650) { P.mouth = 'open'; P.eyes = 'wide'; }
        else if (st < 2400) { const f = Math.floor((st - 650) / 240) % 2; P.eyes = 'happy'; P.mouth = f ? 'open' : 'chew'; P.blush = 'big'; P.dw = f ? 0 : 2; P.dh = f ? 0 : -1; }
        else { P.eyes = 'happy'; P.mouth = 'open'; P.arms = 'up'; P.blush = 'big'; P.y = jump(st - 2400, 400, 3); }
        break;
      }
      case 'full': { P.eyes = 'happy'; P.mouth = 'chew'; P.blush = 'big'; P.dw = 2; P.dh = -1; if (st < 1100) P.look = [-1, 1][Math.floor(st / 170) % 2]; P.earFlop = 1; break; }
      case 'sleep': { P.eyes = 'sleep'; P.mouth = 'tiny'; P.droop = 1; P.dw = P.dh < 0 ? 2 : 0; P.sway = 0; break; }
      case 'sulk': { P.eyes = 'sulk'; P.mouth = 'chew'; P.blush = 'big'; P.look = -2; P.dw = P.dh <= 0 ? 2 : 0; P.droop = 1; P.sway = -1; break; }
      case 'reunion': {
        if (st < 450) { P.eyes = 'wide'; P.mouth = 'o'; P.dh = 1; }
        else { P.eyes = 'happy'; P.mouth = 'open'; P.blush = 'big'; P.arms = 'up'; P.y = jump(st - 450, 520, 5) || jump(st - 1000, 420, 3); }
        break;
      }
      case 'celebrate': {
        P.eyes = 'happy'; P.mouth = 'open'; P.arms = 'up'; P.blush = 'big';
        if (st < 180) { P.dh = -2; P.dw = 2; P.arms = 'down'; }
        else { const j = st - 180; P.y = jump(j, 620, 7); if (j > 620 && j < 760) { P.dh = -1; P.dw = 2; } else if (j >= 760) P.y = jump(j - 760, 520, 4); }
        break;
      }
      case 'surprise': P.eyes = 'wide'; P.mouth = 'o'; P.dh = 1; break;
      case 'special': this.special(P, st); break;
      case 'dizzy': P.eyes = 'dizzy'; P.mouth = 'o'; P.lean = [-1, 0, 1, 0][Math.floor(st / 130) % 4]; P.droop = 1; break;
      case 'dance': { const f = Math.floor(st / 220) % 2; P.eyes = 'happy'; P.mouth = 'open'; P.blush = 'big'; P.arms = f ? 'up' : 'wave'; P.lean = f ? 1 : -1; P.y = jump(st % 440, 440, 3); P.foot = f ? 1 : -1; P.earFlop = f; break; }
      case 'evolve': {
        P.eyes = 'open'; P.dh = 0;
        if (st < 2300) { const k = Math.floor(Math.pow(st / 2300, 2.2) * 16); P.silh = true; P.alt = k % 2 === 0; P.y = st > 200 ? 1 : 0; }
        else { P.eyes = 'happy'; P.mouth = 'open'; P.arms = 'up'; P.blush = 'big'; }
        break;
      }
    }
    return P;
  }
  render() {
    const P = this.pose();
    let spec = this.spec;
    if (this.state === 'evolve' && P.alt && this.evolveFrom) spec = this.evolveFrom;
    const key = JSON.stringify(P) + JSON.stringify(spec) + this.dir;
    if (key === this.key) return;
    this.key = key;
    paint(this.ctx, build(spec, P), this.scale, P.silh);
    this.cv.style.transform = `translateY(${-P.y * this.scale}px) scaleX(${this.dir}) rotate(${P.rot || 0}deg)`;
  }
}


function spawnFx(pet, kind) {
  const host = pet.host, s = pet.scale;
  const el = document.createElement('img');
  el.alt = '';
  el.className = 'wpet-fx' + (kind === 'z' ? ' wpet-z' : '');
  const src = { heart: IC.heart, spark: IC.spark, twinkle: IC.spark, z: IC.z, note: IC.note, puff: IC.puff }[kind];
  el.src = src;
  const size = { heart: 27, spark: 21, twinkle: 12, z: 12, note: 12, puff: 18 }[kind] || 12;
  el.style.width = (size * s / 3) + 'px';
  const cx = 16 * s + rnd(-9, 9) * s;
  el.style.left = (cx - size * s / 6) + 'px';
  el.style.top = (kind === 'z' ? 6 * s : rnd(2, 8) * s) + 'px';
  el.style.setProperty('--dx', rnd(-14, 14) + 'px');
  host.appendChild(el);
  setTimeout(() => el.remove(), 1900);
}


/* 모든 펫을 한 번의 타이머 루프로 움직인다.
 * rAF(60~120Hz) 대신 setTimeout 으로 실제 깨어남 횟수를 묶는다: 가만히 있을 땐 ~11Hz, 동작 중엔 ~26Hz.
 * 네이티브가 창을 숨기거나(setLoopVisible(false)) 문서가 hidden 이면 타이머를 아예 걸지 않는다. */
const IDLE_MS = 90, ACTIVE_MS = 38, ACTIVE_MS_REDUCED = 50;
const CALM = { idle: 1, sleep: 1, sulk: 1 };
let loopStarted = false, loopTimer = 0, loopLast = 0, nativeVisible = true;
const loopActive = () => nativeVisible && !(typeof document !== 'undefined' && document.hidden);

function loopTick() {
  loopTimer = 0;
  if (!loopActive()) return;
  let busy = false;
  try {
    const now = performance.now();
    const dt = Math.min(100, Math.max(0, now - loopLast)); loopLast = now;
    for (let i = PETS.length - 1; i >= 0; i--) {
      const p = PETS[i];
      if (!p.cv.isConnected) { PETS.splice(i, 1); PET_BY_CV.delete(p.cv); if (sizeObserver) sizeObserver.unobserve(p.cv); continue; }
      if (p._vis === false) continue; // display:none (ResizeObserver 가 갱신)
      p.update(dt);
      if (!CALM[p.state] || p.food || p.blink > 0) busy = true;
    }
  } finally {
    if (loopActive() && !loopTimer) loopTimer = setTimeout(loopTick, busy ? (reduced ? ACTIVE_MS_REDUCED : ACTIVE_MS) : IDLE_MS);
  }
}
function loopResume() {
  if (!loopStarted || loopTimer || !loopActive()) return;
  loopLast = performance.now(); // 멈춰 있던 시간이 dt 로 쌓이지 않게
  loopTimer = setTimeout(loopTick, 0);
}
function loopSuspend() { if (loopTimer) { clearTimeout(loopTimer); loopTimer = 0; } }
function syncLoop() { if (loopActive()) loopResume(); else loopSuspend(); }

/* 네이티브(Swift)가 알려 주는 창 표시 여부. document.hidden 과 함께 본다. */
function setLoopVisible(v) { nativeVisible = !!v; syncLoop(); }

function startLoop() {
  if (loopStarted) return;
  loopStarted = true;
  if (typeof document !== 'undefined') document.addEventListener('visibilitychange', syncLoop);
  syncLoop();
}
