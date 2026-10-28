// 第 11 章配图
using System;
using System.Linq;
using Cookbook.Core;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Object = UnityEngine.Object;

namespace Cookbook.Ch11
{
    static class Ch11Shots
    {
        const string MyPBR = "Cookbook/Ch11/MyPBR";
        const string MyDebug = "Cookbook/Ch11/MyPBRDebug";

        static Texture2D s_Lut, s_Seams;
        static Texture2D Lut => s_Lut != null ? s_Lut : (s_Lut = MakeLut());
        static Texture2D MakeLut() { var t = DFGLut.Generate(64, 512); t.hideFlags = HideFlags.DontSave; return t; }

        // ---------------- 材质工具 ----------------
        static Material My(Shot s, Color c, float metallic, float smoothness, string shader = MyPBR)
        {
            var m = s.Mat(shader);
            m.SetColor("_BaseColor", c);
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Smoothness", smoothness);
            return m;
        }

        static void UseLut(Material m)
        {
            m.SetTexture("_DFGLut", Lut);
            m.SetFloat("_UseDFGLut", 1);
            m.EnableKeyword("_DFG_LUT");
        }

        /// 给 MyPBR 材质贴上一整套配套贴图（set = "paintedmetal" / "bricks"）
        static Material MyTextured(Shot s, string set, float tiling = 1f, string shader = MyPBR)
        {
            var m = My(s, Color.white, 0, 1, shader);
            m.SetTexture("_BaseMap", s.CoreTex(set + "_albedo"));
            m.SetTextureScale("_BaseMap", Vector2.one * tiling);
            m.SetTexture("_BumpMap", s.CoreTex(set + "_normal")); m.SetFloat("_UseNormalMap", 1); m.EnableKeyword("_NORMALMAP");
            m.SetTexture("_MaskMap", s.CoreTex(set + "_mask")); m.SetFloat("_UseMaskMap", 1); m.EnableKeyword("_MASKMAP");
            UseLut(m);
            return m;
        }

        /// 同一套贴图配给 URP Lit：Mask 的 R/A 走 MetallicGlossMap，G 走 OcclusionMap
        static Material LitTextured(Shot s, string set, float tiling = 1f)
        {
            var m = s.Lit(Color.white, 0, 1);
            m.SetTexture("_BaseMap", s.CoreTex(set + "_albedo"));
            m.SetTextureScale("_BaseMap", Vector2.one * tiling);
            m.SetTexture("_BumpMap", s.CoreTex(set + "_normal")); m.EnableKeyword("_NORMALMAP");
            m.SetTexture("_MetallicGlossMap", s.CoreTex(set + "_mask")); m.EnableKeyword("_METALLICSPECGLOSSMAP");
            m.SetTexture("_OcclusionMap", s.CoreTex(set + "_mask")); m.EnableKeyword("_OCCLUSIONMAP");
            return m;
        }

        static Texture2D Seams()
        {
            if (s_Seams != null) return s_Seams;
            const int N = 256;
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true) { hideFlags = HideFlags.DontSave, wrapMode = TextureWrapMode.Repeat };
            var px = new Color[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    int gx = x % 128, gy = y % 128;
                    float line = (gx < 3 || gy < 3) ? 1f : 0f;                     // 面板缝
                    float dx = gx - 64, dy = gy - 64;
                    float dot = Mathf.Clamp01(1f - Mathf.Sqrt(dx * dx + dy * dy) / 9f); // 面板中心的指示灯
                    float v = Mathf.Max(line, dot > 0 ? 1f : 0f);
                    px[y * N + x] = new Color(v, v, v, 1);
                }
            t.SetPixels(px); t.Apply(true);
            return s_Seams = t;
        }

        // ---------------- 图 11-x：第一步，只有直接光 ----------------
        [BookShot("ch11-step1", W = 960, H = 420)]
        static void Step1(Shot s)
        {
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            for (int i = 0; i < 6; i++)
            {
                float sm = 0.1f + i * 0.17f;
                var a = s.Mat("Cookbook/Ch11/Step1_DirectPBR");
                a.SetColor("_BaseColor", new Color(0.8f, 0.32f, 0.12f)); a.SetFloat("_Metallic", 0); a.SetFloat("_Smoothness", sm);
                s.Sphere(a, new Vector3(-2.75f + i * 1.1f, 0.6f, 0), 1f);
                var b = s.Mat("Cookbook/Ch11/Step1_DirectPBR");
                b.SetColor("_BaseColor", new Color(0.95f, 0.78f, 0.45f)); b.SetFloat("_Metallic", 1); b.SetFloat("_Smoothness", sm);
                s.Sphere(b, new Vector3(-2.75f + i * 1.1f, -0.6f, 0), 1f);
            }
            s.SunDir(35, -40, 1.3f);
            s.LookAt(new Vector3(0, 0, -9.5f), Vector3.zero, 22);
        }

        // ---------------- D / G2 / F / 直接镜面 单项可视化 ----------------
        [BookShot("ch11-terms", W = 440, H = 330, Panels = 4)]
        static void Terms(Shot s)
        {
            int[] views = { 1, 2, 3, 4 };
            s.Background(new Color(0.05f, 0.05f, 0.06f));
            float[] sm = { 0.85f, 0.6f, 0.3f };
            for (int i = 0; i < 3; i++)
            {
                var m = My(s, new Color(0.8f, 0.8f, 0.8f), 0, sm[i], MyDebug);
                m.SetFloat("_View", views[s.Panel]);
                s.Sphere(m, new Vector3(-1.15f + i * 1.15f, 0, 0), 1.05f);
            }
            // D、G2、镜面用右前上方的光；F 换成逆光（光从物体斜后方来），否则 LoH 太大看不出菲涅尔
            if (s.Panel == 2) s.SunDir(25, 155, 1.0f); else s.SunDir(30, -55, 1.0f);
            s.LookAt(new Vector3(0, 0.3f, -6.5f), Vector3.zero, 30);
        }

        // ---------------- 分项：直接光 / 间接漫反射 / 间接镜面 / 合成 ----------------
        static void ScenePieces(Shot s, Func<Material> plain, Func<string, Material> textured, bool lit = false)
        {
            s.Floor(textured("bricks"), 20f);
            s.Knot(textured("paintedmetal"), new Vector3(0, 0.75f, 0.2f), 0.55f);
            var a = plain(); a.SetColor("_BaseColor", new Color(0.85f, 0.85f, 0.85f)); a.SetFloat("_Metallic", 0); a.SetFloat("_Smoothness", 0.35f);
            s.Sphere(a, new Vector3(-1.55f, 0.45f, -0.3f), 0.9f);
            var b = plain(); b.SetColor("_BaseColor", new Color(0.97f, 0.74f, 0.4f)); b.SetFloat("_Metallic", 1); b.SetFloat("_Smoothness", 0.8f);
            s.Sphere(b, new Vector3(1.55f, 0.45f, -0.3f), 0.9f);
        }

        [BookShot("ch11-build", W = 480, H = 360, Panels = 4)]
        static void Build(Shot s)
        {
            int[] views = { 8, 6, 7, 0 };
            Material Plain() { var m = My(s, Color.white, 0, 0.5f, MyDebug); UseLut(m); m.SetFloat("_View", views[s.Panel]); return m; }
            Material Tex(string set) { var m = MyTextured(s, set, set == "bricks" ? 6f : 1f, MyDebug); m.SetFloat("_View", views[s.Panel]); return m; }
            ScenePieces(s, Plain, Tex);
            s.LookAt(new Vector3(0, 1.9f, -4.6f), new Vector3(0, 0.45f, 0), 38);
        }

        // ---------------- DFG LUT：生成 vs 解析近似 ----------------
        [BookShot("ch11-lut", W = 360, H = 360, Panels = 3)]
        static void LutShot(Shot s)
        {
            s.Background(Color.black);
            s.Cam.orthographic = true; s.Cam.orthographicSize = 0.5f;
            s.Cam.transform.position = new Vector3(0, 0, -2); s.Cam.transform.rotation = Quaternion.identity;
            var m = s.Mat("Cookbook/Ch11/DFGLutView");
            m.SetTexture("_DFGLut", Lut);
            m.SetFloat("_Mode", s.Panel);
            s.Quad(m, Vector3.zero, 1f);
            s.Sun.enabled = false;
            if (s.Panel == 2) LogLutError();
        }

        // 把“生成的 LUT”与“解析近似”的最大误差打到日志里，正文引用的是这里的真实数字
        static void LogLutError()
        {
            float maxA = 0, maxB = 0, sumA = 0, sumB = 0; int n = 0;
            var px = Lut.GetPixels();
            int size = Lut.width;
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float NoV = (x + 0.5f) / size, r = (y + 0.5f) / size;
                    Vector4 c0 = new Vector4(-1f, -0.0275f, -0.572f, 0.022f), c1 = new Vector4(1f, 0.0425f, 1.04f, -0.04f);
                    Vector4 rr = c0 * r + c1;
                    float a004 = Mathf.Min(rr.x * rr.x, Mathf.Pow(2f, -9.28f * NoV)) * rr.x + rr.y;
                    float A = -1.04f * a004 + rr.z, B = 1.04f * a004 + rr.w;
                    var c = px[y * size + x];
                    float da = Mathf.Abs(c.r - A), db = Mathf.Abs(c.g - B);
                    maxA = Mathf.Max(maxA, da); maxB = Mathf.Max(maxB, db); sumA += da; sumB += db; n++;
                }
            Debug.Log($"[Ch11] DFG LUT vs analytic: maxA={maxA:F4} maxB={maxB:F4} meanA={sumA / n:F4} meanB={sumB / n:F4} " +
                      $"A(NoV=1,r=0)={px[0 * size + size - 1].r:F3} A+B(NoV=1,r=1)={px[(size - 1) * size + size - 1].r + px[(size - 1) * size + size - 1].g:F3} " +
                      $"A+B(NoV~0.5,r=1)={px[(size - 1) * size + size / 2].r + px[(size - 1) * size + size / 2].g:F3}");
        }

        // ---------------- 白炉测试：多次散射能量补偿 ----------------
        [BookShot("ch11-furnace", W = 720, H = 360, Panels = 2)]
        static void Furnace(Shot s)
        {
            var bg = new Color(0.5f, 0.5f, 0.5f);
            UniformEnvironment(s, bg);
            for (int i = 0; i < 6; i++)
            {
                float sm = 1f - i / 5f;
                var a = My(s, Color.white, 1, sm); UseLut(a); a.SetFloat("_EnergyCompensation", s.Panel);
                s.Sphere(a, new Vector3(-2.75f + i * 1.1f, 0.6f, 0), 1f);
                var b = My(s, new Color(1f, 0.71f, 0.29f), 1, sm); UseLut(b); b.SetFloat("_EnergyCompensation", s.Panel);
                s.Sphere(b, new Vector3(-2.75f + i * 1.1f, -0.6f, 0), 1f);
            }
            s.LookAt(new Vector3(0, 0, -11f), Vector3.zero, 20);
        }

        /// 均匀环境：背景、SH、反射全部是同一个亮度，并关闭主光 —— 白炉测试的标准布置
        static void UniformEnvironment(Shot s, Color bg)
        {
            s.Background(bg);
            s.Sun.enabled = false;
            var lin = bg.linear;
            var cube = new Cubemap(16, TextureFormat.RGBAHalf, true) { hideFlags = HideFlags.DontSave };
            var px = Enumerable.Repeat(new Color(lin.r, lin.g, lin.b, 1), 16 * 16).ToArray();
            foreach (CubemapFace f in new[] { CubemapFace.PositiveX, CubemapFace.NegativeX, CubemapFace.PositiveY, CubemapFace.NegativeY, CubemapFace.PositiveZ, CubemapFace.NegativeZ })
                cube.SetPixels(px, f);
            cube.Apply(true);
            s.Temp.Add(cube);
            RenderSettings.customReflectionTexture = cube;
            var sh = new SphericalHarmonicsL2();
            sh.AddAmbientLight(lin);
            RenderSettings.ambientProbe = sh;
        }

        // ---------------- 粗糙度 × 金属度 矩阵：MyPBR 与 URP Lit ----------------
        static void Matrix(Shot s, bool lit)
        {
            s.Background(new Color(0.2f, 0.21f, 0.23f));
            var baseColor = new Color(0.9f, 0.45f, 0.2f);
            float[] metal = { 0f, 0.5f, 1f };
            for (int r = 0; r < 3; r++)
                for (int c = 0; c < 6; c++)
                {
                    float sm = c / 5f;
                    Material m;
                    if (lit) m = s.Lit(baseColor, metal[r], sm);
                    else { m = My(s, baseColor, metal[r], sm); UseLut(m); }
                    s.Sphere(m, new Vector3(-2.75f + c * 1.1f, 1.1f - r * 1.1f, 0), 1f);
                }
            s.SunDir(40, -35, 1.3f);
            s.LookAt(new Vector3(0, 0, -10.5f), Vector3.zero, 24);
        }
        [BookShot("ch11-matrix-my", W = 960, H = 500)] static void MatrixMy(Shot s) => Matrix(s, false);
        [BookShot("ch11-matrix-lit", W = 960, H = 500)] static void MatrixLit(Shot s) => Matrix(s, true);

        // ---------------- 多光源：Forward（每物体 4 / 8 盏）与 Forward+ ----------------
        [BookShot("ch11-lights", W = 480, H = 360, Panels = 3)]
        static void Lights(Shot s)
        {
            if (s.Panel < 2) s.Renderer.renderingMode = RenderingMode.Forward;
            s.Asset.maxAdditionalLightsCount = s.Panel == 0 ? 4 : 8;
            s.Floor(MyTextured(s, "bricks", 8f), 16f);
            s.Knot(MyTextured(s, "paintedmetal"), new Vector3(0, 0.7f, 0), 0.5f);
            for (int i = 0; i < 4; i++)
            {
                float a = (i + 0.5f) * Mathf.PI / 2f;
                var m = My(s, new Color(0.85f, 0.85f, 0.85f), i % 2, 0.75f); UseLut(m);
                s.Sphere(m, new Vector3(Mathf.Cos(a) * 1.9f, 0.35f, Mathf.Sin(a) * 1.9f), 0.7f);
            }
            Color[] cols = { new Color(1, .3f, .2f), new Color(.2f, .6f, 1), new Color(.3f, 1, .4f), new Color(1, .8f, .2f),
                             new Color(.8f, .3f, 1), new Color(.2f, 1, 1), new Color(1, .5f, .1f), new Color(1, .2f, .6f) };
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4f;
                s.Point(new Vector3(Mathf.Cos(a) * 3f, 0.5f, Mathf.Sin(a) * 3f), cols[i], 3f, 3.5f);
            }
            s.SunDir(55, -30, 0.12f);
            s.LookAt(new Vector3(0, 5.2f, -6.2f), new Vector3(0, 0.1f, 0.3f), 45);
        }

        // ---------------- 贴图逐项加入 ----------------
        [BookShot("ch11-maps", W = 440, H = 360, Panels = 4)]
        static void Maps(Shot s)
        {
            Material Make()
            {
                var m = My(s, Color.white, 0, 0.55f);
                UseLut(m);
                m.SetTexture("_BaseMap", s.CoreTex("paintedmetal_albedo"));
                if (s.Panel >= 1) { m.SetTexture("_BumpMap", s.CoreTex("paintedmetal_normal")); m.EnableKeyword("_NORMALMAP"); m.SetFloat("_BumpScale", 3f); }
                if (s.Panel >= 2) { m.SetTexture("_MaskMap", s.CoreTex("paintedmetal_mask")); m.EnableKeyword("_MASKMAP"); m.SetFloat("_Smoothness", 1); }
                if (s.Panel >= 3) { m.SetTexture("_EmissionMap", Seams()); m.SetColor("_EmissionColor", new Color(0.2f, 1.6f, 2.2f)); m.EnableKeyword("_EMISSION"); }
                return m;
            }
            s.Floor();
            s.Sphere(Make(), new Vector3(-0.7f, 0.65f, 0), 1.3f);
            var cube = s.Cube(Make(), new Vector3(0.85f, 0.5f, 0.3f), 1.0f);
            cube.transform.rotation = Quaternion.Euler(0, 35, 0);
            s.SunDir(38, -50, 1.2f);
            s.LookAt(new Vector3(0, 1.6f, -3.6f), new Vector3(0.05f, 0.5f, 0), 38);
        }

        // ---------------- 实物效果：MyPBR vs URP Lit ----------------
        [BookShot("ch11-hero", W = 720, H = 520, Panels = 2)]
        static void Hero(Shot s)
        {
            bool lit = s.Panel == 1;
            Material Tex(string set, float tiling) => lit ? LitTextured(s, set, tiling) : MyTextured(s, set, tiling);
            s.Floor(Tex("bricks", 7.5f), 15f);
            var wall = s.Cube(Tex("bricks", 3f), new Vector3(0, 2f, 2.2f), 1f);
            wall.transform.localScale = new Vector3(8f, 4f, 0.3f);
            s.Knot(Tex("paintedmetal", 1f), new Vector3(0, 0.85f, 0.2f), 0.6f);
            s.Sphere(Tex("paintedmetal", 1f), new Vector3(-1.75f, 0.55f, -0.2f), 1.1f);
            var c = s.Cube(Tex("paintedmetal", 1f), new Vector3(1.75f, 0.45f, -0.1f), 0.9f);
            c.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Point(new Vector3(-2.2f, 1.6f, -1.4f), new Color(1f, 0.55f, 0.25f), 2.5f, 5f);
            s.SunDir(42, -40, 1.25f);
            s.LookAt(new Vector3(0, 1.7f, -5.2f), new Vector3(0, 0.75f, 0), 40);
        }

        // ---------------- DepthNormals Pass 的验证：SSAO ----------------
        [BookShot("ch11-ssao", W = 640, H = 420, Panels = 2)]
        static void Ssao(Shot s)
        {
            if (s.Panel == 1)
            {
                var t = typeof(UniversalRendererData).Assembly.GetType("UnityEngine.Rendering.Universal.ScreenSpaceAmbientOcclusion");
                var f = (ScriptableRendererFeature)ScriptableObject.CreateInstance(t);
                f.name = "SSAO";
                var so = new SerializedObject(f);
                so.FindProperty("m_Settings.Intensity").floatValue = 2.5f;
                so.FindProperty("m_Settings.Radius").floatValue = 0.35f;
                so.FindProperty("m_Settings.DirectLightingStrength").floatValue = 0.4f;
                so.ApplyModifiedPropertiesWithoutUndo();
                f.Create();
                s.Temp.Add(f);
                s.Renderer.rendererFeatures.Add(f);
                s.Renderer.SetDirty();
            }
            Material Plain(Color c, float metal, float sm) { var m = My(s, c, metal, sm); UseLut(m); return m; }
            s.Floor(Plain(new Color(0.75f, 0.75f, 0.72f), 0, 0.3f), 20f);
            var w1 = s.Cube(Plain(new Color(0.75f, 0.75f, 0.72f), 0, 0.3f), new Vector3(0, 1.5f, 1.2f), 1f); w1.transform.localScale = new Vector3(6f, 3f, 0.2f);
            var w2 = s.Cube(Plain(new Color(0.75f, 0.75f, 0.72f), 0, 0.3f), new Vector3(-1.6f, 1.5f, 0f), 1f); w2.transform.localScale = new Vector3(0.2f, 3f, 2.6f);
            s.Knot(MyTextured(s, "paintedmetal"), new Vector3(0.3f, 0.75f, 0.2f), 0.5f);
            for (int i = 0; i < 5; i++)
            {
                var cb = s.Cube(Plain(new Color(0.8f, 0.35f, 0.2f), 0, 0.4f), new Vector3(-1.15f + i * 0.05f, 0.2f + i * 0.4f, 0.75f - i * 0.02f), 0.4f);
                cb.transform.rotation = Quaternion.Euler(0, i * 17f, 0);
            }
            s.Sphere(Plain(new Color(0.9f, 0.9f, 0.9f), 0, 0.6f), new Vector3(1.4f, 0.45f, 0.4f), 0.9f);
            s.SunDir(55, 30, 1.0f);
            s.LookAt(new Vector3(1.2f, 1.9f, -3.6f), new Vector3(-0.1f, 0.7f, 0.5f), 42);
        }
            // ---------------- Rendering Debugger 作用于 MyPBR（验证 DEBUG_DISPLAY 分支）----------------
        [BookShot("ch11-rd", W = 480, H = 330, Panels = 3)]
        static void RenderingDebugger(Shot s)
        {
            if (s.Panel == 0) MyPBRVariantCheck.Check();   // 顺便强制编译几组关键字组合
            Material Plain(Color c, float metal, float sm) { var m = My(s, c, metal, sm); UseLut(m); return m; }
            s.Floor(MyTextured(s, "bricks", 8f), 16f);
            s.Knot(MyTextured(s, "paintedmetal"), new Vector3(0, 0.75f, 0.3f), 0.5f);
            s.Sphere(Plain(new Color(0.85f, 0.85f, 0.85f), 0, 0.3f), new Vector3(-1.5f, 0.45f, -0.3f), 0.9f);
            s.Sphere(Plain(new Color(0.97f, 0.74f, 0.4f), 1, 0.85f), new Vector3(1.5f, 0.45f, -0.3f), 0.9f);
            s.SunDir(42, -35, 1.2f);
            s.LookAt(new Vector3(0, 1.9f, -4.4f), new Vector3(0, 0.45f, 0), 40);
            if (s.Panel == 0) return;
            var mat = UniversalRenderPipelineDebugDisplaySettings.Instance.materialSettings;
            mat.materialDebugMode = s.Panel == 1 ? DebugMaterialMode.Albedo : DebugMaterialMode.Smoothness;
            int frames = 0;
            Action<ScriptableRenderContext, Camera> reset = null;
            reset = (ctx, cam) =>
            {
                if (cam != s.Cam || ++frames < 3) return;
                mat.materialDebugMode = DebugMaterialMode.None;          // 渲染完本张图后恢复，免得影响后续配图
                RenderPipelineManager.endCameraRendering -= reset;
            };
            RenderPipelineManager.endCameraRendering += reset;
        }
    }
}
