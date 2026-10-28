// 案例 23.4：让一个 Blob 阴影 Quad 跟随目标物体（网页版，对应 Ch23/BlobShadow.cs）。
// 每帧从目标向下“找地面”，把 Quad 贴到地面上、对齐地面法线，
// 并根据离地高度放大、变淡（物体跳得越高，影子越大越虚）。
// 网页里没有物理系统，射线检测简化为：地面就是 y = fallbackGroundY 的水平面（书里的场景正是如此）。
export default class BlobShadow {
  constructor(engine, json, obj, scene) {
    this.engine = engine; this.obj = obj; this.scene = scene;
    const d = json.data || {};
    this.d = {
      baseSize: d.baseSize ?? 1, growth: d.growth ?? 0.8, maxHeight: d.maxHeight ?? 3,
      strength: d.strength ?? 0.8, fallbackGroundY: d.fallbackGroundY ?? 0,
    };
    // 导出数据里引用的 Transform 以 {component: 物体序号} 表示
    const t = d.target && d.target.component;
    this.target = t !== undefined && t !== null ? scene.objects[t] : null;
  }

  update() { this.apply(); }

  apply() {
    const target = this.target, d = this.d;
    if (!target) return;
    const m = target.matrix;
    const origin = [m[12], m[13], m[14]];
    const groundPos = [origin[0], d.fallbackGroundY, origin[2]];
    const height = Math.max(0, origin[1] - groundPos[1]);
    const t = Math.min(1, Math.max(0, height / d.maxHeight));

    // Quad 默认朝 -Z，旋转到“正面朝上”（绕 X 轴 +90°，与 Quaternion.FromToRotation(back, up) 相同）
    const s = d.baseSize * (1 + d.growth * t);
    const p = [groundPos[0], groundPos[1] + 0.005, groundPos[2]];
    this.scene.setMatrix(this.obj, new Float32Array([s, 0, 0, 0, 0, 0, s, 0, 0, -s, 0, 0, p[0], p[1], p[2], 1]));
    if (this.obj.renderer) {
      const c = this.obj.renderer.bounds[0];
      c[0] = p[0]; c[1] = p[1]; c[2] = p[2];
    }

    // C# 用 MaterialPropertyBlock 改每个阴影自己的浓度；网页版对应“逐物体 uniform”
    this.obj.uniforms = this.obj.uniforms || {};
    this.obj.uniforms._Strength = d.strength * (1 - t);
  }
}
