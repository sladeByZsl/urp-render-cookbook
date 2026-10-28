// URP 14 自带的 SSAO Renderer Feature（ScreenSpaceAmbientOcclusion.cs）的网页版。
// 前向路径、AfterOpaque 关闭时：在不透明物体之前（AfterRenderingPrePasses + 1）算好 _ScreenSpaceOcclusionTexture，
// 再设置 _AmbientOcclusionParam = (1, 0, 0, 直接光 AO 强度)，Lit 等着色器的 UniversalFragmentPBR 会自动用上。
// Source = DepthNormals 时先跑一遍 DepthNormals 预渲染得到 _CameraNormalsTexture（和 URP 一样，深度也取自这次预渲染）。
import { Material, BUILTIN_SHADERS } from '../engine/shader.js';
import { RenderPassEvent } from '../engine/features.js';
import { mat4 } from '../engine/math.js';

BUILTIN_SHADERS['Hidden/Universal Render Pipeline/ScreenSpaceAmbientOcclusion'] = 'URP/ScreenSpaceAmbientOcclusion.glsl';

// ScreenSpaceAmbientOcclusionSettings 的默认值
const DEFAULTS = { AOMethod: 0, Downsample: false, AfterOpaque: false, Source: 1, NormalSamples: 1, Intensity: 3, DirectLightingStrength: 0.25, Radius: 0.035, Samples: 1, BlurQuality: 0, Falloff: 100, SampleCount: -1 };
const BLUE_NOISE = [0, 1, 2, 3, 4, 5, 6].map((i) => `LDR_LLL1_${i}.png`);

// ShaderPasses 枚举
const P = { AmbientOcclusion: 0, BilateralBlurHorizontal: 1, BilateralBlurVertical: 2, BilateralBlurFinal: 3, BilateralAfterOpaque: 4, GaussianBlurHorizontal: 5, GaussianBlurVertical: 6, GaussianAfterOpaque: 7, KawaseBlur: 8, KawaseAfterOpaque: 9 };
const FINAL = 3;

export default class ScreenSpaceAmbientOcclusion {
  constructor(engine, data, scene) {
    this.engine = engine;
    this.scene = scene;
    const s = { ...DEFAULTS, ...((data && data.m_Settings) || {}) };
    // Create()：旧版的 SampleCount 字段换算成新设置
    if (s.SampleCount > 0) { s.AOMethod = 1; s.Samples = s.SampleCount > 11 ? 0 : s.SampleCount > 8 ? 1 : 2; s.SampleCount = -1; }
    this.s = s;
    this.noiseIndex = 0;
  }

  async init() {
    this.material = new Material(await this.engine.shaders.get('Hidden/Universal Render Pipeline/ScreenSpaceAmbientOcclusion'));
    this.noise = (await Promise.all(BLUE_NOISE.map((k) => this.engine.assets.texture(k).catch(() => null)))).filter(Boolean);
  }

  addPasses(frame, enqueue) {
    const s = this.s;
    if (!(s.Intensity > 0 && s.Radius > 0 && s.Falloff > 0)) return;
    enqueue(s.AfterOpaque ? RenderPassEvent.AfterRenderingOpaques : RenderPassEvent.AfterRenderingPrePasses + 1, (fr) => this.execute(fr), 'SSAO');
  }

  // DepthNormals 预渲染：_CameraNormalsTexture（世界空间法线）+ 无 MSAA 的深度
  renderDepthNormals(fr) {
    const gl = fr.gl;
    const rt = fr.getTemporaryRT('_SSAODepthNormals', fr.width, fr.height, { color: 'RGBA16F', depth: 'DEPTH24' });
    fr.engine.bindTarget(rt);
    gl.colorMask(true, true, true, true); gl.depthMask(true);
    gl.clearColor(0, 0, 0, 0); gl.clearDepth(1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    fr.drawRenderers({ queue: 'opaque', lightModes: ['DepthNormals', 'DepthNormalsOnly'], layerMask: fr.scene.rendererData.m_OpaqueLayerMask ?? -1 });
    fr.setGlobal('_CameraNormalsTexture', rt.texture);
    return rt;
  }

  execute(fr) {
    const E = this.engine, s = this.s, m = this.material, W = fr.width, H = fr.height;
    const div = s.Downsample ? 2 : 1;
    // 深度来源：AfterOpaque 时相机深度已经有了；否则前向路径需要预渲染
    let depthTex;
    if (s.Source === 1 || !s.AfterOpaque) {
      const dn = this.renderDepthNormals(fr);
      depthTex = dn.depthTexture;
    } else depthTex = fr.cameraDepthTexture();
    fr.setGlobal('_CameraDepthTexture', depthTex);

    // OnCameraSetup：近平面四角（相机相对的世界空间）
    const cview = new Float32Array(fr.view); cview[12] = 0; cview[13] = 0; cview[14] = 0;
    const inv = mat4.invert(mat4.mul(fr.proj, cview));
    const tl = mat4.transformPoint(inv, [-1, 1, -1]), tr = mat4.transformPoint(inv, [1, 1, -1]);
    const bl = mat4.transformPoint(inv, [-1, -1, -1]), farC = mat4.transformPoint(inv, [0, 0, 1]);
    const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2], 0];
    const u = {
      _ProjectionParams2: [1 / fr.camera.near, 0, 0, 0],
      _CameraViewProjections: fr.viewProj,
      _CameraViewTopLeftCorner: [tl[0], tl[1], tl[2], 0], _CameraViewXExtent: sub(tr, tl), _CameraViewYExtent: sub(bl, tl), _CameraViewZExtent: [farC[0], farC[1], farC[2], 0],
      _SSAOOrthographic: fr.camera.orthographic ? 1 : 0,
      _SSAOSampleCount: [12, 8, 4][s.Samples] || 4,
      _SSAONormalSource: s.Source === 1 ? 3 : s.NormalSamples,
      _CameraDepthTexture: depthTex,
      _CameraDepthTexture_TexelSize: [1 / depthTex.width, 1 / depthTex.height, depthTex.width, depthTex.height],
    };
    if (s.AOMethod === 0 && this.noise.length) {
      // 蓝噪声：URP 每帧换一张、随机偏移；这里按帧时间取伪随机，保证截图可复现
      const n = Math.floor(fr.time * 60);
      const noise = this.noise[n % this.noise.length];
      const fr2 = (x) => x - Math.floor(x);
      u._SSAOBlueNoise = 1;
      u._BlueNoiseTexture = noise;
      u._SSAOParams = [s.Intensity, s.Radius * 1.5, 1 / div, s.Falloff];
      u._SSAOBlueNoiseParams = [W / noise.width, H / noise.height, fr2(Math.sin(n * 12.9898 + 0.5) * 43758.5453), fr2(Math.sin(n * 78.233 + 0.5) * 43758.5453)];
    } else {
      u._SSAOBlueNoise = 0;
      u._SSAOParams = [s.Intensity, s.Radius, 1 / div, s.Falloff];
    }
    const aw = Math.floor(W / div), ah = Math.floor(H / div);
    // PostProcessUtils.SetSourceSize(m_AOPassDescriptor)：此时描述已恢复成全分辨率
    u._SourceSize = [W, H, 1 / W, 1 / H];

    const tex = [0, 1, 2].map((i) => fr.getTemporaryRT('_SSAO_OcclusionTexture' + i, aw, ah, { color: 'RGBA8' }));
    tex[FINAL] = fr.getTemporaryRT('_SSAO_OcclusionTexture', W, H, { color: 'RGBA8' });
    const blur = s.BlurQuality === 2 ? 'Kawase' : s.BlurQuality === 1 ? 'Gaussian' : 'Bilateral';
    let indices, passes;
    if (blur === 'Bilateral') { indices = [0, 1, 2, FINAL]; passes = [P.BilateralBlurHorizontal, P.BilateralBlurVertical, s.AfterOpaque ? P.BilateralAfterOpaque : P.BilateralBlurFinal]; }
    else if (blur === 'Gaussian') { indices = [0, 1, FINAL, FINAL]; passes = s.AfterOpaque ? [P.GaussianBlurHorizontal, P.GaussianAfterOpaque] : [P.GaussianBlurHorizontal, P.GaussianBlurVertical]; }
    else { indices = [0, FINAL]; passes = [s.AfterOpaque ? P.KawaseAfterOpaque : P.KawaseBlur]; u._LastKawasePass = 1; u._KawaseBlurIteration = 0; }

    E.blit(null, tex[0], m, P.AmbientOcclusion, u);
    passes.forEach((pass, i) => {
      const base = tex[indices[i]].texture;
      const afterOpaque = pass === P.BilateralAfterOpaque || pass === P.GaussianAfterOpaque || pass === P.KawaseAfterOpaque;
      E.blit(base, afterOpaque ? fr.cameraTarget : tex[indices[i + 1]], m, pass, u);
    });
    if (!s.AfterOpaque) {
      fr.setGlobal('_ScreenSpaceOcclusionTexture', tex[FINAL].texture);
      fr.setGlobal('_AmbientOcclusionParam', [1, 0, 0, s.DirectLightingStrength]);
    }
    fr.bindCamera();
  }
}
