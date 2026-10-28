// 渲染到 RenderTexture 的副相机（Camera.targetTexture 不为空、且不是主相机）。
// 例：第 16 章的 MsaaView 用一台关掉的副相机以真正的 MSAA 渲染到低分辨率 RT，主相机只拍一块显示这张 RT 的 Quad。
// 网页版每帧先用这台相机把场景画进自己的 RT，再把场景里引用这张 RT 的材质贴图换成它的结果。
import { Frame, Camera } from '../engine/pipeline.js';
import { RenderPassEvent } from '../engine/features.js';

class RTFrame extends Frame {
  constructor(engine, scene, cam, w, h, time, dt, key, srgb) {
    const main = scene.camera;
    scene.camera = cam;                 // Frame 构造时按 scene.camera 决定 MSAA/HDR
    super(engine, scene, w, h, time, dt);
    scene.camera = main;
    this.camera = cam;
    this.rtKey = key;
    if (srgb) { this.hdr = false; this.colorFormat = 'SRGB8_ALPHA8'; }
    // 本相机画的场景不需要深度/不透明贴图时别抢主相机的同名 RT（尺寸不同会被反复重建）
    this.requireDepth = false;
    this.requireOpaque = false;
  }

  beginCamera() {
    const E = this.engine, gl = this.gl, cam = this.camera;
    this.cameraTarget = E.rt(this.rtKey, this.width, this.height, { color: this.colorFormat, depth: 'DEPTH24_STENCIL8', samples: this.msaa, renderbuffers: true, filter: this.filter });
    E.bindTarget(this.cameraTarget);
    gl.depthMask(true); gl.colorMask(true, true, true, true); gl.stencilMask(255);
    const bg = cam.clearFlags === 'SolidColor' ? cam.background : [0, 0, 0, 0];
    gl.clearColor(bg[0], bg[1], bg[2], bg[3]);
    gl.clearDepth(1); gl.clearStencil(0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);
    E.setGlobal('_CameraDepthTexture', E.glc.defaults.white);
    E.setGlobal('_CameraOpaqueTexture', E.glc.defaults.gray);
  }
}

export default class RenderTextureCamera {
  constructor(engine, json, obj, scene) {
    this.engine = engine; this.json = json; this.obj = obj; this.scene = scene;
    const o = obj.json;
    const add = o.components.find((x) => x.type.endsWith('UniversalAdditionalCameraData'));
    this.cam = new Camera(json, o, add ? add.data : {});
    this.cam.aspect = json.aspect;
    this.key = json.targetTexture;
  }

  async init() {
    this.meta = await this.engine.assets.textureMeta(this.key);
    if (!this.meta) throw new Error(`副相机的目标贴图 ${this.key} 不在贴图索引里`);
  }

  update(time, dt) {
    const E = this.engine, S = this.scene, m = this.meta, gl = E.gl;
    if (S.__rtCameraBusy) return;
    S.__rtCameraBusy = true;
    const prevVP = E.prevViewProj;
    try {
      const frame = new RTFrame(E, S, this.cam, m.width, m.height, time, dt, 'rtcam:' + this.key, m.rtFormat === 'ARGB32' || !!m.srgb);
      frame.filter = m.filter === 'Point' ? 'Point' : 'Bilinear';
      frame.setupCamera();
      frame.setupLights();
      frame.setupEnvironment();
      const passes = [
        { event: RenderPassEvent.BeforeRenderingShadows + 1, builtin: true, run: () => frame.renderShadows() },
        { event: RenderPassEvent.BeforeRenderingOpaques + 1, builtin: true, run: () => frame.renderOpaques() },
        { event: RenderPassEvent.AfterRenderingOpaques, builtin: true, run: () => frame.copyDepth() },
        { event: RenderPassEvent.BeforeRenderingSkybox + 1, builtin: true, run: () => frame.renderSkybox() },
        { event: RenderPassEvent.AfterRenderingSkybox, builtin: true, run: () => frame.copyColor() },
        { event: RenderPassEvent.BeforeRenderingTransparents + 1, builtin: true, run: () => frame.renderTransparents() },
      ];
      for (const f of S.features) {
        if (!f.active || !f.impl) continue;
        f.impl.addPasses(frame, (event, run) => { if (event < RenderPassEvent.BeforeRenderingPostProcessing) passes.push({ event, run }); });
      }
      passes.forEach((p, i) => (p.order = i));
      passes.sort((a, b) => a.event - b.event || (a.builtin === b.builtin ? a.order - b.order : a.builtin ? -1 : 1));
      frame.beginCamera();
      for (const p of passes) p.run(frame);
      const tex = frame.cameraColorTexture();
      // RT 的过滤方式（MsaaView 缩小渲染时用点采样放大）
      gl.bindTexture(gl.TEXTURE_2D, tex.tex);
      const f = m.filter === 'Point' ? gl.NEAREST : gl.LINEAR;
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, f);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
      // 场景里引用这张 RT 的材质贴图换成渲染结果
      for (const mat of S.materials.values()) {
        for (const [k, v] of mat.props) if (v && v.texture === this.key && v.glTexture !== tex) mat.props.set(k, { ...v, glTexture: tex });
      }
    } finally {
      E.prevViewProj = prevVP;
      S.__rtCameraBusy = false;
    }
  }
}
