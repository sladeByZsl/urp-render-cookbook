using System.Reflection;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch27
{
    static class Shots
    {
        // ======================= 场景 =======================
        static Texture2D s_Grid, s_Dirt;

        static Texture2D GridTex()
        {
            if (s_Grid != null) return s_Grid;
            const int n = 128;
            s_Grid = new Texture2D(n, n, TextureFormat.RGBA32, true) { name = "ch27_grid", wrapMode = TextureWrapMode.Repeat, anisoLevel = 8, hideFlags = HideFlags.DontSave };
            var px = new Color[n * n];
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float v = (x < 3 || y < 3) ? 0.18f : 0.55f;
                    px[y * n + x] = new Color(v, v, v, 1);
                }
            s_Grid.SetPixels(px); s_Grid.Apply(true);
            return s_Grid;
        }

        static Material Emissive(Shot s, Color baseCol, Color emission, float intensity)
        {
            var m = s.Lit(baseCol, 0, 0.5f);
            m.EnableKeyword("_EMISSION");
            // _EmissionColor 是 [HDR] 属性：线性工程里原样上传，这里直接写线性 HDR 值（SetColor 和 SetVector 效果相同）
            m.SetVector("_EmissionColor", (Vector4)(emission * intensity));
            return m;
        }

        static Material UnlitColor(Shot s, Color c)
        {
            var m = s.Mat("Universal Render Pipeline/Unlit");
            m.SetColor("_BaseColor", c);
            return m;
        }

        static GameObject Box(Shot s, Material m, Vector3 pos, Vector3 size, float yaw = 0)
        {
            var go = s.Cube(m, pos);
            go.transform.localScale = size;
            go.transform.rotation = Quaternion.Euler(0, yaw, 0);
            return go;
        }

        // 近似 24 色标准色卡（sRGB 8bit，取常见公开近似值），用 Unlit 显示，颜色变化一目了然
        static readonly int[,] k_Chart =
        {
            {115, 82, 68}, {194,150,130}, { 98,122,157}, { 87,108, 67}, {133,128,177}, {103,189,170},
            {214,126, 44}, { 80, 91,166}, {193, 90, 99}, { 94, 60,108}, {157,188, 64}, {224,163, 46},
            { 56, 61,150}, { 70,148, 73}, {175, 54, 60}, {231,199, 31}, {187, 86,149}, {  8,133,161},
            {243,243,242}, {200,200,200}, {160,160,160}, {122,122,121}, { 85, 85, 85}, { 52, 52, 52},
        };

        static void ColorChart(Shot s, Vector3 center, float yaw, float cell = 0.26f)
        {
            var root = new GameObject("ColorChart");
            root.transform.position = center;
            var board = s.Quad(UnlitColor(s, new Color(0.08f, 0.08f, 0.08f)), Vector3.zero);
            board.transform.SetParent(root.transform, false);
            board.transform.localPosition = new Vector3(0, 0, 0.01f);
            board.transform.localScale = new Vector3(cell * 6 + 0.12f, cell * 4 + 0.12f, 1);
            for (int i = 0; i < 24; i++)
            {
                int r = i / 6, c = i % 6;
                var col = new Color(k_Chart[i, 0] / 255f, k_Chart[i, 1] / 255f, k_Chart[i, 2] / 255f);
                var q = s.Quad(UnlitColor(s, col), Vector3.zero);
                q.transform.SetParent(root.transform, false);
                q.transform.localPosition = new Vector3((c - 2.5f) * cell, (1.5f - r) * cell, 0);
                q.transform.localScale = Vector3.one * cell * 0.88f;
            }
            root.transform.rotation = Quaternion.Euler(0, yaw, 0);
        }

        /// 本章的“样板间”：色卡 + 一排彩色球 + 白色高光球 + 自发光霓虹物体
        static void Showroom(Shot s, float sun = 1.8f)
        {
            s.Asset.colorGradingMode = ColorGradingMode.HighDynamicRange;
            var floor = s.Lit(Color.white, 0, 0.25f);
            floor.SetTexture("_BaseMap", GridTex());
            floor.SetTextureScale("_BaseMap", new Vector2(60, 60));
            s.Floor(floor);

            ColorChart(s, new Vector3(-1.45f, 1.05f, 1.6f), -18f);
            Color[] cols = { new Color(0.85f, 0.12f, 0.1f), new Color(0.95f, 0.75f, 0.1f), new Color(0.15f, 0.65f, 0.25f), new Color(0.12f, 0.3f, 0.85f) };
            for (int i = 0; i < cols.Length; i++)
                s.Sphere(s.Lit(cols[i], 0, 0.6f), new Vector3(0.35f + i * 0.62f, 0.27f, 0.1f + i * 0.15f), 0.54f);
            s.Sphere(s.Lit(new Color(0.95f, 0.95f, 0.95f), 0.0f, 0.9f), new Vector3(1.45f, 0.55f, 1.4f), 1.1f);
            // 自发光：橙色圆环 + 青/品红小方块，亮度都远大于 1
            var torus = s.Torus(Emissive(s, Color.black, new Color(1f, 0.28f, 0.04f), 5f), new Vector3(0.15f, 1.25f, 2.3f), 0.45f, 0.06f);
            torus.transform.rotation = Quaternion.Euler(90, 0, 0);
            Box(s, Emissive(s, Color.black, new Color(0.05f, 0.5f, 1f), 6f), new Vector3(-0.35f, 0.08f, -0.3f), new Vector3(0.16f, 0.16f, 0.16f), 30);
            Box(s, Emissive(s, Color.black, new Color(1f, 0.05f, 0.45f), 6f), new Vector3(2.55f, 0.08f, 0.1f), new Vector3(0.16f, 0.16f, 0.16f), 15);
            var neon = s.Cylinder(Emissive(s, Color.black, new Color(0.1f, 1f, 0.25f), 4f), new Vector3(2.5f, 0.9f, 2.0f));
            neon.transform.localScale = new Vector3(0.05f, 0.9f, 0.05f);
            s.SunDir(42, -38, sun);
            s.LookAt(new Vector3(0.45f, 1.55f, -3.9f), new Vector3(0.45f, 0.75f, 1.0f), 46);
        }

        static VolumeProfile Post(Shot s, bool tonemap = true)
        {
            var p = s.Post();
            if (tonemap) p.Add<Tonemapping>().mode.Override(TonemappingMode.ACES);
            return p;
        }

        // ======================= Bloom =======================
        [BookShot("ch27-bloom", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Bloom1(Shot s)
        {
            Showroom(s);
            var p = Post(s);
            if (s.Panel > 0)
            {
                var b = p.Add<Bloom>();
                b.intensity.Override(s.Panel == 1 ? 1f : 2.5f);
                b.threshold.Override(1f);
                b.scatter.Override(s.Panel == 1 ? 0.7f : 0.85f);
                if (s.Panel == 2) { b.tint.Override(new Color(1f, 0.85f, 0.7f)); b.highQualityFiltering.Override(true); }
            }
        }

        [BookShot("ch27-bloom-threshold", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void BloomThreshold(Shot s)
        {
            float[] t = { 0.4f, 1.0f, 2.0f };
            Showroom(s);
            var b = Post(s).Add<Bloom>();
            b.intensity.Override(1.5f);
            b.threshold.Override(t[s.Panel]);
        }

        [BookShot("ch27-bloom-scatter", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void BloomScatter(Shot s)
        {
            float[] sc = { 0.2f, 0.7f, 0.95f };
            Showroom(s);
            var b = Post(s).Add<Bloom>();
            b.intensity.Override(1.5f);
            b.threshold.Override(1f);
            b.scatter.Override(sc[s.Panel]);
        }

        static Texture2D DirtTex()
        {
            if (s_Dirt != null) return s_Dirt;
            // 程序生成一张“镜头脏污”：大量半透明的软圆斑 + 几道擦痕，黑底
            const int w = 512, h = 288;
            s_Dirt = new Texture2D(w, h, TextureFormat.RGBA32, false) { name = "ch27_dirt", hideFlags = HideFlags.DontSave };
            var px = new Color[w * h];
            var rnd = new System.Random(11);
            for (int k = 0; k < 90; k++)
            {
                float cx = (float)rnd.NextDouble() * w, cy = (float)rnd.NextDouble() * h;
                float r = 6 + (float)rnd.NextDouble() * 34, a = 0.15f + (float)rnd.NextDouble() * 0.5f;
                for (int y = Mathf.Max(0, (int)(cy - r)); y < Mathf.Min(h, (int)(cy + r)); y++)
                    for (int x = Mathf.Max(0, (int)(cx - r)); x < Mathf.Min(w, (int)(cx + r)); x++)
                    {
                        float d = Mathf.Sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / r;
                        if (d < 1) px[y * w + x] += Color.white * a * (1 - d * d) * (0.6f + 0.4f * d);  // 边缘略亮，像水渍
                    }
            }
            for (int k = 0; k < 6; k++)
            {
                float x0 = (float)rnd.NextDouble() * w, y0 = (float)rnd.NextDouble() * h, ang = (float)rnd.NextDouble() * Mathf.PI;
                for (int t = 0; t < 220; t++)
                {
                    int x = (int)(x0 + Mathf.Cos(ang) * t), y = (int)(y0 + Mathf.Sin(ang) * t);
                    for (int o = -2; o <= 2; o++)
                        if (x >= 0 && x < w && y + o >= 0 && y + o < h) px[(y + o) * w + x] += Color.white * 0.12f;
                }
            }
            for (int i = 0; i < px.Length; i++) { var c = px[i]; c.a = 1; px[i] = new Color(Mathf.Min(c.r, 1), Mathf.Min(c.g, 1), Mathf.Min(c.b, 1), 1); }
            s_Dirt.SetPixels(px); s_Dirt.Apply();
            return s_Dirt;
        }

        [BookShot("ch27-bloom-dirt", W = 640, H = 420, Panels = 2, Hdr = true)]
        static void BloomDirt(Shot s)
        {
            Showroom(s, 2.4f);
            var b = Post(s).Add<Bloom>();
            b.intensity.Override(2f);
            b.threshold.Override(0.9f);
            b.scatter.Override(0.8f);
            if (s.Panel == 1) { b.dirtTexture.Override(DirtTex()); b.dirtIntensity.Override(3f); }
        }

        // ======================= Tonemapping =======================
        [BookShot("ch27-tonemap", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Tonemap(Shot s)
        {
            Showroom(s, 3.2f);   // 故意把太阳调得很亮，制造大量 >1 的像素
            var p = s.Post();
            var tm = p.Add<Tonemapping>();
            tm.mode.Override(s.Panel == 0 ? TonemappingMode.None : s.Panel == 1 ? TonemappingMode.Neutral : TonemappingMode.ACES);
            var b = p.Add<Bloom>(); b.intensity.Override(0.6f); b.threshold.Override(1.2f);
        }

        // ======================= Color Adjustments =======================
        [BookShot("ch27-coloradj", W = 480, H = 330, Panels = 4, Hdr = true)]
        static void ColorAdj(Shot s)
        {
            Showroom(s);
            var ca = Post(s).Add<ColorAdjustments>();
            switch (s.Panel)
            {
                case 1: ca.postExposure.Override(1f); break;
                case 2: ca.contrast.Override(60f); break;
                case 3: ca.contrast.Override(-60f); break;
            }
        }

        [BookShot("ch27-huesat", W = 480, H = 330, Panels = 4, Hdr = true)]
        static void HueSat(Shot s)
        {
            Showroom(s);
            var ca = Post(s).Add<ColorAdjustments>();
            switch (s.Panel)
            {
                case 0: ca.saturation.Override(-100f); break;
                case 1: ca.saturation.Override(60f); break;
                case 2: ca.hueShift.Override(120f); break;
                case 3: ca.colorFilter.Override(new Color(1f, 0.88f, 0.72f)); break;
            }
        }

        // ======================= White Balance =======================
        [BookShot("ch27-whitebalance", W = 480, H = 330, Panels = 4, Hdr = true)]
        static void WhiteBalanceShot(Shot s)
        {
            Showroom(s);
            var wb = Post(s).Add<WhiteBalance>();
            switch (s.Panel)
            {
                case 0: wb.temperature.Override(-60f); break;
                case 1: wb.temperature.Override(60f); break;
                case 2: wb.tint.Override(-60f); break;
                case 3: wb.tint.Override(60f); break;
            }
        }

        // ======================= Lift Gamma Gain =======================
        [BookShot("ch27-lgg", W = 480, H = 330, Panels = 4, Hdr = true)]
        static void LGG(Shot s)
        {
            Showroom(s);
            var lgg = Post(s).Add<LiftGammaGain>();
            switch (s.Panel)
            {
                case 1: lgg.lift.Override(new Vector4(0.85f, 0.93f, 1.2f, 0.04f)); break;   // 暗部偏蓝并整体抬起
                case 2: lgg.gamma.Override(new Vector4(1f, 1f, 1f, -0.25f)); break;         // 中间调整体压暗
                case 3: lgg.gain.Override(new Vector4(1.15f, 1.03f, 0.88f, 0.08f)); break;    // 亮部偏暖并提亮
            }
        }

        // ======================= Shadows Midtones Highlights =======================
        [BookShot("ch27-smh", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void SMH(Shot s)
        {
            Showroom(s);
            var smh = Post(s).Add<ShadowsMidtonesHighlights>();
            var teal = new Vector4(0.55f, 0.95f, 1.5f, 0f);
            var orange = new Vector4(1.45f, 1.05f, 0.6f, 0f);
            if (s.Panel != 1) smh.shadows.Override(teal);
            if (s.Panel != 0) smh.highlights.Override(orange);
        }

        // ======================= Channel Mixer =======================
        [BookShot("ch27-channelmixer", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Mixer(Shot s)
        {
            Showroom(s);
            var cm = Post(s).Add<ChannelMixer>();
            switch (s.Panel)
            {
                case 0: // 红蓝互换
                    cm.redOutRedIn.Override(0); cm.redOutBlueIn.Override(100);
                    cm.blueOutBlueIn.Override(0); cm.blueOutRedIn.Override(100);
                    break;
                case 1: // 三个输出都取同一组系数 → 黑白，系数决定哪种颜色更亮
                    foreach (var (r, g, b) in new[] { (cm.redOutRedIn, cm.redOutGreenIn, cm.redOutBlueIn), (cm.greenOutRedIn, cm.greenOutGreenIn, cm.greenOutBlueIn), (cm.blueOutRedIn, cm.blueOutGreenIn, cm.blueOutBlueIn) })
                    { r.Override(70); g.Override(20); b.Override(10); }
                    break;
                case 2: // 绿色输出里掺入红色：植被泛黄、红色泛橙
                    cm.greenOutRedIn.Override(45); cm.greenOutGreenIn.Override(70);
                    cm.blueOutBlueIn.Override(120);
                    break;
            }
        }

        // ======================= Color Curves =======================
        [BookShot("ch27-curves", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Curves(Shot s)
        {
            Showroom(s);
            var cc = Post(s).Add<ColorCurves>();
            switch (s.Panel)
            {
                case 0: // Master S 曲线：压暗部、提亮部
                    cc.master.Override(new TextureCurve(new[] { new Keyframe(0f, 0f, 0.6f, 0.6f), new Keyframe(0.25f, 0.15f, 1.13f, 1.13f), new Keyframe(0.75f, 0.85f, 1.13f, 1.13f), new Keyframe(1f, 1f, 0.6f, 0.6f) }, 0f, false, new Vector2(0f, 1f)));
                    break;
                case 1: // Hue vs Sat：只保留红色附近的饱和度（0.5 = 不变，0 = 去色）
                    cc.hueVsSat.Override(new TextureCurve(new[] { new Keyframe(0f, 0.5f), new Keyframe(0.07f, 0f), new Keyframe(0.93f, 0f) }, 0.5f, true, new Vector2(0f, 1f)));
                    break;
                case 2: // Hue vs Hue：把绿色（色相约 0.33）推向青色
                    cc.hueVsHue.Override(new TextureCurve(new[] { new Keyframe(0.2f, 0.5f), new Keyframe(0.33f, 0.62f), new Keyframe(0.46f, 0.5f) }, 0.5f, true, new Vector2(0f, 1f)));
                    break;
            }
        }

        // ======================= Color Lookup =======================
        /// 程序化生成一张 32³ 的 LUT（宽 1024 × 高 32 的横条），内容是一个“暖调褪色胶片”风格。
        /// LUT 的格子里存的是 sRGB 编码的颜色（LDR 查找在 sRGB 空间进行），纹理必须是线性（非 sRGB）格式。
        //#region lut
        static Texture2D MakeLut(int size)
        {
            var t = new Texture2D(size * size, size, TextureFormat.RGBA32, false, true) { name = "ch27_lut", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear, hideFlags = HideFlags.DontSave };
            var px = new Color[size * size * size];
            for (int b = 0; b < size; b++)
                for (int g = 0; g < size; g++)
                    for (int r = 0; r < size; r++)
                    {
                        var c = new Vector3(r, g, b) / (size - 1);            // 输入：sRGB 0..1
                        float l = Vector3.Dot(c, new Vector3(0.299f, 0.587f, 0.114f));
                        c = Vector3.Lerp(new Vector3(l, l, l), c, 0.7f);     // 去掉 30% 饱和度
                        c = new Vector3(c.x * 1.06f + 0.03f, c.y * 0.98f + 0.025f, c.z * 0.85f + 0.06f);  // 暖色 + 抬黑（褪色感）
                        for (int k = 0; k < 3; k++)                            // 轻微 S 曲线
                        {
                            float v = Mathf.Clamp01(c[k]);
                            c[k] = Mathf.Lerp(v, v * v * (3 - 2 * v), 0.35f);
                        }
                        // 横条布局：第 b 个 size×size 小方块对应蓝色 = b，方块内 x = 红、y = 绿
                        px[g * size * size + b * size + r] = new Color(c.x, c.y, c.z, 1);
                    }
            t.SetPixels(px); t.Apply();
            return t;
        }
        //#endregion

        [BookShot("ch27-lut", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Lut(Shot s)
        {
            float[] contrib = { 0f, 0.5f, 1f };
            Showroom(s);
            var cl = Post(s).Add<ColorLookup>();
            cl.texture.Override(MakeLut(s.Asset.colorGradingLutSize));
            cl.contribution.Override(contrib[s.Panel]);
        }

        // ======================= Split Toning =======================
        [BookShot("ch27-splittoning", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Split(Shot s)
        {
            float[] balance = { -50f, 0f, 50f };
            Showroom(s);
            var st = Post(s).Add<SplitToning>();
            st.shadows.Override(new Color(0.25f, 0.45f, 0.75f));
            st.highlights.Override(new Color(0.95f, 0.7f, 0.35f));
            st.balance.Override(balance[s.Panel]);
        }

        // ======================= Vignette =======================
        [BookShot("ch27-vignette", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void VignetteShot(Shot s)
        {
            Showroom(s);
            var v = Post(s).Add<Vignette>();
            v.intensity.Override(0.45f);
            v.smoothness.Override(0.35f);
            if (s.Panel == 1) { v.rounded.Override(true); v.intensity.Override(0.5f); }
            if (s.Panel == 2) { v.color.Override(new Color(0.45f, 0.05f, 0.05f)); v.center.Override(new Vector2(0.38f, 0.55f)); v.intensity.Override(0.55f); v.smoothness.Override(0.5f); }
        }

        // ======================= Chromatic Aberration =======================
        [BookShot("ch27-ca", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void CA(Shot s)
        {
            float[] k = { 0f, 0.5f, 1f };
            Showroom(s);
            var ca = Post(s).Add<ChromaticAberration>();
            ca.intensity.Override(k[s.Panel]);
        }

        // ======================= Film Grain =======================
        [BookShot("ch27-grain", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Grain(Shot s)
        {
            Showroom(s);
            var g = Post(s).Add<FilmGrain>();
            if (s.Panel == 1) { g.type.Override(FilmGrainLookup.Thin1); g.intensity.Override(0.6f); }
            if (s.Panel == 2) { g.type.Override(FilmGrainLookup.Large01); g.intensity.Override(1f); g.response.Override(0.3f); }
        }

        // ======================= Lens Distortion =======================
        [BookShot("ch27-lens", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Lens(Shot s)
        {
            float[] k = { -0.5f, 0f, 0.5f };
            Showroom(s);
            var ld = Post(s).Add<LensDistortion>();
            ld.intensity.Override(k[s.Panel]);
            if (s.Panel == 2) ld.scale.Override(0.85f);   // 枕形会把画面边缘推出屏幕外，适当缩小
        }

        // ======================= Panini Projection =======================
        [BookShot("ch27-panini", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Panini(Shot s)
        {
            float[] d = { 0f, 0.5f, 1f };
            Showroom(s);
            // 超广角：100° 垂直视角
            s.LookAt(new Vector3(0.45f, 1.3f, -1.8f), new Vector3(0.45f, 0.9f, 1.0f), 100);
            var p = Post(s).Add<PaniniProjection>();
            p.distance.Override(d[s.Panel]);
            p.cropToFit.Override(1f);
        }

        // ======================= Depth of Field =======================
        static void DofScene(Shot s)
        {
            s.Asset.colorGradingMode = ColorGradingMode.HighDynamicRange;
            var floor = s.Lit(Color.white, 0, 0.25f);
            floor.SetTexture("_BaseMap", GridTex());
            floor.SetTextureScale("_BaseMap", new Vector2(60, 60));
            s.Floor(floor);
            Color[] cols = { new Color(0.85f, 0.2f, 0.15f), new Color(0.95f, 0.75f, 0.15f), new Color(0.2f, 0.7f, 0.3f), new Color(0.2f, 0.4f, 0.9f), new Color(0.8f, 0.8f, 0.8f) };
            // 一列由近及远的立柱 + 球，距离相机约 1.5 ~ 16 米
            for (int i = 0; i < 9; i++)
            {
                float z = -1.6f + i * i * 0.22f + i * 0.9f;
                var m = s.Lit(cols[i % cols.Length], 0, 0.6f);
                var post = s.Cylinder(m, new Vector3(-0.5f + (i % 2) * 1.0f, 0.6f, z));
                post.transform.localScale = new Vector3(0.35f, 0.6f, 0.35f);
                s.Sphere(m, new Vector3(-0.5f + (i % 2) * 1.0f, 1.45f, z), 0.45f);
            }
            // 远处一排小灯珠：失焦后变成光斑（Bokeh）
            for (int i = 0; i < 14; i++)
            {
                var m = Emissive(s, Color.black, i % 2 == 0 ? new Color(1f, 0.45f, 0.1f) : new Color(0.15f, 0.55f, 1f), 10f);
                s.Sphere(m, new Vector3(-3.5f + i * 0.55f, 1.2f + Mathf.Sin(i * 1.7f) * 0.5f, 22f), 0.12f);
            }
            s.SunDir(35, -40, 1.6f);
            s.LookAt(new Vector3(0.1f, 1.25f, -3.2f), new Vector3(0.0f, 1.0f, 6f), 40);
        }

        [BookShot("ch27-dof-gauss", W = 800, H = 450, Panels = 2, Hdr = true)]
        static void DofGauss(Shot s)
        {
            DofScene(s);
            var dof = Post(s).Add<DepthOfField>();
            dof.mode.Override(s.Panel == 0 ? DepthOfFieldMode.Off : DepthOfFieldMode.Gaussian);
            dof.gaussianStart.Override(2.5f);
            dof.gaussianEnd.Override(8f);
            dof.gaussianMaxRadius.Override(1.5f);
            dof.highQualitySampling.Override(true);
        }

        [BookShot("ch27-dof-bokeh", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void DofBokeh(Shot s)
        {
            float[] focus = { 1.65f, 5f, 20f };
            DofScene(s);
            var dof = Post(s).Add<DepthOfField>();
            dof.mode.Override(DepthOfFieldMode.Bokeh);
            dof.focusDistance.Override(focus[s.Panel]);
            dof.focalLength.Override(85f);
            dof.aperture.Override(1.8f);
            dof.bladeCount.Override(6);
            dof.bladeCurvature.Override(0.3f);
        }

        // ======================= Motion Blur =======================
        [BookShot("ch27-motionblur", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void Motion(Shot s)
        {
            Showroom(s);
            var p = Post(s);
            // Volume 上的 MotionBlur 照常配置（这是项目里真正要做的事）……
            var mb = p.Add<MotionBlur>();
            mb.mode.Override(MotionBlurMode.CameraOnly);
            mb.quality.Override(MotionBlurQuality.High);
            mb.intensity.Override(s.Panel == 0 ? 0f : s.Panel == 1 ? 0.5f : 1f);
            mb.clamp.Override(0.1f);
            // ……但编辑模式下 URP 不执行它，配图改由 MotionBlurPreviewFeature 用相同参数调用同一个 Shader
            var f = s.Feature<MotionBlurPreviewFeature>();
            f.intensity = mb.intensity.value; f.clamp = mb.clamp.value; f.quality = (int)mb.quality.value;
            // 模拟“相机在上一帧绕 Y 轴少转了 2.5°”：算出那时的 GPU VP 矩阵交给 Feature
            var t = s.Cam.transform; var rot = t.rotation;
            t.rotation = Quaternion.AngleAxis(-2.5f, Vector3.up) * rot;
            var proj = Matrix4x4.Perspective(s.Cam.fieldOfView, 640f / 420f, s.Cam.nearClipPlane, s.Cam.farClipPlane);
            f.previousViewProj = GL.GetGPUProjectionMatrix(proj, true) * s.Cam.worldToCameraMatrix;
            t.rotation = rot;
            f.targetCamera = s.Cam;
        }

        // ======================= Volume 权重 =======================
        [BookShot("ch27-volume-weight", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void VolumeWeight(Shot s)
        {
            float[] w = { 0f, 0.5f, 1f };
            Showroom(s);
            Post(s);   // 基础：全局 Volume 只有 ACES
            // 第二个全局 Volume：优先级更高，带一套强烈的调色，权重分别为 0 / 0.5 / 1
            var go = new GameObject("Grade Volume");
            var vol = go.AddComponent<Volume>();
            vol.isGlobal = true; vol.priority = 10; vol.weight = w[s.Panel];
            var prof = ScriptableObject.CreateInstance<VolumeProfile>();
            var ca = prof.Add<ColorAdjustments>(); ca.saturation.Override(-70f); ca.contrast.Override(25f);
            var smh = prof.Add<ShadowsMidtonesHighlights>(); smh.shadows.Override(new Vector4(0.75f, 1f, 1.3f, 0f));
            var vg = prof.Add<Vignette>(); vg.intensity.Override(0.5f);
            vol.sharedProfile = prof;
        }

        // ======================= 综合 =======================
        [BookShot("ch27-final", W = 800, H = 450, Panels = 2, Hdr = true)]
        static void Final(Shot s)
        {
            Showroom(s, 2.2f);
            var p = s.Post();
            if (s.Panel == 0) return;   // 左：无任何效果（HDR 直接截断输出）
            p.Add<Tonemapping>().mode.Override(TonemappingMode.ACES);
            var b = p.Add<Bloom>(); b.intensity.Override(1.2f); b.threshold.Override(1f); b.scatter.Override(0.75f);
            var ca = p.Add<ColorAdjustments>(); ca.postExposure.Override(0.3f); ca.contrast.Override(15f); ca.saturation.Override(10f);
            var wb = p.Add<WhiteBalance>(); wb.temperature.Override(8f);
            var smh = p.Add<ShadowsMidtonesHighlights>(); smh.shadows.Override(new Vector4(0.9f, 1f, 1.15f, 0f)); smh.highlights.Override(new Vector4(1.1f, 1.03f, 0.92f, 0f));
            var v = p.Add<Vignette>(); v.intensity.Override(0.3f); v.smoothness.Override(0.4f);
            var g = p.Add<FilmGrain>(); g.type.Override(FilmGrainLookup.Thin2); g.intensity.Override(0.25f);
        }
    }
}
