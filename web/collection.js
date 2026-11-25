// 졸업 앨범 화면 — #card 를 채우는 독립 렌더러.
// 카드를 열고 닫는 일(hidden, 포커스, data-view 지우기)은 app.js 가 맡는다.
// 펫 그림은 engine.js 의 build/paint 로 한 번만 그린다. Pet 인스턴스나 타이머는 만들지 않는다.
(function (root) {
  'use strict';

  const PAGE_SIZE = 6;   // 3칸 × 2줄. 카드 안에서 스크롤 없이 보이는 양
  const SCALE = 2;       // 32도트 × 2 = 64px
  const ADULT = 3;       // 완성형

  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  };

  // 기록은 app.js 가 generations.js 로 정리해 넘긴다 ({ species, name, shiny, graduatedAt(ISO) }).
  // 여기서는 화면에 내는 쪽(한 쪽 분량)만 표시용으로 바꾼다
  function view(r) {
    const sp = typeof SP !== 'undefined' && SP;
    const known = !!sp && Object.prototype.hasOwnProperty.call(sp, r.species);
    // generations.js 는 이름이 비면 종 id 를 대신 넣는다. 아는 종이면 종 이름으로 바꿔 보여 준다
    const name = known && r.name === r.species ? sp[r.species].name : r.name;
    return { name, species: r.species, known, kind: known ? sp[r.species].name : '', shiny: r.shiny === true, iso: r.graduatedAt };
  }

  const pad = (n) => (n < 10 ? '0' : '') + n;
  const dateText = (d) => d.getFullYear() + '.' + pad(d.getMonth() + 1) + '.' + pad(d.getDate());
  const dateLong = (d) => d.getFullYear() + '년 ' + (d.getMonth() + 1) + '월 ' + d.getDate() + '일 졸업';
  const SHINY_NOTE = '반짝이: 64마리 중 1마리꼴로 태어나는 희귀한 색'; // app.js 의 fresh() 확률과 같다

  // 완성형 정지 그림. 엔진이 없거나 모르는 종이면 false
  function drawPet(cv, e) {
    if (!e.known || typeof build !== 'function' || typeof paint !== 'function') return false;
    try {
      const spec = { species: e.species, stage: ADULT, crack: 0, plump: 0, shiny: e.shiny };
      const P = {
        dh: 0, dw: 0, lag: 0, eyes: 'open',
        mouth: typeof defaultMouth === 'function' ? defaultMouth(spec) : 'smile',
        look: 0, blush: 'n', arms: 'down', y: 0, foot: 0, sway: 0, droop: 0, tail: 0, tilt: 0,
        silh: false, alt: false, earFlop: 0, lean: 0, rot: 0, ballY: 0, hornGlow: 0, wave: 0,
      };
      const ctx = cv.getContext('2d');
      if (!ctx) return false;
      cv.width = cv.height = 32 * SCALE;
      paint(ctx, build(spec, P), SCALE, false);
      return true;
    } catch (err) {
      return false;
    }
  }

  function entryNode(e) {
    const li = el('li', 'collection-entry');
    // 꾸밈용 열쇠: 엔진이 아는 종 id(SP 의 키)만 그대로 싣고, 나머지는 모두 unknown
    li.dataset.species = e.known ? e.species : 'unknown';
    if (e.shiny) li.dataset.shiny = 'true';
    const said = [e.name];
    if (e.kind && e.kind !== e.name) said.push(e.kind);
    else if (!e.known) said.push('알 수 없는 종');
    const pic = el('div', 'collection-pic');
    pic.setAttribute('aria-hidden', 'true');
    const cv = el('canvas', 'wpet-px collection-cv');
    if (drawPet(cv, e)) pic.appendChild(cv);
    else { pic.classList.add('is-unknown'); pic.textContent = '?'; }
    li.appendChild(pic);
    li.appendChild(el('span', 'collection-name', e.name));
    if (e.shiny) {
      const s = el('span', 'collection-shiny', '반짝이');
      s.title = SHINY_NOTE;
      li.appendChild(s);
      said.push(SHINY_NOTE);
    }
    const d = new Date(e.iso);
    if (!isNaN(d.getTime())) {
      const t = el('time', 'collection-date', dateText(d));
      t.dateTime = e.iso;
      t.title = dateLong(d);
      li.appendChild(t);
      said.push(dateLong(d));
    }
    li.setAttribute('aria-label', said.join(', ')); // 읽어 줄 때는 날짜를 풀어 쓰고 반짝이의 뜻도 함께
    return li;
  }

  // opts.back: 미션 카드에서 들어온 앨범. 닫기 단추(.collection-close)가 '돌아가기'가 된다 (data-action 으로 구분)
  function render(card, entries, onClose, opts) {
    if (!card) return;
    const back = !!(opts && opts.back);
    // 저장된 순서가 곧 졸업한 순서다. 복사·정렬 없이 뒤에서부터 읽어 최근 졸업을 먼저 보여 준다
    const list = Array.isArray(entries) ? entries : [];
    const pages = Math.max(1, Math.ceil(list.length / PAGE_SIZE));
    let page = 0;

    card.textContent = '';
    card.dataset.view = 'collection';
    card.setAttribute('aria-label', '졸업 앨범');

    const hd = el('div', 'card-hd collection-hd');
    hd.appendChild(el('b', 'collection-title', '졸업 앨범'));
    hd.appendChild(el('span', 'sub', list.length ? '졸업한 펫 ' + list.length + '마리' : '졸업한 펫이 아직 없어요'));
    const x = el('button', 'card-x collection-close', back ? '‹' : '×');
    x.type = 'button';
    x.dataset.action = back ? 'back' : 'close';
    x.setAttribute('aria-label', back ? '미션 카드로 돌아가기' : '졸업 앨범 닫기');
    x.title = back ? '미션 카드로 돌아가기' : '닫기';
    x.addEventListener('click', () => { if (typeof onClose === 'function') onClose(); });
    hd.appendChild(x);
    card.appendChild(hd);

    const body = el('div', 'card-body collection-body');
    card.appendChild(body);

    if (!list.length) {
      body.appendChild(el('p', 'collection-empty', '펫을 Lv.10까지 키우면 졸업해서 여기에 남아요. 미션을 끝내 경험치를 모아 보세요.'));
      return;
    }

    body.tabIndex = 0; // 이름이 길어 넘칠 때 키보드로도 스크롤할 수 있게
    body.setAttribute('role', 'group');
    body.setAttribute('aria-label', '졸업한 펫 목록');
    const ul = el('ul', 'collection-list');
    body.appendChild(ul);

    let prev = null, next = null, status = null;
    if (pages > 1) {
      const nav = el('div', 'collection-nav');
      nav.setAttribute('role', 'group');
      nav.setAttribute('aria-label', '쪽 넘기기');
      prev = el('button', 'collection-prev', '이전');
      next = el('button', 'collection-next', '다음');
      prev.type = next.type = 'button';
      prev.setAttribute('aria-label', '이전 쪽');
      next.setAttribute('aria-label', '다음 쪽');
      status = el('span', 'collection-page');
      status.setAttribute('role', 'status');
      status.setAttribute('aria-live', 'polite');
      prev.addEventListener('click', () => go(page - 1, prev, next));
      next.addEventListener('click', () => go(page + 1, next, prev));
      nav.appendChild(prev); nav.appendChild(status); nav.appendChild(next);
      card.appendChild(nav);
    }

    // 한 쪽 분량만 DOM 과 캔버스로 만든다. 기록이 아무리 많아도 그리는 양은 PAGE_SIZE 로 묶인다
    function show() {
      ul.textContent = '';
      const last = list.length - 1 - page * PAGE_SIZE;
      for (let i = last; i > last - PAGE_SIZE && i >= 0; i--) ul.appendChild(entryNode(view(list[i])));
      body.scrollTop = 0;
      if (status) {
        status.textContent = (page + 1) + ' / ' + pages;
        status.title = pages + '쪽 중 ' + (page + 1) + '쪽';
        prev.disabled = page === 0;
        next.disabled = page === pages - 1;
      }
    }
    function go(p, self, fallback) {
      const n = Math.min(pages - 1, Math.max(0, p));
      if (n === page) return;
      // 꺼지는 순간 포커스를 놓는 브라우저도 있으니, 누른 단추가 포커스를 쥐고 있었는지 먼저 본다 (마우스로 누른 때는 옮기지 않는다)
      const held = document.activeElement === self;
      page = n;
      show();
      // 끝에 닿아 누른 단추가 꺼지면 포커스를 반대쪽 단추로 옮긴다
      if (held && self.disabled && fallback && !fallback.disabled) fallback.focus();
    }
    show();
  }

  root.MacPetCollection = { render, PAGE_SIZE };
})(typeof window !== 'undefined' ? window : globalThis);
