// 网页里的“实时预览”组件：画布 + 多格切换 + 相机控制 + 参数面板 + 在线编辑 GLSL。
//   const v = new Viewer(容器元素, { sceneId: 'ch05-lambert', base: './' });  await v.open();
// 同一页面同一时间只开一个预览（WebGL 上下文有限），打开新的会自动关掉旧的。
import { Engine } from './pipeline.js';
import { srgbToLinear, linearToSrgb } from './math.js';
import { isHdr } from './shader.js';

let ACTIVE = null;

// URP 自带着色器只显示这些常用参数（其余是内部状态，改了反而会乱）
const BUILTIN_VISIBLE = new Set(['_BaseColor', '_Metallic', '_Smoothness', '_BumpScale', '_OcclusionStrength', '_EmissionColor', '_Cutoff', '_SpecColor', '_Tint', '_Exposure', '_Rotation', '_ClearCoatMask', '_ClearCoatSmoothness']);
const HIDDEN_ALWAYS = new Set(['_Surface', '_Blend', '_AlphaClip', '_SrcBlend', '_DstBlend', '_SrcBlendAlpha', '_DstBlendAlpha', '_ZWrite', '_Cull', '_BlendOp', '_ReceiveShadows', '_QueueOffset', '_QueueControl', '_WorkflowMode', '_SmoothnessTextureChannel', '_SpecularHighlights', '_EnvironmentReflections', '_AlphaToMask', '_XRMotionVectorsPass', '_AddPrecomputedVelocity', '_MainTex', '_Color', '_GlossMapScale', '_Glossiness', '_GlossyReflections', '_DstBlend2']);

const ENUMS = {
  'UnityEngine.Rendering.CullMode': [['Off', 0], ['Front', 1], ['Back', 2]],
  'UnityEngine.Rendering.BlendMode': ['Zero', 'One', 'DstColor', 'SrcColor', 'OneMinusDstColor', 'SrcAlpha', 'OneMinusSrcColor', 'DstAlpha', 'OneMinusDstAlpha', 'SrcAlphaSaturate', 'OneMinusSrcAlpha'].map((n, i) => [n, i]),
  'UnityEngine.Rendering.CompareFunction': ['Disabled', 'Never', 'Less', 'Equal', 'LessEqual', 'Greater', 'NotEqual', 'GreaterEqual', 'Always'].map((n, i) => [n, i]),
  'UnityEngine.Rendering.BlendOp': ['Add', 'Subtract', 'ReverseSubtract', 'Min', 'Max'].map((n, i) => [n, i]),
  'UnityEngine.Rendering.StencilOp': ['Keep', 'Zero', 'Replace', 'IncrementSaturate', 'DecrementSaturate', 'Invert', 'IncrementWrap', 'DecrementWrap'].map((n, i) => [n, i]),
};

// Volume 参数的滑杆范围（URP 内置组件里常见的名字）
const VOL_RANGES = {
  intensity: [0, 5], threshold: [0, 4], scatter: [0, 1], clamp: [0, 100], postExposure: [-4, 4], contrast: [-100, 100], saturation: [-100, 100],
  hueShift: [-180, 180], temperature: [-100, 100], tint: [-100, 100], smoothness: [0, 1], response: [0, 1], scale: [0.01, 5],
  xMultiplier: [0, 1], yMultiplier: [0, 1], distance: [0, 1], cropToFit: [0, 1], focusDistance: [0.1, 50], aperture: [1, 32], focalLength: [1, 300],
  gaussianStart: [0, 50], gaussianEnd: [0, 100], gaussianMaxRadius: [0.5, 1.5], balance: [-100, 100], dirtIntensity: [0, 10],
};
const VOL_ENUMS = {
  'Tonemapping.mode': ['None', 'Neutral', 'ACES'],
  'DepthOfField.mode': ['Off', 'Gaussian', 'Bokeh'],
  'FilmGrain.type': ['Thin1', 'Thin2', 'Medium1', 'Medium2', 'Medium3', 'Medium4', 'Medium5', 'Medium6', 'Large01', 'Large02', 'Custom'],
  'MotionBlur.mode': ['CameraOnly'],
  'MotionBlur.quality': ['Low', 'Medium', 'High'],
  'Bloom.downscale': ['Half', 'Quarter'],
};

export class Viewer {
  constructor(host, { sceneId, base = './', note = '', onClose = null } = {}) {
    this.host = host;
    this.sceneId = sceneId;
    this.base = base;
    this.note = note;
    this.onClose = onClose;
    this.panel = 0;
    this.playing = true;
    this.time = 0;
    this.edited = new Map();   // 文件 → 原始源码
  }

  // ---------------- 打开 / 关闭 ----------------
  async open() {
    if (ACTIVE && ACTIVE !== this) ACTIVE.close();
    ACTIVE = this;
    this.buildDom();
    this.msg('正在加载…');
    try {
      this.doc = await (await fetch(`${this.base}data/scenes/${this.sceneId}.json`)).json();
      this.engine = new Engine(this.canvas, { base: this.base });
      this.engine.onError = (e) => this.showError(e);
      await this.engine.init();
      await this.loadPanel(0);
      this.loop();
    } catch (e) {
      console.error(e);
      this.msg('加载失败：' + e.message);
    }
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    cancelAnimationFrame(this.raf);
    this.ro && this.ro.disconnect();
    this.io && this.io.disconnect();
    try { this.engine && this.engine.gl.getExtension('WEBGL_lose_context')?.loseContext(); } catch (e) { /* 已经丢失 */ }
    this.root.remove();
    if (ACTIVE === this) ACTIVE = null;
    this.onClose && this.onClose();
  }

  async loadPanel(p) {
    this.panel = p;
    this.msg('正在加载…');
    this.errors.innerHTML = '';
    this.engine.errors = [];
    this.scene = await this.engine.loadScene(this.doc, p, { onProgress: (f) => this.msg(`正在加载贴图 ${Math.round(f * 100)}%`) });
    this.msg('');
    this.tabs.querySelectorAll('button').forEach((b, i) => b.classList.toggle('on', i === p));
    if (this.scene.missingShaders.size) this.showError(new Error('还没有 GLSL 版本：' + [...this.scene.missingShaders].join('、') + '（显示为洋红色）'));
    for (const f of this.scene.features) if (f.error) this.showError(f.error);
    this.buildParams();
    if (!this.codePane.hidden) this.buildCode();
  }

  // ---------------- DOM ----------------
  buildDom() {
    const d = this.doc;
    const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; };
    this.root = el('div', 'vw');
    const bar = el('div', 'vw-bar');
    this.tabs = el('div', 'vw-tabs');
    const btn = (label, title, fn, cls = '') => { const b = el('button', cls, label); b.title = title; b.onclick = fn; return b; };
    this.playBtn = btn('⏸', '暂停 / 继续动画', () => this.togglePlay());
    bar.append(this.tabs, el('span', 'vw-sp'),
      this.playBtn,
      btn('⟲', '重置视角（也可以双击画面）', () => this.scene && this.scene.camera.reset()),
      btn('参数', '显示 / 隐藏参数面板', () => this.root.classList.toggle('noside'), 'txt'),
      btn('改代码', '在线编辑 GLSL，改完按 Ctrl+Enter 运行', () => this.toggleCode(), 'txt'),
      btn('⛶', '全屏', () => this.fullscreen()),
      btn('✕', '关闭预览', () => this.close()));
    const body = el('div', 'vw-body');
    const stage = el('div', 'vw-stage');
    this.canvas = el('canvas');
    this.message = el('div', 'vw-msg');
    stage.append(this.canvas, this.message, el('div', 'vw-hint', '拖动旋转 · 右键/Shift 拖动平移 · 滚轮缩放 · 双击复位'));
    this.side = el('div', 'vw-side');
    body.append(stage, this.side);
    this.errors = el('div', 'vw-errors');
    this.codePane = el('div', 'vw-code');
    this.codePane.hidden = true;
    this.root.append(bar, body, this.errors, this.codePane);
    if (this.note) this.root.append(el('div', 'vw-note', this.note));
    this.host.append(this.root);
    this.stage = stage;
    this.bindControls();
    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(stage);
    // 滚出视野时暂停渲染，省电
    this.visible = true;
    this.io = new IntersectionObserver((es) => { this.visible = es[0].isIntersecting; });
    this.io.observe(this.root);
  }

  resize() {
    if (!this.doc) { this.canvas.style.aspectRatio = '16 / 9'; return; }
    const w = this.stage.clientWidth;
    const aspect = this.doc.w / this.doc.h;
    let cssH = w / aspect;
    if (document.fullscreenElement === this.root) cssH = this.stage.clientHeight;
    this.canvas.style.height = cssH + 'px';
    // 参数面板和画面一样高（宽屏并排时），多出的内容在面板里滚动
    this.side.style.maxHeight = getComputedStyle(this.root.querySelector('.vw-body')).gridTemplateColumns.split(' ').length > 1 ? Math.max(cssH, 240) + 'px' : '';
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    let pw = Math.round(w * dpr), ph = Math.round(cssH * dpr);
    const maxPx = 2.4e6;
    if (pw * ph > maxPx) { const k = Math.sqrt(maxPx / (pw * ph)); pw = Math.round(pw * k); ph = Math.round(ph * k); }
    if (this.canvas.width !== pw || this.canvas.height !== ph) { this.canvas.width = pw; this.canvas.height = ph; }
  }

  msg(t) { this.message.textContent = t; this.message.style.display = t ? '' : 'none'; }

  showError(e) {
    const list = e.errors && e.errors.length ? e.errors.map((x) => `${x.file}:${x.line}  ${x.message}`) : [e.message];
    for (const line of list) {
      if ([...this.errors.children].some((c) => c.textContent === line)) continue;
      const div = document.createElement('div');
      div.textContent = line;
      this.errors.append(div);
    }
    if (this.cm && e.errors) this.markErrors(e.errors);
  }

  togglePlay() { this.playing = !this.playing; this.playBtn.textContent = this.playing ? '⏸' : '▶'; }

  fullscreen() {
    if (document.fullscreenElement) document.exitFullscreen();
    else this.root.requestFullscreen?.().then(() => this.resize());
  }

  // ---------------- 相机交互 ----------------
  bindControls() {
    const c = this.canvas;
    let drag = null;
    c.addEventListener('contextmenu', (e) => e.preventDefault());
    c.addEventListener('pointerdown', (e) => { drag = { x: e.clientX, y: e.clientY, pan: e.button === 2 || e.shiftKey }; c.setPointerCapture(e.pointerId); });
    c.addEventListener('pointerup', () => { drag = null; });
    c.addEventListener('pointermove', (e) => {
      if (!drag || !this.scene) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      drag.x = e.clientX; drag.y = e.clientY;
      const cam = this.scene.camera;
      if (drag.pan) cam.pan(dx / c.clientHeight, dy / c.clientHeight);
      else cam.orbit(dx * 0.008, dy * 0.008);
    });
    c.addEventListener('wheel', (e) => { if (!this.scene) return; e.preventDefault(); this.scene.camera.zoom(Math.exp(e.deltaY * 0.001)); }, { passive: false });
    c.addEventListener('dblclick', () => this.scene && this.scene.camera.reset());
    // 双指缩放
    const touches = new Map();
    c.addEventListener('touchstart', (e) => { for (const t of e.changedTouches) touches.set(t.identifier, [t.clientX, t.clientY]); }, { passive: true });
    c.addEventListener('touchmove', (e) => {
      if (touches.size !== 2 || !this.scene) return;
      const [a, b] = [...touches.values()];
      const d0 = Math.hypot(a[0] - b[0], a[1] - b[1]);
      for (const t of e.changedTouches) touches.set(t.identifier, [t.clientX, t.clientY]);
      const [a2, b2] = [...touches.values()];
      const d1 = Math.hypot(a2[0] - b2[0], a2[1] - b2[1]);
      if (d0 > 0 && d1 > 0) this.scene.camera.zoom(d0 / d1);
      e.preventDefault();
    }, { passive: false });
    c.addEventListener('touchend', (e) => { for (const t of e.changedTouches) touches.delete(t.identifier); });
  }

  // ---------------- 渲染循环 ----------------
  loop() {
    let last = performance.now();
    const tick = (now) => {
      if (this.closed) return;
      this.raf = requestAnimationFrame(tick);
      const dt = Math.min(0.1, (now - last) / 1000);
      last = now;
      if (!this.scene || !this.visible) return;
      if (this.playing) this.time += dt;
      this.resize();
      try { this.engine.render(this.scene, this.time, dt); } catch (e) { this.showError(e); }
    };
    this.raf = requestAnimationFrame(tick);
  }

  // ---------------- 多格切换 ----------------
  buildTabs() {
    this.tabs.innerHTML = '';
    const n = this.doc.panels.length;
    if (n <= 1) return;
    const names = n === 2 ? ['左图', '右图'] : n === 3 ? ['左图', '中图', '右图'] : null;
    for (let i = 0; i < n; i++) {
      const b = document.createElement('button');
      b.textContent = names ? names[i] : `第 ${i + 1} 格`;
      b.title = `书中这张图的第 ${i + 1} 格`;
      b.onclick = () => this.loadPanel(i);
      this.tabs.append(b);
    }
  }

  // ---------------- 参数面板 ----------------
  buildParams() {
    if (!this.tabs.children.length) this.buildTabs();
    const S = this.scene, side = this.side;
    side.innerHTML = '';
    const sec = (title, open = true) => {
      const d = document.createElement('details');
      d.open = open;
      const s = document.createElement('summary');
      s.innerHTML = title;
      d.append(s);
      side.append(d);
      return d;
    };
    // 材质：本书的着色器排前面，URP 自带的（多为陪衬/地面）排后面并默认折叠
    const mats = new Map();
    for (const o of S.renderers) o.renderer.materials.forEach((m) => {
      if (!m) return;
      if (!mats.has(m)) mats.set(m, []);
      mats.get(m).push(o.name);
    });
    const list = [...mats.entries()].sort((a, b) => (isBuiltin(a[0]) - isBuiltin(b[0])));
    let cookbookCount = 0;
    for (const [m, objs] of list) {
      const props = m.shader.meta.props || [];
      const visible = props.filter((p) => showProp(m, p));
      if (!visible.length) continue;
      const builtin = isBuiltin(m);
      if (!builtin) cookbookCount++;
      const names = [...new Set(objs)].slice(0, 3).join('、') + (objs.length > 3 ? ' 等' : '');
      const d = sec(`<b>${esc(shortShader(m.shader.name))}</b><small>${esc(names)}</small>`, !builtin && cookbookCount <= 2);
      let header = null;
      for (const p of props) {
        const hdr = (p.attrs || []).find((a) => a.startsWith('Header('));
        if (hdr && showProp(m, p)) { header = document.createElement('div'); header.className = 'vw-h'; header.textContent = hdr.slice(7, -1); d.append(header); }
        if (!visible.includes(p)) continue;
        const row = this.propControl(m, p);
        if (row) d.append(row);
      }
    }
    // 灯光
    const lights = S.lights.filter((l) => l.obj.active);
    if (lights.length) {
      const d = sec('<b>灯光</b>', false);
      lights.forEach((l, i) => d.append(...this.lightControls(l, i)));
    }
    // 后处理 Volume
    const comps = [];
    for (const v of S.volumes) for (const c of v.components) comps.push(c);
    if (comps.length) {
      const d = sec('<b>后处理（Volume）</b>', cookbookCount === 0);
      if (!S.camera.postProcessing) d.append(note('这台相机没有打开 Post Processing，以下参数不生效'));
      for (const c of comps) d.append(...this.volumeControls(c));
    }
    if (!side.children.length) side.append(note('这个场景没有可调的参数'));
  }

  propControl(m, p) {
    const attrs = p.attrs || [];
    const label = p.desc || p.name;
    const row = document.createElement('label');
    row.className = 'vw-row';
    row.title = p.name;
    const lab = document.createElement('span');
    lab.textContent = label;
    row.append(lab);
    const toggle = attrs.find((a) => /^(Toggle|ToggleOff|MaterialToggle|ToggleUI)\b/.test(a));
    const kwEnum = attrs.find((a) => a.startsWith('KeywordEnum('));
    const en = attrs.find((a) => a.startsWith('Enum('));
    const v = m.props.get(p.name);
    if (p.type === 'Texture') {
      const t = v && v.texture;
      const s = document.createElement('em');
      s.textContent = t ? t.replace(/_[0-9a-f]{6,}$/, '') : '（无）';
      row.append(s);
      return row;
    }
    if (toggle && (p.type === 'Float' || p.type === 'Range' || p.type === 'Int')) {
      const off = toggle.startsWith('ToggleOff');
      const m2 = /\(([^)]+)\)/.exec(toggle);
      const kw = toggle.startsWith('ToggleUI') ? null : m2 ? m2[1].trim() : (p.name.replace(/^_/, '') + (off ? '_OFF' : '_ON')).toUpperCase();
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = +v > 0.5;
      cb.onchange = () => { m.setFloat(p.name, cb.checked ? 1 : 0); if (kw) m.setKeyword(kw, off ? !cb.checked : cb.checked); };
      row.append(cb);
      return row;
    }
    if (kwEnum) {
      const opts = kwEnum.slice(12, -1).split(',').map((s) => s.trim());
      const sel = document.createElement('select');
      opts.forEach((o, i) => sel.append(new Option(o, i)));
      sel.value = String(Math.round(+v || 0));
      sel.onchange = () => {
        const idx = +sel.value;
        m.setFloat(p.name, idx);
        opts.forEach((o, i) => m.setKeyword((p.name + '_' + o).toUpperCase().replace(/\s+/g, '_'), i === idx));
      };
      row.append(sel);
      return row;
    }
    if (en) {
      const body = en.slice(5, -1).trim();
      let opts = ENUMS[body];
      if (!opts) { const parts = body.split(',').map((s) => s.trim()); opts = []; for (let i = 0; i + 1 < parts.length; i += 2) opts.push([parts[i], +parts[i + 1]]); }
      if (opts.length) {
        const sel = document.createElement('select');
        opts.forEach(([n, val]) => sel.append(new Option(n, val)));
        sel.value = String(+v);
        sel.onchange = () => m.setFloat(p.name, +sel.value);
        row.append(sel);
        return row;
      }
    }
    if (p.type === 'Range' || p.type === 'Float' || p.type === 'Int') {
      const isInt = p.type === 'Int' || attrs.includes('IntRange');
      let [lo, hi] = p.type === 'Range' ? p.range : guessRange(+v);
      row.append(...slider(+v, lo, hi, isInt, p.type !== 'Range', (x) => m.setFloat(p.name, x)));
      return row;
    }
    if (p.type === 'Color') {
      const hdr = isHdr(p);
      row.append(...colorInput(v, hdr, (c) => m.setVector(p.name, c)));
      return row;
    }
    if (p.type === 'Vector') {
      const wrap = document.createElement('span');
      wrap.className = 'vw-vec';
      const cur = (v || [0, 0, 0, 0]).slice();
      for (let k = 0; k < 4; k++) {
        const n = document.createElement('input');
        n.type = 'number'; n.step = 'any'; n.value = round(cur[k]);
        n.oninput = () => { cur[k] = +n.value; m.setVector(p.name, cur.slice()); };
        wrap.append(n);
      }
      row.append(wrap);
      return row;
    }
    return null;
  }

  lightControls(l, i) {
    const out = [];
    const title = document.createElement('div');
    title.className = 'vw-h';
    title.textContent = `${l.obj.name}（${{ Directional: '方向光', Point: '点光源', Spot: '聚光灯' }[l.lightType] || l.lightType}）`;
    out.push(title);
    const base = l.color.slice(0, 3);
    const update = () => {
      const lc = base.map(srgbToLinear);
      l.finalColor = [lc[0] * l.intensity, lc[1] * l.intensity, lc[2] * l.intensity, 1];
    };
    const row = (label, ...ctl) => { const r = document.createElement('label'); r.className = 'vw-row'; const s = document.createElement('span'); s.textContent = label; r.append(s, ...ctl); return r; };
    out.push(row('强度', ...slider(l.intensity, 0, Math.max(4, l.intensity * 2), false, false, (x) => { l.intensity = x; update(); })));
    out.push(row('颜色', ...colorInput([...base.map(srgbToLinear), 1], false, (c) => { for (let k = 0; k < 3; k++) base[k] = linearToSrgb(c[k]); update(); })));
    if (l.lightType !== 'Point') {
      // 由朝向反推俯仰/偏航（Unity：forward = Euler(pitch, yaw) * (0,0,1)）
      const f = l.forward;
      let pitch = (-Math.asin(Math.max(-1, Math.min(1, f[1]))) * 180) / Math.PI;
      let yaw = (Math.atan2(f[0], f[2]) * 180) / Math.PI;
      const setDir = () => {
        const p = (pitch * Math.PI) / 180, y = (yaw * Math.PI) / 180;
        l.forward = [Math.sin(y) * Math.cos(p), -Math.sin(p), Math.cos(y) * Math.cos(p)];
      };
      out.push(row('俯仰角', ...slider(pitch, -90, 90, false, false, (x) => { pitch = x; setDir(); })));
      out.push(row('方位角', ...slider(yaw, -180, 180, false, false, (x) => { yaw = x; setDir(); })));
    }
    if (l.lightType !== 'Directional') out.push(row('范围', ...slider(l.range, 0.1, Math.max(10, l.range * 2), false, false, (x) => { l.range = x; })));
    return out;
  }

  volumeControls(c) {
    const out = [];
    const short = c.type.split('.').pop();
    const head = document.createElement('label');
    head.className = 'vw-row vw-h';
    const cb = document.createElement('input');
    cb.type = 'checkbox'; cb.checked = c.active !== false;
    cb.onchange = () => { c.active = cb.checked; };
    const s = document.createElement('span');
    s.textContent = short;
    head.append(s, cb);
    out.push(head);
    for (const [k, p] of Object.entries(c.data)) {
      if (!p || typeof p !== 'object' || !('m_OverrideState' in p) || !p.m_OverrideState) continue;
      const r = document.createElement('label');
      r.className = 'vw-row';
      const lab = document.createElement('span');
      lab.textContent = k;
      r.append(lab);
      const val = p.m_Value;
      const en = VOL_ENUMS[`${short}.${k}`];
      if (en) {
        const sel = document.createElement('select');
        en.forEach((n, i) => sel.append(new Option(n, i)));
        sel.value = String(val);
        sel.onchange = () => { p.m_Value = +sel.value; };
        r.append(sel);
      } else if (typeof val === 'boolean') {
        const b = document.createElement('input');
        b.type = 'checkbox'; b.checked = val;
        b.onchange = () => { p.m_Value = b.checked; };
        r.append(b);
      } else if (typeof val === 'number') {
        const [lo, hi] = VOL_RANGES[k] || guessRange(val);
        r.append(...slider(val, Math.min(lo, val), Math.max(hi, val), Number.isInteger(val) && hi > 10 && !VOL_RANGES[k], false, (x) => { p.m_Value = x; }));
      } else if (Array.isArray(val) && (val.length === 4 || val.length === 3) && val.every((x) => typeof x === 'number') && /color|tint|filter|shadows|midtones|highlights|lift|gamma|gain/i.test(k)) {
        // Volume 的颜色参数是 sRGB 存储（URP 在用时再 .linear）
        r.append(...colorInput(val.map((x, i) => (i < 3 ? srgbToLinear(x) : x)), false, (col) => { p.m_Value = [linearToSrgb(col[0]), linearToSrgb(col[1]), linearToSrgb(col[2]), val[3] ?? 1]; }));
      } else continue;
      out.push(r);
    }
    return out;
  }

  // ---------------- 在线改代码 ----------------
  toggleCode() {
    this.codePane.hidden = !this.codePane.hidden;
    if (!this.codePane.hidden) this.buildCode();
  }

  async buildCode() {
    await loadCodeMirror(this.base);
    const lib = this.engine.shaders;
    const files = [];
    const seen = new Set();
    const add = (f) => { if (f && !seen.has(f)) { seen.add(f); files.push(f); } };
    const shaders = [...new Set([...this.scene.materials.values()].map((m) => m.shader).filter((s) => s && !s.missing))];
    shaders.sort((a, b) => isBuiltinShader(a) - isBuiltinShader(b));
    for (const s of shaders) { add(s.file); [...(s.files || [])].forEach(add); }
    for (const f of this.scene.features) if (f.impl && f.impl.shaderFiles) f.impl.shaderFiles().forEach(add);
    add('engine/glsl/Lighting.glsl');
    add('engine/glsl/Core.glsl');
    const pane = this.codePane;
    pane.innerHTML = '';
    const bar = document.createElement('div');
    bar.className = 'vw-code-bar';
    const sel = document.createElement('select');
    files.forEach((f) => sel.append(new Option(f + (this.edited.has(f) ? ' *' : ''), f)));
    const run = document.createElement('button'); run.textContent = '运行 (Ctrl+Enter)'; run.className = 'primary';
    const revert = document.createElement('button'); revert.textContent = '还原';
    const hint = document.createElement('span');
    hint.className = 'vw-code-hint';
    hint.innerHTML = '这是网页版的 GLSL；书和配套工程里是 HLSL。改动只在本页有效。';
    bar.append(sel, run, revert, hint);
    const host = document.createElement('div');
    host.className = 'vw-cm';
    pane.append(bar, host);
    const textOf = async (f) => (f.startsWith('engine/') ? (f.endsWith('Core.glsl') ? lib.core : lib.lighting) : await lib.loadText(f));
    this.cm = window.CodeMirror(host, { value: await textOf(files[0]), mode: 'x-shader/x-fragment', lineNumbers: true, matchBrackets: true, styleActiveLine: true, indentUnit: 4, tabSize: 4, lineWrapping: false });
    this.cmFile = files[0];
    sel.onchange = async () => { this.cmFile = sel.value; this.cm.setValue(await textOf(sel.value)); this.cm.clearHistory(); this.clearMarks(); };
    const doRun = () => this.runCode();
    run.onclick = doRun;
    this.cm.setOption('extraKeys', { 'Ctrl-Enter': doRun, 'Cmd-Enter': doRun });
    revert.onclick = async () => {
      const orig = this.edited.get(this.cmFile);
      if (orig === undefined) return;
      this.cm.setValue(orig);
      await this.runCode();
      this.edited.delete(this.cmFile);
    };
  }

  async runCode() {
    const f = this.cmFile, text = this.cm.getValue();
    const lib = this.engine.shaders;
    if (!this.edited.has(f)) this.edited.set(f, f.startsWith('engine/') ? (f.endsWith('Core.glsl') ? lib.core : lib.lighting) : lib.texts.get(f));
    this.errors.innerHTML = '';
    this.clearMarks();
    this.engine.errors = [];
    if (f.endsWith('Core.glsl')) lib.core = text;
    else if (f.endsWith('Lighting.glsl')) lib.lighting = text;
    let errs = [];
    if (f.startsWith('engine/')) { for (const sh of lib.shaders.values()) { try { sh.build(); } catch (e) { errs.push(e); } } }
    else errs = await lib.setSource(f, text);
    errs.forEach((e) => this.showError(e instanceof Error ? e : new Error(`${e.shader}: ${e.message}`)));
    // 渲染一帧，把编译错误收集出来
    try { this.engine.render(this.scene, this.time, 0); } catch (e) { this.showError(e); }
    if (!this.errors.children.length) { const ok = document.createElement('div'); ok.className = 'ok'; ok.textContent = '编译通过 ✓'; this.errors.append(ok); setTimeout(() => ok.remove(), 1500); }
  }

  markErrors(errs) {
    if (!this.cm) return;
    for (const e of errs) {
      if (e.file !== this.cmFile || !e.line) continue;
      const h = this.cm.addLineClass(e.line - 1, 'background', 'vw-errline');
      (this.marks || (this.marks = [])).push(h);
    }
  }

  clearMarks() { (this.marks || []).forEach((h) => this.cm.removeLineClass(h, 'background', 'vw-errline')); this.marks = []; }
}

// ---------------- 小工具 ----------------
function isBuiltinShader(s) { return !s.name.startsWith('Cookbook/') ? 1 : 0; }
function isBuiltin(m) { return isBuiltinShader(m.shader); }
function shortShader(n) { return n.replace(/^Cookbook\//, '').replace(/^Universal Render Pipeline\//, 'URP/'); }
function showProp(m, p) {
  if (/HideInInspector|PerRendererData/.test(p.flags || '')) return false;
  if (HIDDEN_ALWAYS.has(p.name)) return false;
  if (isBuiltin(m)) return BUILTIN_VISIBLE.has(p.name);
  return true;
}
function guessRange(v) {
  const a = Math.abs(v);
  if (a === 0) return [0, 1];
  if (a <= 1) return [Math.min(0, v * 2), Math.max(1, v * 2)];
  const hi = Math.pow(10, Math.ceil(Math.log10(a * 2)));
  return [v < 0 ? -hi : 0, hi];
}
function round(x) { return Math.round(x * 1000) / 1000; }
function esc(s) { return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
function note(t) { const d = document.createElement('div'); d.className = 'vw-empty'; d.textContent = t; return d; }

function slider(v, lo, hi, isInt, free, onInput) {
  const r = document.createElement('input');
  r.type = 'range';
  r.min = lo; r.max = hi; r.step = isInt ? 1 : (hi - lo) / 500;
  r.value = v;
  const n = document.createElement('input');
  n.type = 'number'; n.step = isInt ? 1 : 'any'; n.value = round(v);
  r.oninput = () => { n.value = round(+r.value); onInput(+r.value); };
  n.oninput = () => { if (free && +n.value > +r.max) r.max = n.value; r.value = n.value; onInput(+n.value); };
  return [r, n];
}

// 颜色：显示为 sRGB 取色器；HDR 颜色额外给一个强度（2 的幂次，和 Unity 的 HDR 取色器一样）
function colorInput(v, hdr, onInput) {
  const lin = (v || [1, 1, 1, 1]).slice();
  let mx = Math.max(lin[0], lin[1], lin[2]);
  let intensity = hdr && mx > 1 ? Math.log2(mx) : 0;
  const scale = Math.pow(2, intensity);
  const base = [lin[0] / scale, lin[1] / scale, lin[2] / scale];
  const c = document.createElement('input');
  c.type = 'color';
  c.value = toHex(base.map(linearToSrgb));
  const emit = () => { const s = Math.pow(2, intensity); onInput([base[0] * s, base[1] * s, base[2] * s, lin[3] ?? 1]); };
  c.oninput = () => { const rgb = fromHex(c.value).map(srgbToLinear); base[0] = rgb[0]; base[1] = rgb[1]; base[2] = rgb[2]; emit(); };
  if (!hdr) return [c];
  const n = document.createElement('input');
  n.type = 'number'; n.step = 0.1; n.value = round(intensity); n.title = 'HDR 强度（2 的幂次）';
  n.oninput = () => { intensity = +n.value; emit(); };
  return [c, n];
}
function toHex(c) { return '#' + c.map((x) => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, '0')).join(''); }
function fromHex(h) { return [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255); }

let cmPromise = null;
function loadCodeMirror(base) {
  if (window.CodeMirror) return Promise.resolve();
  if (cmPromise) return cmPromise;
  const add = (tag, attrs) => new Promise((res, rej) => { const e = document.createElement(tag); Object.assign(e, attrs); e.onload = res; e.onerror = rej; document.head.append(e); });
  cmPromise = add('link', { rel: 'stylesheet', href: base + 'vendor/codemirror/codemirror.min.css' })
    .then(() => add('script', { src: base + 'vendor/codemirror/codemirror.min.js' }))
    .then(() => Promise.all(['mode/clike/clike.min.js', 'addon/edit/matchbrackets.min.js', 'addon/selection/active-line.min.js'].map((f) => add('script', { src: base + 'vendor/codemirror/' + f }))));
  return cmPromise;
}
