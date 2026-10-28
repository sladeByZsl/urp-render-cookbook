// 案例 20.7–20.9：批量绘制草丛 + 上传交互体（网页版，对应 Ch20/GrassRenderer.cs）。
// C# 用 Graphics.RenderMeshInstanced 每 1023 个实例一批提交；WebGL2 没有这个 API，
// 这里往场景里加一个“自定义绘制物体”：同一个草丛网格 + instanceCount，引擎用 drawElementsInstanced 一次画完，
// 每实例矩阵和 _Variation 打包进一张 RGBA32F 贴图（Grass.glsl 里按 gl_InstanceID 读取），
// 主画面、阴影 Pass 都走引擎的普通流程（和 RenderParams 里的 shadowCastingMode / receiveShadows 一样）。
//
// 实例数据在 C# 里由拍摄脚本 Ch20Shots.Grass() 调 SetInstances() 填入，不会被序列化导出，
// 所以网页版按同样的参数（区域、间距、随机种子、筛选规则）重新生成：
//   - System.Random 按 .NET 源码逐位复刻，位置、旋转、缩放、颜色随机值与 Unity 一致；
//   - 地面高度直接从场景里的地形网格插值（等价于 C# 里的高度函数 h(x, z)）；
//   - 缩放用到的 Mathf.PerlinNoise 是近似实现（只影响 ±20% 的大小起伏）。
import { mat4 } from '../engine/math.js';

const DATA_WIDTH = 1024;   // 与 Grass.glsl 的 GRASS_DATA_WIDTH 一致
const MAX_INTERACTORS = 8;

// 各配图调用 Ch20Shots.Grass(s, h, area, spacing, accept, seed) 的参数
const SHOTS = {
  'ch20-grass-field': { area: [-14, -8, 28, 34], spacing: 0.24 },
  'ch20-grass-interact': { area: [-6, -4, 12, 12], spacing: 0.16 },
  'ch20-grass-fade': { area: [-16, -6, 32, 40], spacing: 0.3 },
  // 只在平缓、低于雪线的地方长草
  'ch20-final': {
    area: [-16, -14, 30, 30], spacing: 0.26,
    accept: (x, z, h) => {
      const e = 0.3, y = h(x, z);
      const dx = (h(x + e, z) - h(x - e, z)) / (2 * e), dz = (h(x, z + e) - h(x, z - e)) / (2 * e);
      return dx * dx + dz * dz < 0.12 && y < 4 && y > -0.3;
    },
  },
};

export default class GrassRenderer {
  constructor(engine, json, obj, scene) {
    this.engine = engine; this.obj = obj; this.scene = scene;
    const d = json.data || {};
    this.d = d;
    this.castShadows = d.castShadows !== false;
    this.interactorRadius = d.interactorRadius ?? 1;
    // 导出数据里引用的 Transform 以 {component: 物体序号} 表示
    this.interactors = (d.interactors || []).map((t) => (t && t.component !== undefined && t.component !== null ? scene.objects[t.component] : null));
  }

  async init() {
    const E = this.engine, S = this.scene, d = this.d;
    const material = d.material && S.materialById(d.material.material);
    if (!material || !d.mesh || !d.mesh.mesh) return;
    const mesh = await E.assets.mesh(d.mesh.mesh);
    const { matrices, variation } = this.buildInstances();
    this.setInstances(matrices, variation, mesh, material);
  }

  //#region setInstances
  /// 设置所有实例：矩阵（每个 12 个数 = 前三行）+ 每实例一个 0..1 的随机值（Shader 里用来做颜色变化）
  setInstances(matrices, variation, mesh, material) {
    const n = variation.length;
    if (!n) return;
    const texels = n * 4, rows = Math.ceil(texels / DATA_WIDTH);
    const data = new Float32Array(DATA_WIDTH * rows * 4);
    const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < n; i++) {
      data.set(matrices.subarray(i * 12, i * 12 + 12), i * 16);
      data[i * 16 + 12] = variation[i];
      const p = [matrices[i * 12 + 3], matrices[i * 12 + 7], matrices[i * 12 + 11]];
      for (let k = 0; k < 3; k++) { min[k] = Math.min(min[k], p[k]); max[k] = Math.max(max[k], p[k]); }
    }
    const tex = this.engine.glc.texture2D(DATA_WIDTH, rows, 'RGBA32F', data, { mips: false, filter: 'Point', wrap: 'Clamp' });
    // 外扩 1 米，留给草高和弯曲
    const center = [0, 1, 2].map((k) => (min[k] + max[k]) * 0.5);
    const extents = [0, 1, 2].map((k) => (max[k] - min[k]) * 0.5 + 1);
    const o = this.obj;
    this.drawObj = {
      index: -1, name: o.name + ' (instanced)', active: true, layer: o.layer, json: o.json,
      matrix: mat4.identity(), invMatrix: mat4.identity(), flip: false,
      mesh, instanceCount: n,
      renderer: {
        enabled: true, materials: [material], castShadows: this.castShadows, shadowsOnly: false,
        receiveShadows: true, bounds: [center, extents], sortingOrder: 0,
      },
      uniforms: { _GrassInstanceData: tex },
    };
    this.scene.renderers.push(this.drawObj);
    this.count = n;
  }
  //#endregion

  // 每帧（C# 是每个相机开始渲染时）上传交互体：全局数组，所有用到它的材质都能读到
  update() {
    if (this.drawObj) this.drawObj.active = this.obj.active !== false;
    const arr = new Float32Array(MAX_INTERACTORS * 4);
    let n = 0;
    for (const t of this.interactors) {
      if (!t || n >= MAX_INTERACTORS) continue;
      const m = t.matrix, s = (t.json.lossyScale || [1])[0];
      arr.set([m[12], m[13], m[14], this.interactorRadius * s], n * 4);
      n++;
    }
    this.engine.setGlobal('_Ch20Interactors', arr);
    this.engine.setGlobal('_Ch20InteractorCount', n);
  }

  // ---------------- 复刻 Ch20Shots.Grass() 的实例生成 ----------------
  buildInstances() {
    const cfg = SHOTS[this.scene.doc.id] || null;
    const h = this.terrainHeight();
    let area, spacing, accept = null;
    if (cfg) { area = cfg.area; spacing = cfg.spacing; accept = cfg.accept || null; }
    else {
      // 不认识的场景：铺满地形
      const b = this.terrain ? this.terrain.renderer.bounds : [[0, 0, 0], [5, 0, 5]];
      area = [b[0][0] - b[1][0], b[0][2] - b[1][2], b[1][0] * 2, b[1][2] * 2]; spacing = 0.3;
    }
    const f = Math.fround;
    const rnd = new DotNetRandom(5);
    const R = () => f(rnd.nextDouble());
    const mats = [], vars = [];
    const [ax, ay, aw, ah] = area.map(f);
    const sp = f(spacing);
    // C# 用 float 累加循环变量，次数要与之一致，所以全程用 Math.fround 模拟单精度
    for (let z = ay; z < f(ay + ah); z = f(z + sp)) {
      for (let x = ax; x < f(ax + aw); x = f(x + sp)) {
        const px = f(x + f(f(R() - 0.5) * sp));
        const pz = f(z + f(f(R() - 0.5) * sp));
        if (accept && !accept(px, pz, h)) continue;
        const py = h(px, pz);
        const sc = lerp(0.75, 1.35, R()) * lerp(0.8, 1.2, fbm(px * 0.3, pz * 0.3, 2));
        const yaw = (R() * 360 * Math.PI) / 180;
        // Matrix4x4.TRS(p, Euler(0, yaw, 0), sc) 的前三行（Unity 左手系绕 Y 旋转）
        const c = Math.cos(yaw) * sc, s = Math.sin(yaw) * sc;
        mats.push(c, 0, s, px, 0, sc, 0, py, -s, 0, c, pz);
        vars.push(R());
      }
    }
    return { matrices: new Float32Array(mats), variation: new Float32Array(vars) };
  }

  // 地形高度：在场景里名为 Terrain 的规则网格（Heightfield.Build 生成）上按三角形插值
  terrainHeight() {
    const t = this.scene.objects.find((o) => o.name === 'Terrain' && o.mesh && o.mesh.cpu && o.mesh.cpu.position);
    this.terrain = t;
    if (!t) return () => 0;
    const pos = t.mesh.cpu.position, vc = t.mesh.header.vertexCount;
    const N = Math.round(Math.sqrt(vc)) - 1;   // 每边段数
    const x0 = pos[0], z0 = pos[2], step = (pos[(N) * 3] - x0) / N;
    const m = t.matrix;   // 地形物体在原点，这里仍按平移处理
    const Y = (ix, iz) => pos[(iz * (N + 1) + ix) * 3 + 1];
    return (wx, wz) => {
      const gx = Math.min(Math.max((wx - m[12] - x0) / step, 0), N - 1e-4), gz = Math.min(Math.max((wz - m[14] - z0) / step, 0), N - 1e-4);
      const ix = Math.floor(gx), iz = Math.floor(gz), fx = gx - ix, fz = gz - iz;
      const h00 = Y(ix, iz), h10 = Y(ix + 1, iz), h01 = Y(ix, iz + 1), h11 = Y(ix + 1, iz + 1);
      // 与 Heightfield.Build 的三角形划分一致：(a, b, a+1) 与 (a+1, b, b+1)
      const y = fx + fz <= 1 ? h00 + fx * (h10 - h00) + fz * (h01 - h00) : h11 + (1 - fx) * (h01 - h11) + (1 - fz) * (h10 - h11);
      return y + m[13];
    };
  }
}

function lerp(a, b, t) { t = Math.min(Math.max(t, 0), 1); return a + (b - a) * t; }

// .NET（Mono）System.Random(seed) 的 Knuth 减法生成器，按参考源码逐行移植
class DotNetRandom {
  constructor(seed) {
    const MBIG = 2147483647, MSEED = 161803398;
    const a = new Int32Array(56);
    const sub = seed === -2147483648 ? 2147483647 : Math.abs(seed);
    let mj = MSEED - sub;
    a[55] = mj;
    let mk = 1;
    for (let i = 1; i < 55; i++) {
      const ii = (21 * i) % 55;
      a[ii] = mk;
      mk = mj - mk;
      if (mk < 0) mk += MBIG;
      mj = a[ii];
    }
    for (let k = 1; k < 5; k++)
      for (let i = 1; i < 56; i++) {
        a[i] -= a[1 + ((i + 30) % 55)];
        if (a[i] < 0) a[i] += MBIG;
      }
    this.a = a; this.inext = 0; this.inextp = 21; this.MBIG = MBIG;
  }
  sample() {
    let n = this.inext, np = this.inextp;
    if (++n >= 56) n = 1;
    if (++np >= 56) np = 1;
    let r = this.a[n] - this.a[np];
    if (r === this.MBIG) r--;
    if (r < 0) r += this.MBIG;
    this.a[n] = r;
    this.inext = n; this.inextp = np;
    return r;
  }
  nextDouble() { return this.sample() * (1 / this.MBIG); }
}

// Mathf.PerlinNoise 的近似（经典改进 Perlin 噪声，输出约 0..1）与 Heightfield.Fbm
const PERM = [151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180];
const P = new Int32Array(512);
for (let i = 0; i < 512; i++) P[i] = PERM[i & 255];
function grad(h, x, y) { h &= 15; const u = h < 8 ? x : y, v = h < 4 ? y : h === 12 || h === 14 ? x : 0; return ((h & 1) === 0 ? u : -u) + ((h & 2) === 0 ? v : -v); }
function perlin(x, y) {
  const X = Math.floor(x) & 255, Y = Math.floor(y) & 255;
  x -= Math.floor(x); y -= Math.floor(y);
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  const u = fade(x), v = fade(y);
  const A = P[X] + Y, B = P[X + 1] + Y;
  const l = (t, a, b) => a + t * (b - a);
  const n = l(v, l(u, grad(P[P[A]], x, y), grad(P[P[B]], x - 1, y)), l(u, grad(P[P[A + 1]], x, y - 1), grad(P[P[B + 1]], x - 1, y - 1)));
  return Math.min(Math.max((n + 1) * 0.5, 0), 1);
}
function fbm(x, z, octaves = 5) {
  let sum = 0, amp = 0.5, freq = 1, norm = 0;
  for (let i = 0; i < octaves; i++) {
    sum += perlin(x * freq + i * 17.13, z * freq - i * 9.71) * amp;
    norm += amp; amp *= 0.5; freq *= 2.03;
  }
  return sum / norm;
}
