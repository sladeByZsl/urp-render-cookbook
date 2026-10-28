// 第 26 章配图：每张图 = 场景 + s.Feature<自定义 Feature>() + s.Post().Add<自定义 Volume 组件>()。
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    static class Ch26Shots
    {
        static Material Emissive(Shot s, Color c, float intensity)
        {
            var m = s.Lit(c * 0.2f, 0f, 0.5f);
            m.EnableKeyword("_EMISSION");
            m.SetColor("_EmissionColor", c * intensity);
            return m;
        }

        // 通用场景：彩色物体 + 几个 HDR 自发光物体（给 Bloom 用）
        static void Stage(Shot s, float glow = 2.5f)
        {
            s.Floor();
            s.Knot(s.Lit(new Color(0.95f, 0.45f, 0.12f), 0f, 0.6f), new Vector3(0, 0.95f, 0.4f), 1.0f);
            s.Sphere(s.Lit(new Color(0.85f, 0.12f, 0.12f), 0f, 0.75f), new Vector3(-1.55f, 0.45f, -0.3f), 0.9f);
            var cube = s.Cube(s.Lit(new Color(0.15f, 0.35f, 0.9f), 0f, 0.4f), new Vector3(1.55f, 0.4f, -0.1f), 0.8f);
            cube.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Sphere(s.Lit(new Color(0.9f, 0.9f, 0.92f), 1f, 0.85f), new Vector3(0.7f, 0.3f, -1.0f), 0.6f);
            s.Capsule(s.Lit(new Color(0.2f, 0.75f, 0.35f), 0f, 0.5f), new Vector3(-0.6f, 0.5f, 1.8f), 1.0f);
            // 自发光：三颗小灯球 + 一根霓虹灯条
            s.Sphere(Emissive(s, new Color(0.05f, 0.55f, 1f), glow), new Vector3(-0.55f, 0.18f, -1.3f), 0.36f);
            s.Sphere(Emissive(s, new Color(1f, 0.1f, 0.6f), glow), new Vector3(2.3f, 0.2f, -0.9f), 0.4f);
            s.Sphere(Emissive(s, new Color(1f, 0.7f, 0.1f), glow), new Vector3(-2.4f, 1.3f, 1.2f), 0.35f);
            var bar = s.Cube(Emissive(s, new Color(1f, 0.3f, 0.05f), glow), new Vector3(0.9f, 2.05f, 2.4f), 1f);
            bar.transform.localScale = new Vector3(2.6f, 0.08f, 0.08f);
            s.LookAt(new Vector3(0, 1.75f, -5.3f), new Vector3(0, 0.65f, 0.2f), 38);
        }

        static Volume GlobalVolume() => Object.FindObjectOfType<Volume>();

        //#region shot-saturation
        [BookShot("ch26-saturation", W = 640, H = 400, Panels = 3)]
        static void Saturation(Shot s)
        {
            Stage(s);
            s.Feature<SaturationFeature>();
            var v = s.Post().Add<SaturationVolume>();
            if (s.Panel == 1) v.saturation.Override(0f);
            if (s.Panel == 2) { v.saturation.Override(1.6f); v.contrast.Override(1.25f); }
        }
        //#endregion

        [BookShot("ch26-volume-weight", W = 640, H = 400, Panels = 3)]
        static void VolumeWeight(Shot s)
        {
            Stage(s);
            s.Feature<SaturationFeature>();
            var v = s.Post().Add<SaturationVolume>();
            v.saturation.Override(0f);
            GlobalVolume().weight = new[] { 0.25f, 0.5f, 1f }[s.Panel];
        }

        [BookShot("ch26-gaussian", W = 640, H = 400, Panels = 3)]
        static void Gaussian(Shot s)
        {
            Stage(s);
            s.Feature<GaussianBlurFeature>();
            var v = s.Post().Add<GaussianBlurVolume>();
            if (s.Panel == 1) { v.spread.Override(1f); v.iterations.Override(1); v.downsample.Override(1); }
            if (s.Panel == 2) { v.spread.Override(1.5f); v.iterations.Override(3); v.downsample.Override(4); }
        }

        [BookShot("ch26-kawase", W = 640, H = 400, Panels = 3)]
        static void Kawase(Shot s)
        {
            Stage(s);
            s.Feature<KawaseBlurFeature>();
            var v = s.Post().Add<KawaseBlurVolume>();
            switch (s.Panel)
            {
                case 0: v.mode.Override(KawaseMode.Kawase); v.iterations.Override(5); break;
                case 1: v.mode.Override(KawaseMode.DualKawase); v.iterations.Override(3); break;
                default: v.mode.Override(KawaseMode.DualKawase); v.iterations.Override(5); break;
            }
        }

        //#region shot-bloom
        [BookShot("ch26-bloom", W = 480, H = 320, Panels = 4, Hdr = true)]   // Hdr：浮点相机目标，亮度可远大于 1
        static void BloomShot(Shot s)
        {
            Stage(s, glow: 10f);                             // 自发光强度 10：远超阈值
            s.Background(new Color(0.02f, 0.025f, 0.04f));   // 暗背景更能看出泛光
            s.SunDir(50, -30, 0.8f);
            var prof = s.Post();
            // 四格都加同样的 ACES 色调映射（URP 自带），只有 Bloom 不同
            prof.Add<Tonemapping>().mode.Override(TonemappingMode.ACES);
            if (s.Panel == 0) return;

            s.Feature<MyBloomFeature>();
            var v = prof.Add<MyBloomVolume>();
            v.threshold.Override(1f);
            v.softKnee.Override(0.5f);
            v.intensity.Override(1f);
            v.scatter.Override(0.7f);
            v.debugView.Override(s.Panel == 1 ? BloomDebugView.Prefilter
                               : s.Panel == 2 ? BloomDebugView.BloomOnly : BloomDebugView.None);
        }
        //#endregion

        // 与 URP 自带 Bloom 对照（同样的阈值与强度）
        [BookShot("ch26-bloom-compare", W = 640, H = 400, Panels = 2, Hdr = true)]
        static void BloomCompare(Shot s)
        {
            Stage(s, glow: 10f);
            s.Background(new Color(0.02f, 0.025f, 0.04f));
            s.SunDir(50, -30, 0.8f);
            var prof = s.Post();
            prof.Add<Tonemapping>().mode.Override(TonemappingMode.ACES);
            if (s.Panel == 0)
            {
                s.Feature<MyBloomFeature>();
                var v = prof.Add<MyBloomVolume>();
                v.threshold.Override(1f); v.softKnee.Override(0.5f); v.intensity.Override(1f); v.scatter.Override(0.7f);
            }
            else
            {
                // URP 的 threshold 按 Gamma 空间理解（内部 GammaToLinear），1 在两种空间里相同；
                // scatter 内部被重映射到 0.05~0.95，0.72 ≈ 我们的 0.7
                var b = prof.Add<Bloom>();
                b.threshold.Override(1f); b.intensity.Override(1f); b.scatter.Override(0.72f);
            }
        }

        [BookShot("ch26-radial", W = 640, H = 400, Panels = 2)]
        static void Radial(Shot s)
        {
            Stage(s);
            s.Feature<RadialBlurFeature>();
            var v = s.Post().Add<RadialBlurVolume>();
            if (s.Panel == 1) { v.strength.Override(0.6f); v.samples.Override(16); v.center.Override(new Vector2(0.5f, 0.55f)); }
        }

        //#region shot-lens
        [BookShot("ch26-lens", W = 640, H = 400, Panels = 3)]
        static void Lens(Shot s)
        {
            Stage(s);
            // 两个 Feature 都在 BeforeRenderingPostProcessing：入队顺序 = Renderer 列表顺序
            s.Feature<MyChromaticAberrationFeature>();
            s.Feature<MyVignetteFeature>();
            var prof = s.Post();
            var ca = prof.Add<MyChromaticAberration>();
            var vg = prof.Add<MyVignette>();
            if (s.Panel != 1) ca.intensity.Override(1f);
            if (s.Panel != 0) { vg.intensity.Override(0.6f); vg.smoothness.Override(0.7f); vg.rounded.Override(true); }
            if (s.Panel == 2) vg.color.Override(new Color(0.12f, 0.02f, 0.05f));
        }
        //#endregion

        [BookShot("ch26-pixelate", W = 640, H = 400, Panels = 3)]
        static void Pixelate(Shot s)
        {
            Stage(s);
            s.Feature<PixelateFeature>();
            var v = s.Post().Add<PixelateVolume>();
            v.pixelSize.Override(5);
            if (s.Panel == 1) { v.colorLevels.Override(6); v.dither.Override(0f); }
            if (s.Panel == 2) { v.colorLevels.Override(6); v.dither.Override(1f); }
        }

        [BookShot("ch26-crt", W = 640, H = 400, Panels = 2)]
        static void Crt(Shot s)
        {
            Stage(s);
            s.Feature<CrtFeature>();
            var v = s.Post().Add<CrtVolume>();
            if (s.Panel == 1) { v.intensity.Override(1f); v.curvature.Override(0.18f); v.lineCount.Override(160f); }
        }

        //#region shot-edge
        [BookShot("ch26-edge", W = 640, H = 400, Panels = 3)]
        static void Edge(Shot s)
        {
            Stage(s);
            s.Feature<EdgeDetectFeature>();
            var v = s.Post().Add<EdgeDetectVolume>();
            v.intensity.Override(1f);
            v.thickness.Override(1f);
            switch (s.Panel)
            {
                case 0: v.edgesOnly.Override(1f); v.normalThreshold.Override(4f); break;   // 只用深度
                case 1: v.edgesOnly.Override(1f); break;                                     // 深度 + 法线
                default: v.edgesOnly.Override(0f); break;                                    // 叠在原图上
            }
        }
        //#endregion

        [BookShot("ch26-hitflash", W = 640, H = 400, Panels = 3)]
        static void HitFlash(Shot s)
        {
            Stage(s);
            s.Feature<HitFlashFeature>();
            var v = s.Post().Add<HitFlashVolume>();
            v.intensity.Override(new[] { 0.3f, 0.65f, 1f }[s.Panel]);
            v.phase.Override(1.7f);
        }
    }
}
