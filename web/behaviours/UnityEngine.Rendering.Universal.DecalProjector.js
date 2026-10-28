// URP 的 Decal Projector 组件（网页版）。它本身不画任何东西：只把投影盒（尺寸、偏移、UV、淡出、材质）
// 登记到场景的贴花列表里，由 DecalRendererFeature 统一绘制——和 URP 的 DecalSystem 一样。
import { mat4 } from '../engine/math.js';

export default class DecalProjector {
  constructor(engine, json, obj, scene) {
    this.engine = engine; this.obj = obj; this.scene = scene; this.json = json;
    const d = json.data || {};
    this.enabled = json.enabled !== false && d.m_Enabled !== false;
    this.material = d.m_Material ? scene.materialById(d.m_Material.material) : null;
    this.size = d.m_Size || [1, 1, 1];
    this.pivot = d.m_Offset || [0, 0, 0.5];          // 盒子中心在投影器本地空间的位置（Inspector 里的 Pivot）
    this.uvScale = d.m_UVScale || [1, 1];
    this.uvBias = d.m_UVBias || [0, 0];
    this.fadeFactor = d.m_FadeFactor ?? 1;            // Opacity
    this.drawDistance = d.m_DrawDistance ?? 1000;
    this.fadeScale = d.m_FadeScale ?? 0.9;            // 距离淡出从 drawDistance × fadeScale 开始
    this.startAngleFade = d.m_StartAngleFade ?? 180;
    this.endAngleFade = d.m_EndAngleFade ?? 180;
    this.scaleMode = d.m_ScaleMode ?? 0;              // 0 Scale Invariant：忽略 Transform 的缩放
    (scene.decalProjectors = scene.decalProjectors || []).push(this);
  }

  // 投影盒矩阵：本地 [-0.5, 0.5]³ → 世界（沿 +Z 投影）
  boxMatrix() {
    const m = this.obj.matrix;
    let L = m;
    if (this.scaleMode === 0) {
      L = new Float32Array(m);
      for (let c = 0; c < 3; c++) {
        const len = Math.hypot(m[c * 4], m[c * 4 + 1], m[c * 4 + 2]) || 1;
        for (let r = 0; r < 3; r++) L[c * 4 + r] = m[c * 4 + r] / len;
      }
    }
    const [sx, sy, sz] = this.size, [px, py, pz] = this.pivot;
    const local = new Float32Array([sx, 0, 0, 0, 0, sy, 0, 0, 0, 0, sz, 0, px, py, pz, 1]);
    return mat4.mul(L, local);
  }

  // URP DecalSystem 的角度衰减系数：angleFade = (1 - (0.25 - start)/range, -0.25/range)，角度都除以 180
  angleFade() {
    if (this.startAngleFade >= 180 && this.endAngleFade >= 180) return [0, 0, 0];
    const s = this.startAngleFade / 180, e = this.endAngleFade / 180;
    const range = Math.max(0.0001, e - s);
    return [1 - (0.25 - s) / range, -0.25 / range, 1];
  }
}
