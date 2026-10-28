// 第 13 章配图
using System;
using System.Collections.Generic;
using System.IO;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch13
{
    static class Ch13Shots
    {
        // ---------------- 贴图工具：用不同的“导入设置”重新加载配套贴图 ----------------
        static readonly Dictionary<string, Texture2D> s_Cache = new Dictionary<string, Texture2D>();

        /// 从 PNG 原始字节建贴图；linear=false 相当于导入设置里勾选 sRGB
        static Texture2D LoadCore(string name, bool linear, string variant = "", Func<Color32, Color32> edit = null)
        {
            string key = name + linear + variant;
            if (s_Cache.TryGetValue(key, out var t) && t != null) return t;
            var bytes = File.ReadAllBytes("Assets/Cookbook/_Core/Textures/" + name + ".png");
            var tmp = new Texture2D(2, 2, TextureFormat.RGBA32, false, true);
            tmp.LoadImage(bytes);
            var px = tmp.GetPixels32();
            if (edit != null) for (int i = 0; i < px.Length; i++) px[i] = edit(px[i]);
            t = new Texture2D(tmp.width, tmp.height, TextureFormat.RGBA32, true, linear)
            { name = key, wrapMode = TextureWrapMode.Repeat, anisoLevel = 4, hideFlags = HideFlags.DontSave };
            t.SetPixels32(px);
            t.Apply(true);
            UnityEngine.Object.DestroyImmediate(tmp);
            return s_Cache[key] = t;
        }

        static PaintedMetalGenerator.Result s_PM;
        static PaintedMetalGenerator.Result PM => s_PM.albedo != null ? s_PM : (s_PM = PaintedMetalGenerator.Generate(PaintedMetalGenerator.Settings.Default));

        /// URP Lit + 一整套贴图。mask 同时进 MetallicGlossMap（读 R、A）和 OcclusionMap（读 G）
        static Material LitSet(Shot s, Texture albedo, Texture mask, Texture normal, float tiling = 1f, float bumpScale = 1f)
        {
            var m = s.Lit(Color.white, 0, mask != null ? 1f : 0.5f);
            m.SetTexture("_BaseMap", albedo);
            m.SetTextureScale("_BaseMap", Vector2.one * tiling);
            if (normal != null) { m.SetTexture("_BumpMap", normal); m.SetFloat("_BumpScale", bumpScale); m.EnableKeyword("_NORMALMAP"); }
            if (mask != null)
            {
                m.SetTexture("_MetallicGlossMap", mask); m.EnableKeyword("_METALLICSPECGLOSSMAP");
                m.SetTexture("_OcclusionMap", mask); m.EnableKeyword("_OCCLUSIONMAP");
            }
            return m;
        }

        static Material Gray(Shot s, float srgb, float metallic = 0, float smooth = 0.45f) =>
            s.Lit(new Color(srgb, srgb, srgb), metallic, smooth);   // Color 是 sRGB 值，Unity 在线性空间下自动转换

        // ---------------- 色彩空间：sRGB 勾错的后果 ----------------
        [BookShot("ch13-colorspace", W = 480, H = 360, Panels = 3)]
        static void ColorSpace(Shot s)
        {
            bool albedoLinear = s.Panel == 1;        // 错误：颜色贴图关了 sRGB
            bool maskSRGB = s.Panel == 2;            // 错误：数据贴图开了 sRGB
            Material Set(string set) => LitSet(s, LoadCore(set + "_albedo", albedoLinear), LoadCore(set + "_mask", !maskSRGB),
                                               LoadCore(set + "_normal", true), set == "bricks" ? 1f : 1f);
            s.Floor();
            s.Sphere(Set("paintedmetal"), new Vector3(-0.75f, 0.65f, 0), 1.3f);
            var c = s.Cube(Set("bricks"), new Vector3(0.9f, 0.55f, 0.2f), 1.1f);
            c.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.SunDir(40, -45, 1.2f);
            s.LookAt(new Vector3(0, 1.5f, -3.8f), new Vector3(0.05f, 0.55f, 0), 38);
        }

        // ---------------- 程序化刷漆金属：四个通道 ----------------
        [BookShot("ch13-paint-channels", W = 340, H = 340, Panels = 4)]
        static void PaintChannels(Shot s)
        {
            s.Background(Color.black);
            s.Cam.orthographic = true; s.Cam.orthographicSize = 0.5f;
            s.Cam.transform.position = new Vector3(0, 0, -2); s.Cam.transform.rotation = Quaternion.identity;
            s.Sun.enabled = false;
            var m = s.Mat("Cookbook/Ch13/ChannelView");
            int[] ch = { 4, 0, 1, 3 };
            m.SetTexture("_MainTex", s.Panel == 0 ? PM.albedo : PM.mask);
            m.SetFloat("_Channel", ch[s.Panel]);
            m.SetFloat("_LinearData", s.Panel == 0 ? 0 : 1);
            s.Quad(m, Vector3.zero, 1f);
        }

        // ---------------- 程序化刷漆金属：逐步加贴图 ----------------
        [BookShot("ch13-paint-flow", W = 440, H = 360, Panels = 4)]
        static void PaintFlow(Shot s)
        {
            var pm = PM;
            if (s.Panel == 3)
            {
                var st = PaintedMetalGenerator.Settings.Default;
                st.wear = 0.62f; st.paintColor = new Color(0.62f, 0.16f, 0.1f); st.seed = 21;
                pm = PaintedMetalGenerator.Generate(st);
            }
            Material Make() => LitSet(s, pm.albedo, s.Panel >= 1 ? pm.mask : null, s.Panel >= 2 ? pm.normal : null, 1f, 1f);
            s.Floor();
            s.Sphere(Make(), new Vector3(-0.7f, 0.65f, 0), 1.3f);
            var c = s.Cube(Make(), new Vector3(0.85f, 0.5f, 0.3f), 1.0f);
            c.transform.rotation = Quaternion.Euler(0, 35, 0);
            s.SunDir(38, -50, 1.2f);
            s.LookAt(new Vector3(0, 1.6f, -3.6f), new Vector3(0.05f, 0.5f, 0), 38);
        }

        // ---------------- 把粗糙度当光滑度用 ----------------
        [BookShot("ch13-rough-as-smooth", W = 480, H = 360, Panels = 2)]
        static void RoughAsSmooth(Shot s)
        {
            // 砖墙 Mask 的 A 通道是光滑度（砖 0.25~0.4、灰缝 0.1）；右图模拟“把粗糙度图直接塞进光滑度通道”
            var mask = s.Panel == 0 ? LoadCore("bricks_mask", true)
                                    : LoadCore("bricks_mask", true, "invA", c => new Color32(c.r, c.g, c.b, (byte)(255 - c.a)));
            Material Make(float tiling) => LitSet(s, LoadCore("bricks_albedo", false), mask, LoadCore("bricks_normal", true), tiling, 1.2f);
            s.Floor(Make(5f), 10f);
            var wall = s.Cube(Make(2f), new Vector3(0, 1.5f, 1.5f), 1f);
            wall.transform.localScale = new Vector3(6f, 3f, 0.2f);
            s.SunDir(28, -55, 1.3f);
            s.LookAt(new Vector3(-1.4f, 0.9f, -1.8f), new Vector3(0.4f, 0.55f, 1.0f), 50);
        }

        // ---------------- Albedo 取值：从纯黑到纯白 ----------------
        static readonly int[] GraySteps = { 0, 15, 45, 80, 128, 190, 235, 255 };

        [BookShot("ch13-albedo-range", W = 960, H = 300, Panels = 2)]
        static void AlbedoRange(Shot s)
        {
            s.Background(new Color(0.32f, 0.33f, 0.35f));
            for (int i = 0; i < GraySteps.Length; i++)
            {
                var m = Gray(s, GraySteps[i] / 255f, 0, 0.4f);
                if (s.Panel == 1) m.shader = Shader.Find("Cookbook/Ch13/PBRValidate");
                s.Sphere(m, new Vector3(-3.85f + i * 1.1f, 0, 0), 1f);
            }
            s.SunDir(40, -35, 1.2f);
            s.LookAt(new Vector3(0, 0, -12f), Vector3.zero, 15);
        }

        // ---------------- 金属度的常见错误 ----------------
        [BookShot("ch13-metal-errors", W = 960, H = 330)]
        static void MetalErrors(Shot s)
        {
            s.Floor();
            var gold = new Color(1f, 0.78f, 0.42f);
            Material[] mats =
            {
                s.Lit(gold, 1, 0.75f),                                   // 正确：亮色金属
                s.Lit(new Color(0.16f, 0.13f, 0.09f), 1, 0.75f),         // 错误：金属的 Albedo 画得很暗
                s.Lit(gold, 0.5f, 0.75f),                                // 错误：大面积“半金属”
                s.Lit(gold, 0, 0.75f),                                   // 错误：金属材质忘了开金属度
                s.Lit(new Color(0.7f, 0.08f, 0.06f), 1, 0.75f),          // 错误：红色塑料被设成金属
            };
            for (int i = 0; i < mats.Length; i++) s.Sphere(mats[i], new Vector3(-2.4f + i * 1.2f, 0.55f, 0), 1.05f);
            s.SunDir(40, -35, 1.25f);
            s.LookAt(new Vector3(0, 1.9f, -6.6f), new Vector3(0, 0.45f, 0), 30);
        }

        // ---------------- 法线贴图的常见错误 ----------------
        [BookShot("ch13-normal-errors", W = 440, H = 330, Panels = 4)]
        static void NormalErrors(Shot s)
        {
            Texture2D n;
            float scale = 1f;
            switch (s.Panel)
            {
                case 1: n = LoadCore("bricks_normal", true, "flipY", c => new Color32(c.r, (byte)(255 - c.g), c.b, c.a)); break;  // Y 翻转（DirectX 约定）
                case 2: n = LoadCore("bricks_normal", false); break;   // 没标记成 Normal Map：被当成 sRGB 颜色解码
                default: n = LoadCore("bricks_normal", true); break;
            }
            if (s.Panel == 3) scale = 3.5f;                             // 强度拉过头
            var m = LitSet(s, LoadCore("bricks_albedo", false), LoadCore("bricks_mask", true), n, 1f, scale);
            var wall = s.Quad(m, new Vector3(0, 1f, 0), 3f);             // Quad 默认朝 -Z，正对相机
            s.Background(new Color(0.15f, 0.16f, 0.18f));
            s.SunDir(68, 25, 2.0f);                                      // 从上方贴着墙面照下来的掠射光：凸起砖块的上沿受光、下沿背光
            s.LookAt(new Vector3(0, 1f, -2.0f), new Vector3(0, 1f, 0), 36);
        }

        // ---------------- 光照环境对判断的影响 ----------------
        [BookShot("ch13-lighting-env", W = 480, H = 360, Panels = 3)]
        static void LightingEnv(Shot s)
        {
            s.Floor();
            s.Sphere(LitSet(s, PM.albedo, PM.mask, PM.normal), new Vector3(-1.05f, 0.55f, 0), 1.1f);
            s.Sphere(Gray(s, 0.73f, 0, 0.3f), new Vector3(0.15f, 0.4f, -0.4f), 0.8f);   // 中性灰参考球
            var c = s.Cube(LitSet(s, LoadCore("bricks_albedo", false), LoadCore("bricks_mask", true), LoadCore("bricks_normal", true)),
                           new Vector3(1.2f, 0.45f, 0.3f), 0.9f);
            c.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.LookAt(new Vector3(0, 1.5f, -3.9f), new Vector3(0.05f, 0.45f, 0), 38);
            if (s.Panel == 1)
            {
                // 夕阳：低角度暖色主光 + 偏蓝、偏暗的环境光
                s.SunDir(9, -60, 1.6f); s.Sun.color = new Color(1f, 0.55f, 0.25f);
                var sh = new SphericalHarmonicsL2(); sh.AddAmbientLight(new Color(0.05f, 0.08f, 0.16f));
                RenderSettings.ambientProbe = sh;
                RenderSettings.reflectionIntensity = 0.35f;
            }
            else if (s.Panel == 2)
            {
                // 黑屋子里一盏偏冷的点光：没有环境光、没有反射
                s.Sun.enabled = false;
                s.Background(Color.black);
                RenderSettings.ambientProbe = new SphericalHarmonicsL2();
                RenderSettings.reflectionIntensity = 0f;
                s.Point(new Vector3(-0.3f, 1.6f, -1.2f), new Color(0.75f, 0.85f, 1f), 3.5f, 6f);
            }
            else s.SunDir(42, -40, 1.25f);
        }

        // ---------------- 校验用场景 ----------------
        static void ValidationScene(Shot s)
        {
            s.Floor(LitSet(s, LoadCore("bricks_albedo", false), LoadCore("bricks_mask", true), LoadCore("bricks_normal", true), 8f), 16f);
            Material[] mats =
            {
                Gray(s, 0.02f, 0, 0.4f),                                 // 电介质过暗（“纯黑”）
                s.Lit(new Color(0.55f, 0.3f, 0.2f), 0, 0.4f),            // 正常电介质
                Gray(s, 1f, 0, 0.4f),                                    // 电介质过亮（“纯白”）
                s.Lit(new Color(0.95f, 0.75f, 0.45f), 0.5f, 0.7f),       // 金属度灰区
                s.Lit(new Color(0.18f, 0.18f, 0.2f), 1, 0.7f),           // 金属但 Albedo 很暗
                s.Lit(new Color(0.95f, 0.93f, 0.88f), 1, 0.7f),          // 正常金属
            };
            for (int i = 0; i < mats.Length; i++) s.Sphere(mats[i], new Vector3(-2.75f + i * 1.1f, 0.5f, 0), 0.95f);
            s.Knot(LitSet(s, PM.albedo, PM.mask, PM.normal), new Vector3(0, 0.75f, 2.1f), 0.5f);
            s.SunDir(42, -35, 1.2f);
            s.LookAt(new Vector3(0, 2.5f, -6.4f), new Vector3(0, 0.6f, 0.6f), 38);
        }

        // 用 URP 的 Rendering Debugger 做材质校验（与在 Window › Analysis › Rendering Debugger 里点选等价）
        static void DebugValidation(Shot s, DebugMaterialValidationMode mode)
        {
            var mat = UniversalRenderPipelineDebugDisplaySettings.Instance.materialSettings;
            mat.materialValidationMode = mode;
            // 本张图渲染 3 帧后自动恢复，避免影响后面的配图
            int frames = 0;
            Action<ScriptableRenderContext, Camera> reset = null;
            reset = (ctx, cam) =>
            {
                if (cam != s.Cam || ++frames < 3) return;
                mat.materialValidationMode = DebugMaterialValidationMode.None;
                RenderPipelineManager.endCameraRendering -= reset;
            };
            RenderPipelineManager.endCameraRendering += reset;
        }

        [BookShot("ch13-rd", W = 540, H = 330, Panels = 3)]
        static void RenderingDebugger(Shot s)
        {
            ValidationScene(s);
            if (s.Panel == 1) DebugValidation(s, DebugMaterialValidationMode.Albedo);
            if (s.Panel == 2) DebugValidation(s, DebugMaterialValidationMode.Metallic);
        }

        //#region validate_feature
        // 用 RenderObjects（Override Mode = Shader）把整个场景的不透明物体用 PBRValidate 重画一遍。
        // 与在 Renderer 资产的 Inspector 里手动添加 Render Objects Feature 并这样填写等价。
        static void AddValidateFeature(Shot s)
        {
            Shader.SetGlobalVector("_PBRValidateRange", new Vector4(30f / 255f, 240f / 255f, 180f / 255f, 1f));
            var f = s.Feature<RenderObjects>();
            f.settings.Event = RenderPassEvent.AfterRenderingOpaques;
            f.settings.filterSettings.RenderQueueType = RenderQueueType.Opaque;
            f.settings.filterSettings.LayerMask = ~0;
            f.settings.overrideMode = RenderObjects.RenderObjectsSettings.OverrideMaterialMode.Shader;
            f.settings.overrideShader = Shader.Find("Cookbook/Ch13/PBRValidate");
            f.settings.overrideShaderPassIndex = 0;
            f.Create();   // 改完 settings 要重新 Create，Feature 才会按新设置建 Pass
        }
        //#endregion

        [BookShot("ch13-validate", W = 720, H = 400, Panels = 2)]
        static void Validate(Shot s)
        {
            ValidationScene(s);
            if (s.Panel == 1) AddValidateFeature(s);
        }

        // ---------------- 砖墙 PBR 套图 ----------------
        [BookShot("ch13-bricks", W = 480, H = 360, Panels = 3)]
        static void Bricks(Shot s)
        {
            var mask = s.Panel >= 1 ? LoadCore("bricks_mask", true) : null;
            Material Make(float tiling)
            {
                var m = LitSet(s, LoadCore("bricks_albedo", false), mask, LoadCore("bricks_normal", true), tiling, 1.2f);
                if (s.Panel == 2)
                {
                    m.SetTexture("_ParallaxMap", LoadCore("bricks_height", true));
                    m.SetFloat("_Parallax", 0.05f);
                    m.EnableKeyword("_PARALLAXMAP");
                }
                return m;
            }
            s.Floor(Make(5f), 10f);
            var wall = s.Cube(Make(2f), new Vector3(0, 1.5f, 1.5f), 1f);
            wall.transform.localScale = new Vector3(6f, 3f, 0.2f);
            s.SunDir(28, -55, 1.3f);
            s.LookAt(new Vector3(-1.4f, 0.9f, -1.8f), new Vector3(0.4f, 0.55f, 1.0f), 50);
            if (s.Panel == 0) Debug.Log("[Ch13] audit _Core/Textures: " + string.Join(" | ", PBRTextureAudit.AuditFolder("Assets/Cookbook/_Core/Textures")) + " (end)");
        }
    }
}
