// Unity 内置粒子系统（Shuriken）的网页版：够第 21 章用的 CPU 粒子模拟 + 朝向相机的面片渲染。
// 导出数据 json.data 是 ParticleSystem 完整的序列化参数（InitialModule、ShapeModule、EmissionModule……），
// 同一物体上的 UnityEngine.ParticleSystemRenderer 组件给出材质、排序方式、Custom Vertex Streams 等。
//
// 支持的模块：
//   Main（时长/循环/预热、起始生命/速度/大小/旋转/颜色、重力、最大粒子数、模拟空间）
//   Emission（Rate over Time 曲线 + Bursts）、Shape（Cone/Sphere/Hemisphere/Box/Circle）、
//   Velocity over Lifetime（常量）、Force over Lifetime（常量）、Color/Size/Rotation over Lifetime、
//   Texture Sheet Animation（Grid，整张/单行，Frame over Time 曲线，Cycles）
// 渲染：Billboard（View 对齐），按距离/新旧排序，Max Particle Size 限制，Custom Vertex Streams
//   （Position、Color、UV、UV2、AnimBlend、AnimFrame、Center 等按 Unity 的打包规则依次塞进 TEXCOORD0..3）。
// 不支持：Noise、Collision、Sub Emitters、Trails、Lights、Limit Velocity（阻力）等。
//
// 确定性：不逐帧积分，而是“解析”地求出 time 时刻还活着的每个粒子——
//   第 k 个粒子的发射时刻由发射率积分得出，它的所有随机数由 (randomSeed, k) 哈希得到，
//   位置 = 发射点 + 初速度 × 年龄 + ½ × 加速度 × 年龄²。所以同一个 time 总得到同一帧画面，可以任意拖动时间轴。
// 书中配图在拍摄脚本里用 ps.Simulate(4) 把粒子推进到第 4 秒；网页的 time = 0 对应模拟的第 SIM_START 秒。
import { ATTRIBS } from '../engine/shaderlab.js';
import { mat4, srgbToLinear } from '../engine/math.js';

const SIM_START = 4;
const GRAVITY = -9.81;
const QUAD_UV = [[0, 0], [1, 0], [1, 1], [0, 1]];
const QUAD_POS = [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]];

export default class ParticleSystem {
  constructor(engine, json, obj, scene) {
    this.engine = engine; this.obj = obj; this.scene = scene;
    this.d = json.data || {};
    this.rendererJson = obj.json.components.find((c) => c.type === 'UnityEngine.ParticleSystemRenderer') || null;
    const d = this.d;
    this.seed = d.autoRandomSeed ? 12345 : (d.randomSeed >>> 0);
    this.duration = d.lengthInSec || 5;
    this.looping = d.looping !== false;
    this.prewarm = !!d.prewarm && this.looping;
    this.simSpeed = d.simulationSpeed ?? 1;
    this.main = d.InitialModule || {};
    this.maxParticles = this.main.maxNumParticles ?? 1000;
  }

  async init() {
    const R = this.rendererJson;
    if (!R || R.enabled === false) return;
    const rd = R.data || {};
    this.material = this.scene.materialById((R.materials || [])[0]);
    if (!this.material) return;
    this.sortMode = rd.m_SortMode ?? 0;
    this.maxSize = rd.m_MaxParticleSize ?? 0.5;
    this.minSize = rd.m_MinParticleSize ?? 0;
    this.applyColorSpace = rd.m_ApplyActiveColorSpace !== false;
    // 顶点流：没开 Custom Vertex Streams 时是默认的 Position、Normal、Color、UV
    this.streams = rd.m_UseCustomVertexStreams ? rd.m_VertexStreams.slice() : [0, 1, 3, 4];
    this.buildLayout();
    this.createMesh();
    const o = this.obj;
    this.drawObj = {
      index: -1, name: o.name + ' (particles)', active: true, layer: o.layer, json: o.json,
      matrix: mat4.identity(), invMatrix: mat4.identity(), flip: false,   // 粒子顶点已经是世界坐标
      mesh: this.mesh,
      renderer: {
        enabled: true, materials: [this.material], castShadows: false, shadowsOnly: false,
        receiveShadows: false, bounds: R.bounds ? R.bounds.map((v) => v.slice()) : [o.position.slice(), [1, 1, 1]], sortingOrder: R.sortingOrder || 0,
      },
    };
    this.scene.renderers.push(this.drawObj);
  }

  // ---------------- 顶点流打包（与 ParticleSystemRenderer 的规则一致：位置/法线/切线/颜色之外的流按分量依次填进 TEXCOORD0..3） ----------------
  buildLayout() {
    // ParticleSystemVertexStream 枚举 → 分量数
    const COMPS = { 4: 2, 5: 2, 6: 2, 7: 2, 8: 1, 9: 1, 10: 3, 11: 1, 12: 1, 13: 2, 14: 3, 15: 1, 16: 2, 17: 3, 18: 1, 19: 2, 20: 3, 21: 3, 22: 3, 23: 3, 24: 3, 25: 3, 26: 1, 27: 1, 28: 1, 29: 1, 30: 3, 31: 3, 32: 3, 33: 1, 34: 1, 35: 1, 36: 1, 37: 1, 38: 1, 39: 1, 40: 4, 41: 1, 42: 1, 43: 1, 44: 1, 45: 1, 46: 1, 47: 1 };
    this.slots = [];   // {stream, offset（在 4×4 个 texcoord 分量里的位置）, comps}
    let off = 0;
    for (const s of this.streams) {
      if (s <= 3) continue;   // Position / Normal / Tangent / Color 有专门的顶点属性
      const c = COMPS[s] || 1;
      this.slots.push({ stream: s, offset: off, comps: c });
      off += c;
    }
    this.texcoordCount = Math.min(4, Math.ceil(off / 4));
  }

  createMesh() {
    const gl = this.engine.gl;
    const N = this.maxParticles;
    this.cpu = {
      position: new Float32Array(N * 4 * 3),
      color: new Float32Array(N * 4 * 4),
      tex: new Float32Array(N * 4 * 16),   // 4 个 texcoord × vec4
    };
    const vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    const mk = (loc, data, comps, stride = 0, offset = 0) => {
      const b = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, b);
      gl.bufferData(gl.ARRAY_BUFFER, data.byteLength, gl.DYNAMIC_DRAW);
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, comps, gl.FLOAT, false, stride, offset);
      return b;
    };
    this.bPos = mk(ATTRIBS.positionOS, this.cpu.position, 3);
    this.bCol = mk(ATTRIBS.color, this.cpu.color, 4);
    // texcoord0..3 共用一个交错缓冲：每顶点 16 个 float
    this.bTex = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bTex);
    gl.bufferData(gl.ARRAY_BUFFER, this.cpu.tex.byteLength, gl.DYNAMIC_DRAW);
    const T = [ATTRIBS.texcoord0, ATTRIBS.texcoord1, ATTRIBS.texcoord2, ATTRIBS.texcoord3];
    for (let i = 0; i < 4; i++) { gl.enableVertexAttribArray(T[i]); gl.vertexAttribPointer(T[i], 4, gl.FLOAT, false, 64, i * 16); }
    gl.disableVertexAttribArray(ATTRIBS.normalOS); gl.vertexAttrib3f(ATTRIBS.normalOS, 0, 0, -1);
    gl.disableVertexAttribArray(ATTRIBS.tangentOS); gl.vertexAttrib4f(ATTRIBS.tangentOS, 1, 0, 0, 1);
    const idx = new Uint32Array(N * 6);
    for (let i = 0; i < N; i++) idx.set([i * 4, i * 4 + 1, i * 4 + 2, i * 4, i * 4 + 2, i * 4 + 3], i * 6);
    const ib = gl.createBuffer();
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ib);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, idx, gl.STATIC_DRAW);
    gl.bindVertexArray(null);
    this.mesh = { vao, ib, subMeshes: [{ start: 0, count: 0, topology: 'Triangles' }], bounds: null };
  }

  // ---------------- 每帧：求出 time 时刻活着的粒子，生成面片 ----------------
  update(time) {
    if (!this.drawObj) return;
    this.drawObj.active = this.obj.active !== false;
    let T = (time + SIM_START) * this.simSpeed;
    if (this.prewarm) T += this.duration;
    const parts = this.simulate(Math.max(0, T));
    this.buildGeometry(parts);
  }

  maxLifetime() {
    const c = this.main.startLifetime || { minMaxState: 0, scalar: 5 };
    if (c.minMaxState === 0) return c.scalar;
    if (c.minMaxState === 3) return Math.max(c.scalar, c.minScalar);
    const mx = (k) => Math.max(...k.map((x) => x[1]));
    return c.scalar * Math.max(mx(c.maxCurve), c.minMaxState === 2 ? mx(c.minCurve) : 0);
  }

  // 发射时刻表：[{id, t}]，只保留 t > T - 最长寿命 的
  emissions(T) {
    const out = [];
    const E = this.d.EmissionModule;
    if (!E || !E.enabled) return out;
    const D = this.duration, Lmax = this.maxLifetime();
    const tEnd = this.looping ? T : Math.min(T, D);
    const tStart = Math.max(0, T - Lmax);
    // Rate over Time：按系统归一化时间求发射率，积分得到第 k 个粒子的发射时刻
    const rate = E.rateOverTime;
    if (rate && (rate.scalar > 0 || rate.minScalar > 0)) {
      if (rate.minMaxState === 0) {
        const r = rate.scalar;
        const k0 = Math.max(0, Math.ceil(tStart * r - 1e-6)), k1 = Math.floor(tEnd * r - 1e-6);
        for (let k = k0; k <= k1; k++) out.push({ id: k, t: k / r });
      } else {
        const dt = 1 / 120;
        let acc = 0, k = 0;
        for (let t = 0; t < tEnd; t += dt) {
          const u = (t % D) / D;
          const r = evalCurve(rate, u, hash01(this.seed, Math.floor(t / D), 99));
          const next = acc + r * dt;
          // 累积发射数越过整数 k 的时刻就是第 k 个粒子的发射时刻（常量发射率时 = k / rate）
          while (k < next) {
            const te = t + (dt * (k - acc)) / Math.max(next - acc, 1e-9);
            if (te >= tStart && te <= tEnd) out.push({ id: k, t: te });
            k++;
          }
          acc = next;
        }
      }
    }
    // Bursts：每个循环周期里按设定的时间、次数、间隔一次发射一批
    (E.m_Bursts || []).slice(0, E.m_BurstCount ?? 99).forEach((b, bi) => {
      const cycles = this.looping ? Math.floor(T / D) + 1 : 1;
      for (let c = 0; c < cycles; c++) {
        const n = Math.max(1, b.cycleCount || 1);
        for (let i = 0; i < n; i++) {
          const t = c * D + (b.time || 0) + i * (b.repeatInterval || 0.01);
          if (t < tStart || t > tEnd || (b.time || 0) + i * (b.repeatInterval || 0) > D) continue;
          const bid = (bi * 100000 + c * 1000 + i) * 1000;
          if (b.probability !== undefined && hash01(this.seed, bid, 98) > b.probability) continue;
          const cnt = Math.round(evalCurve(b.countCurve || { minMaxState: 0, scalar: b.minCount || 0 }, ((t % D) / D), hash01(this.seed, bid, 97)));
          for (let j = 0; j < cnt; j++) out.push({ id: 1e9 + bid + j, t });
        }
      }
    });
    return out;
  }

  simulate(T) {
    const M = this.main, D = this.duration;
    const em = this.emissions(T);
    const live = [];
    const L2W = this.obj.matrix;
    const shape = this.d.ShapeModule;
    const vel = this.d.VelocityModule, force = this.d.ForceModule;
    const sizeM = this.d.SizeModule, colM = this.d.ColorModule, rotM = this.d.RotationModule;
    for (const e of em) {
      const r = (ch) => hash01(this.seed, e.id, ch);
      const u = ((e.t % D) / D);
      const life = evalCurve(M.startLifetime, u, r(1));
      const age = T - e.t;
      if (age < 0 || age >= life) continue;
      const nAge = age / life;
      // 发射形状：局部空间的位置与方向（Shape 的 +Z 是发射方向），再变到世界空间
      const { pos, dir } = shapeSample(shape, (ch) => r(10 + ch));
      const p0 = mat4.transformPoint(L2W, pos);
      const d0 = normalize(mat4.transformDir(L2W, dir));
      const speed = evalCurve(M.startSpeed, u, r(2));
      const v = [d0[0] * speed, d0[1] * speed, d0[2] * speed];
      const acc = [0, GRAVITY * evalCurve(M.gravityModifier, u, r(3)), 0];
      // Velocity over Lifetime / Force over Lifetime：只支持常量（随机两常量）
      if (vel && vel.enabled) {
        let w = [evalCurve(vel.x, 0, r(20)), evalCurve(vel.y, 0, r(21)), evalCurve(vel.z, 0, r(22))];
        if (!vel.inWorldSpace) w = mat4.transformDir(L2W, w);
        const sm = evalCurve(vel.speedModifier, nAge, r(23));
        for (let k = 0; k < 3; k++) v[k] = v[k] * sm + w[k];
      }
      if (force && force.enabled) {
        let f = [evalCurve(force.x, 0, r(24)), evalCurve(force.y, 0, r(25)), evalCurve(force.z, 0, r(26))];
        if (!force.inWorldSpace) f = mat4.transformDir(L2W, f);
        for (let k = 0; k < 3; k++) acc[k] += f[k];
      }
      const p = [0, 1, 2].map((k) => p0[k] + v[k] * age + 0.5 * acc[k] * age * age);
      // 大小、旋转、颜色
      let size = evalCurve(M.startSize, u, r(4));
      if (sizeM && sizeM.enabled) size *= evalCurve(sizeM.curve, nAge, r(30));
      let rot = evalCurve(M.startRotation, u, r(5));
      if (M.randomizeRotationDirection && r(6) < M.randomizeRotationDirection) rot = -rot;
      if (rotM && rotM.enabled) rot += evalCurve(rotM.curve, nAge, r(31)) * age;   // 常量角速度（弧度/秒）
      let col = evalGradient(M.startColor, u, r(7));
      if (colM && colM.enabled) { const c2 = evalGradient(colM.gradient, nAge, r(32)); col = col.map((x, i) => x * c2[i]); }
      if (this.applyColorSpace) col = [srgbToLinear(col[0]), srgbToLinear(col[1]), srgbToLinear(col[2]), col[3]];
      live.push({ id: e.id, t: e.t, p, size, rot, col, nAge, life, age, rnd: r(40) });
    }
    // 最大粒子数：超出部分（最新发射的）丢掉
    if (live.length > this.maxParticles) { live.sort((a, b) => a.t - b.t); live.length = this.maxParticles; }
    return live;
  }

  // Texture Sheet Animation：返回 [当前帧号（小数部分 = AnimBlend）, 总帧数, 列, 行]
  sheetFrame(pt) {
    const U = this.d.UVModule;
    if (!U || !U.enabled || U.mode !== 0) return null;
    const tx = Math.max(1, U.tilesX), ty = Math.max(1, U.tilesY);
    const singleRow = U.animationType === 1;
    const frames = singleRow ? tx : tx * ty;
    const cycles = U.cycles || 1;
    let x = (pt.nAge * cycles) % 1;
    if (U.timeMode === 2) x = 0;   // FPS 模式不支持，退化为第 0 帧
    const f = evalCurve(U.frameOverTime, x, pt.rnd) * frames + evalCurve(U.startFrame, 0, pt.rnd);
    let row = 0;
    if (singleRow) row = U.rowMode === 1 ? Math.floor(pt.rnd * ty) : (U.rowIndex || 0);
    return { f: Math.min(Math.max(f, 0), frames - 1e-4), frames, tx, ty, singleRow, row };
  }

  tileUV(sf, frame, q) {
    let col, row;
    if (sf.singleRow) { col = frame % sf.tx; row = sf.row; }
    else { col = frame % sf.tx; row = Math.floor(frame / sf.tx); }
    // 第 0 帧在左上角，V 轴向上
    return [(col + q[0]) / sf.tx, (sf.ty - 1 - row + q[1]) / sf.ty];
  }

  buildGeometry(parts) {
    const gl = this.engine.gl, cam = this.scene.camera;
    const V = cam.view;
    const right = [V[0], V[4], V[8]], up = [V[1], V[5], V[9]], back = [V[2], V[6], V[10]];
    const camPos = mat4.transformPoint(mat4.invert(V), [0, 0, 0]);
    const dist2 = (p) => (p[0] - camPos[0]) ** 2 + (p[1] - camPos[1]) ** 2 + (p[2] - camPos[2]) ** 2;
    // 排序：0 None（发射顺序）、1 By Distance（远的先画）、2 Oldest in Front、3 Youngest in Front
    if (this.sortMode === 1) parts.sort((a, b) => dist2(b.p) - dist2(a.p));
    else if (this.sortMode === 2) parts.sort((a, b) => b.t - a.t);
    else if (this.sortMode === 3) parts.sort((a, b) => a.t - b.t);
    else parts.sort((a, b) => a.t - b.t);
    const n = Math.min(parts.length, this.maxParticles);
    const { position, color, tex } = this.cpu;
    tex.fill(0);
    const tanHalf = cam.orthographic ? 0 : Math.tan((cam.fov * Math.PI) / 360);
    for (let i = 0; i < n; i++) {
      const pt = parts[i];
      // Max/Min Particle Size：屏幕上的大小不超过视口高度的这个比例
      let s = pt.size;
      if (tanHalf > 0) {
        const z = Math.max(1e-4, -((pt.p[0] - camPos[0]) * back[0] + (pt.p[1] - camPos[1]) * back[1] + (pt.p[2] - camPos[2]) * back[2]));
        const view = 2 * z * tanHalf;
        s = Math.min(Math.max(s, this.minSize * view), this.maxSize * view);
      }
      const c = Math.cos(pt.rot), sn = Math.sin(pt.rot);
      const sf = this.sheetFrame(pt);
      const f0 = sf ? Math.floor(sf.f) : 0, blend = sf ? sf.f - f0 : 0;
      for (let k = 0; k < 4; k++) {
        const vi = i * 4 + k;
        // 绕视线方向旋转（Unity 的正旋转在屏幕上是顺时针）
        const qx = QUAD_POS[k][0] * s, qy = QUAD_POS[k][1] * s;
        const x = qx * c + qy * sn, y = -qx * sn + qy * c;
        for (let a = 0; a < 3; a++) position[vi * 3 + a] = pt.p[a] + right[a] * x + up[a] * y;
        color.set(pt.col, vi * 4);
        const uv = sf ? this.tileUV(sf, f0, QUAD_UV[k]) : QUAD_UV[k];
        const uv2 = sf ? this.tileUV(sf, (f0 + 1) % sf.frames, QUAD_UV[k]) : QUAD_UV[k];
        for (const sl of this.slots) {
          let val;
          switch (sl.stream) {
            case 4: val = uv; break;                   // UV
            case 5: val = uv2; break;                  // UV2（下一帧）
            case 8: val = [blend]; break;              // AnimBlend
            case 9: val = [sf ? f0 : 0]; break;        // AnimFrame
            case 10: val = pt.p; break;                // Center
            case 11: val = [k]; break;                 // VertexID
            case 12: val = [s]; break;                 // SizeX
            case 26: val = [pt.rot]; break;            // Rotation
            case 33: val = [pt.nAge]; break;           // AgePercent
            case 34: val = [1 / pt.life]; break;       // InvStartLifetime
            case 40: val = [pt.rnd, pt.rnd, pt.rnd, pt.rnd]; break;   // StableRandomXYZW
            default: val = [0, 0, 0, 0];
          }
          for (let q = 0; q < sl.comps; q++) {
            const o = sl.offset + q;
            if (o < 16) tex[vi * 16 + o] = val[q] ?? 0;
          }
        }
      }
    }
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bPos); gl.bufferSubData(gl.ARRAY_BUFFER, 0, position, 0, n * 12);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bCol); gl.bufferSubData(gl.ARRAY_BUFFER, 0, color, 0, n * 16);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.bTex); gl.bufferSubData(gl.ARRAY_BUFFER, 0, tex, 0, n * 64);
    this.mesh.subMeshes[0].count = n * 6;
    this.drawObj.renderer.enabled = n > 0;
    this.count = n;
  }
}

// ---------------- 工具 ----------------
// (seed, 粒子编号, 通道) → [0, 1) 的稳定随机数
function hash01(seed, id, ch) {
  let h = (Math.imul(seed ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul((id % 4294967296) | 0, 0xc2b2ae35) ^ Math.imul(Math.floor(id / 4294967296) + ch * 0x27d4eb2f, 0x165667b1)) >>> 0;
  h ^= h >>> 16; h = Math.imul(h, 0x7feb352d) >>> 0;
  h ^= h >>> 15; h = Math.imul(h, 0x846ca68b) >>> 0;
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

function normalize(v) { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; }

// AnimationCurve：keys = [[time, value, inSlope, outSlope], ...]，相邻关键帧之间是 Hermite 插值
function curveValue(keys, t) {
  if (!keys || !keys.length) return 0;
  if (t <= keys[0][0]) return keys[0][1];
  const last = keys[keys.length - 1];
  if (t >= last[0]) return last[1];
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i], b = keys[i + 1];
    if (t > b[0]) continue;
    const dt = b[0] - a[0];
    if (dt <= 0) return b[1];
    const s = (t - a[0]) / dt, s2 = s * s, s3 = s2 * s;
    const m0 = (Number.isFinite(a[3]) ? a[3] : 0) * dt, m1 = (Number.isFinite(b[2]) ? b[2] : 0) * dt;
    return (2 * s3 - 3 * s2 + 1) * a[1] + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * b[1] + (s3 - s2) * m1;
  }
  return last[1];
}

// MinMaxCurve：0 常量、1 曲线、2 两条曲线之间随机、3 两个常量之间随机
function evalCurve(c, t, rnd) {
  if (!c) return 0;
  switch (c.minMaxState) {
    case 1: return c.scalar * curveValue(c.maxCurve, t);
    case 2: { const a = curveValue(c.minCurve, t), b = curveValue(c.maxCurve, t); return c.scalar * (a + (b - a) * rnd); }
    case 3: return c.minScalar + (c.scalar - c.minScalar) * rnd;
    default: return c.scalar;
  }
}

// Gradient：color = [[t, r, g, b]], alpha = [[t, a]]，线性混合
function gradientValue(g, t) {
  if (!g) return [1, 1, 1, 1];
  const lerpKeys = (keys, n) => {
    if (!keys || !keys.length) return new Array(n).fill(1);
    if (t <= keys[0][0]) return keys[0].slice(1);
    for (let i = 0; i < keys.length - 1; i++) {
      const a = keys[i], b = keys[i + 1];
      if (t <= b[0]) { const s = b[0] > a[0] ? (t - a[0]) / (b[0] - a[0]) : 1; return a.slice(1).map((v, k) => v + (b[k + 1] - v) * s); }
    }
    return keys[keys.length - 1].slice(1);
  };
  const c = lerpKeys(g.color, 3), a = lerpKeys(g.alpha, 1);
  return [c[0], c[1], c[2], a[0]];
}

// MinMaxGradient：0 颜色、1 渐变、2 两色随机、3 两渐变随机、4 渐变里随机取一点
function evalGradient(g, t, rnd) {
  if (!g) return [1, 1, 1, 1];
  const mix = (a, b, s) => a.map((v, i) => v + (b[i] - v) * s);
  switch (g.minMaxState) {
    case 1: return gradientValue(g.maxGradient, t);
    case 2: return mix(g.minColor, g.maxColor, rnd);
    case 3: return mix(gradientValue(g.minGradient, t), gradientValue(g.maxGradient, t), rnd);
    case 4: return gradientValue(g.maxGradient, rnd);
    default: return (g.maxColor || [1, 1, 1, 1]).slice();
  }
}

// Shape 模块：局部空间（+Z 为发射方向）的发射位置与方向
function shapeSample(S, r) {
  if (!S || !S.enabled) return { pos: [0, 0, 0], dir: [0, 0, 1] };
  const R = (S.radius && S.radius.value !== undefined ? S.radius.value : S.radius) ?? 1;
  const thick = S.radiusThickness ?? 1;
  const arc = (((S.arc && S.arc.value) ?? 360) * Math.PI) / 180;
  const sc = S.m_Scale || [1, 1, 1];
  let pos, dir;
  switch (S.type) {
    case 0: case 1: case 2: case 3: {   // Sphere / Hemisphere（Shell = 只在表面）
      const z = S.type >= 2 ? r(0) : r(0) * 2 - 1, ph = r(1) * 2 * Math.PI, s = Math.sqrt(Math.max(0, 1 - z * z));
      dir = [s * Math.cos(ph), s * Math.sin(ph), z];
      const rr = S.type === 1 || S.type === 3 ? R : R * Math.cbrt(1 - thick + thick * r(2));
      pos = dir.map((v) => v * rr);
      break;
    }
    case 5: case 15: case 16:   // Box：盒内随机，沿 +Z 发射
      pos = [(r(0) - 0.5) * sc[0], (r(1) - 0.5) * sc[1], (r(2) - 0.5) * sc[2]];
      dir = [0, 0, 1];
      break;
    case 10: case 11: {   // Circle：XY 平面上的圆盘，沿半径向外
      const ph = r(1) * arc, rr = S.type === 11 ? R : R * Math.sqrt(1 - thick + thick * r(0));
      dir = [Math.cos(ph), Math.sin(ph), 0];
      pos = [dir[0] * rr, dir[1] * rr, 0];
      break;
    }
    default: {   // Cone（从底面发射）：底面圆盘上随机取点，方向按到中心的距离向外倾斜 angle
      const ph = r(1) * arc;
      const k = S.type === 7 ? 1 : Math.sqrt(1 - thick + thick * r(0));   // 0..1：到中心的归一化距离
      const ang = (((S.angle ?? 25) * Math.PI) / 180) * k;
      pos = [Math.cos(ph) * k * R, Math.sin(ph) * k * R, 0];
      dir = [Math.cos(ph) * Math.sin(ang), Math.sin(ph) * Math.sin(ang), Math.cos(ang)];
      if (S.type === 8 || S.type === 9) {   // ConeVolume：沿长度方向随机推进
        const L = (S.length ?? 5) * r(3);
        pos = pos.map((v, i) => v + dir[i] * L);
      }
    }
  }
  // Shape 的 Position / Rotation（欧拉角，度）/ Scale
  const P = S.m_Position || [0, 0, 0], E = S.m_Rotation || [0, 0, 0];
  if (S.type !== 5 && S.type !== 15 && S.type !== 16) pos = pos.map((v, i) => v * sc[i]);
  if (E[0] || E[1] || E[2]) { pos = rotateEuler(pos, E); dir = rotateEuler(dir, E); }
  return { pos: pos.map((v, i) => v + P[i]), dir };
}

// Unity 的欧拉角旋转顺序：先 Z、再 X、再 Y
function rotateEuler(v, e) {
  const [x, y, z] = e.map((d) => (d * Math.PI) / 180);
  let [a, b, c] = v;
  [a, b] = [a * Math.cos(z) - b * Math.sin(z), a * Math.sin(z) + b * Math.cos(z)];
  [b, c] = [b * Math.cos(x) - c * Math.sin(x), b * Math.sin(x) + c * Math.cos(x)];
  [a, c] = [a * Math.cos(y) + c * Math.sin(y), -a * Math.sin(y) + c * Math.cos(y)];
  return [a, b, c];
}
