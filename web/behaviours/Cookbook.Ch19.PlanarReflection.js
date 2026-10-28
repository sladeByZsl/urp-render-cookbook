// 案例 19.9：平面反射（JS 版，对应 Ch19/PlanarReflection.cs）。
// 用一台“镜像相机”从水面下方往上看，把画面渲染进一张 RenderTexture，
// 再设成全局纹理 _PlanarReflectionTex，水面 Shader 用屏幕 UV 采样它。
//
// C# 版用 RenderPipeline.SubmitRenderRequest 让 URP 为反射相机完整渲染一次；
// 网页版在 update() 里（主相机渲染之前）用引擎的 Frame 为镜像相机画一遍：不透明 → 天空盒 → 半透明。
// 和 C# 版一样：不画阴影、不做后处理、不生成深度/不透明贴图。
import { Frame } from '../engine/pipeline.js';
import { mat4, vec3 } from '../engine/math.js';
import { layerMask } from '../engine/features.js';

export default class PlanarReflection {
  constructor(engine, json, obj, scene) {
    this.engine = engine;
    this.obj = obj;            // 水面物体
    this.scene = scene;
    const d = json.data || {};
    this.enabled = json.enabled !== false && d.m_Enabled !== false;
    this.reflectLayers = layerMask(d.reflectLayers ?? ~(1 << 4));   // 4 = 内置的 Water 层
    this.resolutionScale = d.resolutionScale ?? 0.5;
    this.clipPlaneOffset = d.clipPlaneOffset ?? 0.05;
    this.renderShadows = !!d.renderShadows;
    this.rendering = false;   // 防止重入
  }

  // C# 版的 LateUpdate / 拍图时的 RenderFor(Camera.main)：每帧在主相机渲染之前调用
  update(time, dt) {
    if (!this.enabled || !this.obj.active || !this.scene.camera) return;
    this.renderFor(this.scene.camera, time, dt);
  }

  //#region render
  renderFor(cam, time, dt) {
    if (this.rendering) return;
    this.rendering = true;
    const E = this.engine, gl = E.gl;
    const W = E.canvas.width, H = E.canvas.height;
    const w = Math.max(1, (W * this.resolutionScale) | 0), h = Math.max(1, (H * this.resolutionScale) | 0);
    // 反射 RT：主相机允许 HDR 就用浮点格式（C# 版的 DefaultHDR），自带深度，不开 MSAA
    const rt = E.rt('planarReflection', w, h, { color: cam.allowHDR ? 'RGBA16F' : 'SRGB8_ALPHA8', depth: 'DEPTH24_STENCIL8', samples: 1 });

    const reflCam = this.setupReflectionCamera(cam);
    // 用一个“只换了相机”的场景视图建 Frame：灯光、材质、物体都和主相机共用
    const view = Object.create(this.scene);
    view.camera = reflCam;
    const prevVP = E.prevViewProj;
    const frame = new Frame(E, view, w, h, time, dt);
    frame.requireDepth = false;    // requiresDepthOption = Off
    frame.requireOpaque = false;   // requiresColorOption = Off
    frame.setupCamera();
    frame.setupLights();
    frame.setupEnvironment();
    frame.renderShadows();         // reflCam.renderShadows = false 时只是把阴影关掉

    // 清屏（和主相机的清屏方式一致）
    frame.cameraTarget = rt;
    E.bindTarget(rt);
    gl.depthMask(true); gl.colorMask(true, true, true, true); gl.stencilMask(255);
    const bg = reflCam.clearFlags === 'SolidColor' ? reflCam.background : [0, 0, 0, 0];
    gl.clearColor(bg[0], bg[1], bg[2], bg[3]); gl.clearDepth(1); gl.clearStencil(0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

    // 镜像矩阵把左手系变成右手系，三角形绕序反了：临时反转剔除（C# 版的 GL.invertCulling = true），
    // 否则只看得到物体的背面。引擎按物体的 flip 标志决定正面绕序，这里把它们临时取反
    const rs = this.scene.renderers;
    rs.forEach((o) => (o.flip = !o.flip));
    try {
      frame.renderOpaques();
      frame.renderSkybox();
      frame.renderTransparents();
    } finally {
      rs.forEach((o) => (o.flip = !o.flip));
    }

    E.prevViewProj = prevVP;
    E.setGlobal('_PlanarReflectionTex', rt.texture);
    this.rendering = false;
  }
  //#endregion

  //#region mirror
  setupReflectionCamera(cam) {
    // 平面：法线 = 水面物体的 up，经过物体原点
    const m = this.obj.matrix;
    const normal = vec3.normalize([m[4], m[5], m[6]]);
    const pos = [m[12], m[13], m[14]];
    const plane = [normal[0], normal[1], normal[2], -vec3.dot(normal, pos)];
    const reflection = reflectionMatrix(plane);

    // 视图矩阵 = 主相机视图 × 镜像：相机位置、_WorldSpaceCameraPos 都随之镜像
    const view = mat4.mul(cam.view, reflection);

    // 斜裁剪（Oblique）投影：把近裁剪面换成水面，水面以下的东西不进反射
    const clipPlane = cameraSpacePlane(view, vec3.sub(pos, vec3.scale(normal, this.clipPlaneOffset)), normal);
    const proj = calculateObliqueMatrix(cam.projection(), clipPlane);

    return {
      json: cam.json, view, projection: () => proj,
      fov: cam.fov, aspect: cam.aspect, near: cam.near, far: cam.far,
      orthographic: cam.orthographic, orthoSize: cam.orthoSize,
      clearFlags: cam.clearFlags, background: cam.background,
      cullingMask: this.reflectLayers,
      allowHDR: cam.allowHDR, allowMSAA: false,
      renderShadows: this.renderShadows, postProcessing: false, antialiasing: 0,
    };
  }
  //#endregion
}

// 关于平面 (n, d) 的镜像矩阵：p' = p - 2 (n·p + d) n（列主序，下标 m[列*4+行]）
function reflectionMatrix(p) {
  const [x, y, z, w] = p;
  return new Float32Array([
    1 - 2 * x * x, -2 * y * x, -2 * z * x, 0,
    -2 * x * y, 1 - 2 * y * y, -2 * z * y, 0,
    -2 * x * z, -2 * y * z, 1 - 2 * z * z, 0,
    -2 * w * x, -2 * w * y, -2 * w * z, 1,
  ]);
}

// 把世界空间的平面变换到观察空间（斜裁剪需要观察空间平面）
function cameraSpacePlane(worldToCamera, pos, normal) {
  const cpos = mat4.transformPoint(worldToCamera, pos);
  const cn = vec3.normalize(mat4.transformDir(worldToCamera, normal));
  return [cn[0], cn[1], cn[2], -vec3.dot(cpos, cn)];
}

// Unity 的 Camera.CalculateObliqueMatrix（Lengyel 的斜裁剪近平面）：替换投影矩阵第 3 行
function calculateObliqueMatrix(projection, c) {
  const P = new Float32Array(projection);
  const g = (r, col) => P[col * 4 + r];
  const sgn = (v) => (v > 0 ? 1 : v < 0 ? -1 : 0);
  const q = [(sgn(c[0]) + g(0, 2)) / g(0, 0), (sgn(c[1]) + g(1, 2)) / g(1, 1), -1, (1 + g(2, 2)) / g(2, 3)];
  const s = 2 / (c[0] * q[0] + c[1] * q[1] + c[2] * q[2] + c[3] * q[3]);
  P[0 * 4 + 2] = c[0] * s;
  P[1 * 4 + 2] = c[1] * s;
  P[2 * 4 + 2] = c[2] * s + 1;
  P[3 * 4 + 2] = c[3] * s;
  return P;
}
