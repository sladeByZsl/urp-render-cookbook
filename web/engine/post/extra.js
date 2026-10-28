// 其它 URP 内置后处理效果：景深（Gaussian / Bokeh）、相机运动模糊、Panini 投影。
// 顺序与 URP 14 PostProcessPass.Render 相同：景深 → 运动模糊 → Panini → (Bloom) → Uber。
// （镜头畸变、色差、镜头脏污、暗角、胶片颗粒在 URP 里就是 Uber 的一部分，见 post.js / URP/PostFX.glsl。）
// 每个效果：POST_EFFECTS.push({ order, render(post, frame, src, vol) { ...; return 新贴图 } })
//   order < 100：Bloom 之前；100~199：Bloom 之后、Uber 之前；>= 200：Uber 之后
import { POST_EFFECTS, VOLUME_DEFAULTS } from '../post.js';
import { Material, BUILTIN_SHADERS } from '../shader.js';

const NS = 'UnityEngine.Rendering.Universal.';

// URP 的隐藏后处理着色器 → 本站的 GLSL 移植
Object.assign(BUILTIN_SHADERS, {
  'Hidden/Universal Render Pipeline/GaussianDepthOfField': 'URP/GaussianDepthOfField.glsl',
  'Hidden/Universal Render Pipeline/BokehDepthOfField': 'URP/BokehDepthOfField.glsl',
  'Hidden/Universal Render Pipeline/CameraMotionBlur': 'URP/CameraMotionBlur.glsl',
  'Hidden/Universal Render Pipeline/PaniniProjection': 'URP/PaniniProjection.glsl',
  'Hidden/Universal Render Pipeline/Stop NaN': 'URP/StopNaN.glsl',
});

const mats = {};
export async function init(engine) {
  for (const [k, n] of [['gauss', 'GaussianDepthOfField'], ['bokeh', 'BokehDepthOfField'], ['motion', 'CameraMotionBlur'], ['panini', 'PaniniProjection']])
    mats[k] = new Material(await engine.shaders.get('Hidden/Universal Render Pipeline/' + n));
  mats.stopNaN = new Material(await engine.shaders.get('Hidden/Universal Render Pipeline/Stop NaN'));
}

const param = (vol, t) => vol[NS + t] || VOLUME_DEFAULTS[NS + t];
const sourceSize = (W, H) => [W, H, 1 / W, 1 / H];

// ---------------- Stop NaN（相机的 Stop NaNs 选项，URP 里是后处理的第一步）----------------
POST_EFFECTS.push({
  order: 0,
  render(post, frame, src) {
    const P = frame.scene.panel, cam = P && P.objects[P.mainCamera];
    const add = cam && cam.components.find((c) => c.type.endsWith('AdditionalCameraData'));
    if (!add || !add.data || !add.data.m_StopNaN) return null;
    const dst = frame.getTemporaryRT('_StopNaNTarget', frame.width, frame.height, { color: 'RGBA16F' });
    post.engine.blit(src, dst, mats.stopNaN, 0);
    return dst.texture;
  },
});

// ---------------- 景深 ----------------
POST_EFFECTS.push({
  order: 10,
  render(post, frame, src, vol) {
    const dof = param(vol, 'DepthOfField');
    if (dof.mode === 1) return gaussianDoF(post, frame, src, dof);
    if (dof.mode === 2) return bokehDoF(post, frame, src, dof);
    return null;
  },
});

function gaussianDoF(post, frame, src, dof) {
  const E = post.engine, m = mats.gauss, W = frame.width, H = frame.height;
  const wh = Math.floor(W / 2), hh = Math.floor(H / 2);
  const farStart = dof.gaussianStart, farEnd = Math.max(farStart, dof.gaussianEnd);
  const maxRadius = Math.min(dof.gaussianMaxRadius * (wh / 1080), 2);
  const u = {
    _SourceSize: sourceSize(W, H), _DownSampleScaleFactor: [0.5, 0.5, 2, 2], _CoCParams: [farStart, farEnd, maxRadius, 0],
    _HighQualitySampling: dof.highQualitySampling ? 1 : 0, _CameraDepthTexture: frame.cameraDepthTexture(),
  };
  const fullCoC = frame.getTemporaryRT('_FullCoCTexture', W, H, { color: 'R16F' });
  const halfCoC = frame.getTemporaryRT('_HalfCoCTexture', wh, hh, { color: 'R16F' });
  const ping = frame.getTemporaryRT('_PingTexture', wh, hh, { color: 'RGBA16F' });
  const pong = frame.getTemporaryRT('_PongTexture', wh, hh, { color: 'RGBA16F' });
  const dst = frame.getTemporaryRT('_DofDestination', W, H, { color: 'RGBA16F' });
  E.blit(src, fullCoC, m, 'Gaussian Depth Of Field CoC', u);
  u._FullCoCTexture = fullCoC.texture;
  E.blit(src, halfCoC, m, 'Gaussian Depth Of Field Prefilter CoC', u);
  E.blit(src, ping, m, 'Gaussian Depth Of Field Prefilter Color', u);
  u._HalfCoCTexture = halfCoC.texture;
  E.blit(ping.texture, pong, m, 'Gaussian Depth Of Field Blur Horizontal', u);
  E.blit(pong.texture, ping, m, 'Gaussian Depth Of Field Blur Vertical', u);
  u._ColorTexture = ping.texture;
  E.blit(src, dst, m, 'Gaussian Depth Of Field Composite', u);
  return dst.texture;
}

// PostProcessPass.PrepareBokehKernel：3 圈共 42 个采样点，按叶片数做成多边形
function bokehKernel(dof, maxRadius, rcpAspect) {
  const kRings = 4, kPointsPerRing = 7, out = new Float32Array(42 * 4);
  const bladeCount = dof.bladeCount, curvature = 1 - dof.bladeCurvature, rotation = dof.bladeRotation * Math.PI / 180;
  let idx = 0;
  for (let ring = 1; ring < kRings; ring++) {
    const bias = 1 / kPointsPerRing;
    const radius = (ring + bias) / (kRings - 1 + bias);
    const points = ring * kPointsPerRing;
    for (let point = 0; point < points; point++) {
      const phi = 2 * Math.PI * point / points;
      const nt = Math.cos(Math.PI / bladeCount);
      const dt = Math.cos(phi - (2 * Math.PI / bladeCount) * Math.floor((bladeCount * phi + Math.PI) / (2 * Math.PI)));
      const r = radius * Math.pow(nt / dt, curvature);
      const uR = r * Math.cos(phi - rotation) * maxRadius, vR = r * Math.sin(phi - rotation) * maxRadius;
      out.set([uR, vR, Math.sqrt(uR * uR + vR * vR), uR * rcpAspect], idx * 4);
      idx++;
    }
  }
  return out;
}

function bokehDoF(post, frame, src, dof) {
  const E = post.engine, m = mats.bokeh, W = frame.width, H = frame.height;
  const wh = Math.floor(W / 2), hh = Math.floor(H / 2);
  const F = dof.focalLength / 1000, A = dof.focalLength / dof.aperture, P = dof.focusDistance;
  const maxCoC = (A * F) / (P - F);
  const maxRadius = Math.min(0.05, 14 / H);
  const rcpAspect = 1 / (wh / hh);
  const uvMargin = (1 / H) * 2;
  const u = {
    _SourceSize: sourceSize(W, H), _DownSampleScaleFactor: [0.5, 0.5, 2, 2], _CoCParams: [P, maxCoC, maxRadius, rcpAspect],
    _BokehKernel: bokehKernel(dof, maxRadius, rcpAspect), _BokehConstants: [uvMargin, uvMargin * 2, 0, 0], _CameraDepthTexture: frame.cameraDepthTexture(),
  };
  const fullCoC = frame.getTemporaryRT('_FullCoCTexture', W, H, { color: 'R8' });
  const ping = frame.getTemporaryRT('_PingTexture', wh, hh, { color: 'RGBA16F' });
  const pong = frame.getTemporaryRT('_PongTexture', wh, hh, { color: 'RGBA16F' });
  const dst = frame.getTemporaryRT('_DofDestination', W, H, { color: 'RGBA16F' });
  E.blit(src, fullCoC, m, 'Bokeh Depth Of Field CoC', u);
  u._FullCoCTexture = fullCoC.texture;
  E.blit(src, ping, m, 'Bokeh Depth Of Field Prefilter', u);
  E.blit(ping.texture, pong, m, 'Bokeh Depth Of Field Blur', u);
  E.blit(pong.texture, ping, m, 'Bokeh Depth Of Field Post Blur', u);
  u._DofTexture = ping.texture;
  E.blit(src, dst, m, 'Bokeh Depth Of Field Composite', u);
  return dst.texture;
}

// ---------------- 相机运动模糊 ----------------
// 在 Unity 编辑模式下 URP 不执行运动模糊（Application.isPlaying），网页相当于运行模式：相机静止时速度为 0，画面不变；拖动视角时才会模糊。
export function cameraMotionBlur(engine, frame, src, { viewProj, prevViewProj, intensity, clamp, quality, depth }) {
  const W = frame.width, H = frame.height;
  const dst = frame.getTemporaryRT('_MotionBlurTemp', W, H, { color: 'RGBA16F' });
  engine.blit(src, dst, mats.motion, Math.max(0, Math.min(2, quality | 0)), {
    _ViewProjM: viewProj, _PrevViewProjM: prevViewProj, _Intensity: intensity, _Clamp: clamp,
    _SourceSize: sourceSize(W, H), _CameraDepthTexture: depth || frame.cameraDepthTexture(),
  });
  return dst;
}

POST_EFFECTS.push({
  order: 20,
  render(post, frame, src, vol) {
    const mb = param(vol, 'MotionBlur');
    if (!(mb.intensity > 0)) return null;
    const prev = post.engine.globals.get('unity_PrevMatrixVP') || frame.viewProj;
    return cameraMotionBlur(post.engine, frame, src, { viewProj: frame.viewProj, prevViewProj: prev, intensity: mb.intensity, clamp: mb.clamp, quality: mb.quality }).texture;
  },
});

// ---------------- Panini 投影 ----------------
POST_EFFECTS.push({
  order: 30,
  render(post, frame, src, vol) {
    const p = param(vol, 'PaniniProjection');
    if (!(p.distance > 0)) return null;
    const W = frame.width, H = frame.height, cam = frame.camera;
    const viewExt = (() => { const y = Math.tan(0.5 * cam.fov * Math.PI / 180); return [W / H * y, y]; })();
    // CalcCropExtents
    const d = p.distance, viewDist = 1 + d;
    const projHyp = Math.sqrt(viewExt[0] * viewExt[0] + 1);
    const cylDistMinusD = 1 / projHyp, cylDist = cylDistMinusD + d;
    const crop = viewExt.map((x) => x * cylDistMinusD * (viewDist / cylDist));
    const scaleF = Math.min(crop[0] / viewExt[0], crop[1] / viewExt[1]);
    const paniniS = 1 + (Math.min(1, Math.max(0, scaleF)) - 1) * p.cropToFit;
    const dst = frame.getTemporaryRT('_PaniniTemp', W, H, { color: 'RGBA16F' });
    post.engine.blit(src, dst, mats.panini, 0, { _Params: [viewExt[0], viewExt[1], d, paniniS] });
    return dst.texture;
  },
});
