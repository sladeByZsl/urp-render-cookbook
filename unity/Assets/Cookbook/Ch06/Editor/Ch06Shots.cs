// 第 6 章配图：多光源、衰减、阴影接收/投射、Bias、级联、附加光阴影、ClassicLit
using System.Reflection;
using Cookbook.Core;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch06
{
    static class Ch06Shots
    {
        static readonly Color Night = new Color(0.04f, 0.045f, 0.06f);

        // KeywordEnum：Unity 2022 新建材质时会按属性默认值自动打开一个关键字，
        // 所以切换时要同时设属性值、打开目标关键字、关掉同组其它关键字
        static void SetKeywordEnum(Material m, string prop, string[] options, int index)
        {
            m.SetFloat(prop, index);
            for (int i = 0; i < options.Length; i++)
            {
                string kw = (prop + "_" + options[i]).ToUpperInvariant();
                if (i == index) m.EnableKeyword(kw); else m.DisableKeyword(kw);
            }
        }

        static Material Mat(Shot s, string shader, Color c)
        {
            var m = s.Mat("Cookbook/Ch06/" + shader);
            m.SetColor("_BaseColor", c);
            return m;
        }

        // 用本章 Shader 做的棋盘格地面（每格 1 米，与 Shot.Floor 的默认地面一致）
        static GameObject Floor(Shot s, string shader, float size = 60f, Color? c = null, bool checker = true)
        {
            var m = Mat(s, shader, c ?? new Color(0.75f, 0.75f, 0.75f));
            if (checker)
            {
                m.SetTexture("_BaseMap", s.CoreTex("checker"));
                m.SetTextureScale("_BaseMap", new Vector2(size / 8f, size / 8f));
            }
            return s.Floor(m, size);
        }

        static void SetCascadeSplit4(Shot s, Vector3 split)
        {
            var so = new SerializedObject(s.Asset);
            so.FindProperty("m_Cascade4Split").vector3Value = split;
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        static UniversalAdditionalLightData LightData(Light l)
        {
            var d = l.GetComponent<UniversalAdditionalLightData>();
            return d != null ? d : l.gameObject.AddComponent<UniversalAdditionalLightData>();
        }

        // ---------------- 6.1 多光源：Forward 与 Forward+ ----------------
        [BookShot("ch06-forward-vs-plus", W = 640, H = 420, Panels = 3)]
        static void ForwardVsPlus(Shot s)
        {
            if (s.Panel < 2) s.Renderer.renderingMode = RenderingMode.Forward;
            s.Asset.maxAdditionalLightsCount = s.Panel == 0 ? 4 : 8;
            s.Background(Night);
            var floor = Floor(s, "MultiLightLambert");
            floor.GetComponent<MeshRenderer>().sharedMaterial.SetFloat("_AmbientStrength", 0.1f);
            for (int i = 0; i < 3; i++)
            {
                var m = Mat(s, "MultiLightLambert", new Color(0.85f, 0.85f, 0.85f));
                m.SetFloat("_AmbientStrength", 0.1f);
                s.Sphere(m, new Vector3((i - 1) * 1.4f, 0.45f, 0.3f), 0.9f);
            }
            for (int i = 0; i < 8; i++)
            {
                float a = i / 8f * Mathf.PI * 2f;
                var c = Color.HSVToRGB(i / 8f, 0.85f, 1f);
                s.Point(new Vector3(Mathf.Cos(a) * 2.6f, 0.35f, 0.3f + Mathf.Sin(a) * 2.0f), c, 2.5f, 2.6f);
            }
            s.SunDir(50, -30, 0.05f);
            s.LookAt(new Vector3(0, 4.2f, -4.6f), new Vector3(0, 0, 0.4f), 45);
        }

        // ---------------- 6.2 衰减 ----------------
        [BookShot("ch06-falloff", W = 480, H = 400, Panels = 4)]
        static void Falloff(Shot s)
        {
            // 0：平方反比 + Forward+   1：平方反比 + Forward   2：线性   3：URP 平滑衰减
            string[] opts = { "URP", "InverseSquare", "Linear" };
            int[] kw = { 1, 1, 2, 0 };
            if (s.Panel == 1) s.Renderer.renderingMode = RenderingMode.Forward;
            s.Background(Night);
            var fm = Mat(s, "FalloffCompare", new Color(0.7f, 0.7f, 0.7f));
            SetKeywordEnum(fm, "_Falloff", opts, kw[s.Panel]);
            fm.SetFloat("_AmbientStrength", 0.05f);
            s.Floor(fm, 60f);
            var sm = Mat(s, "FalloffCompare", new Color(0.8f, 0.8f, 0.8f));
            SetKeywordEnum(sm, "_Falloff", opts, kw[s.Panel]);
            sm.SetFloat("_AmbientStrength", 0.05f);
            s.Sphere(sm, new Vector3(1.0f, 0.4f, 1.3f), 0.8f);
            s.Point(new Vector3(0, 0.5f, 0.6f), new Color(1f, 0.85f, 0.65f), 3f, 2.5f);
            s.SunDir(50, -30, 0f);
            s.LookAt(new Vector3(0, 5.5f, -3.0f), new Vector3(0, 0, 0.8f), 55);
        }

        [BookShot("ch06-spot-angle", W = 640, H = 420, Panels = 3)]
        static void SpotAngle(Shot s)
        {
            s.Background(Night);
            var fm = Mat(s, "MultiLightLambert", new Color(0.75f, 0.75f, 0.75f));
            fm.SetFloat("_AmbientStrength", 0.05f);
            s.Floor(fm, 60f);
            var spot = s.Spot(new Vector3(0, 3.2f, -0.6f), new Vector3(0, 0, 0.9f), new Color(1f, 0.9f, 0.75f), 6f, 8f, 70f);
            spot.innerSpotAngle = s.Panel == 0 ? 5f : s.Panel == 1 ? 45f : 68f;
            s.SunDir(50, -30, 0f);
            s.LookAt(new Vector3(0, 4.2f, -4.2f), new Vector3(0, 0, 0.9f), 45);
        }

        // ---------------- 6.3 接收阴影 ----------------
        static void ShadowScene(Shot s, string shader, bool receiveOff = false)
        {
            var floor = Floor(s, shader);
            var mats = new System.Collections.Generic.List<Material> { floor.GetComponent<MeshRenderer>().sharedMaterial };
            var m1 = Mat(s, shader, new Color(0.85f, 0.45f, 0.25f)); mats.Add(m1);
            var m2 = Mat(s, shader, new Color(0.3f, 0.5f, 0.8f)); mats.Add(m2);
            var m3 = Mat(s, shader, new Color(0.85f, 0.85f, 0.8f)); mats.Add(m3);
            s.Knot(m1, new Vector3(-0.2f, 0.95f, 0.8f), 0.9f);
            s.Sphere(m2, new Vector3(-1.5f, 0.45f, -0.2f), 0.9f);
            var cube = s.Cube(m3, new Vector3(1.4f, 0.45f, -0.1f), 0.9f);
            cube.transform.rotation = Quaternion.Euler(0, 30, 0);
            if (receiveOff) foreach (var m in mats) m.EnableKeyword("_RECEIVE_SHADOWS_OFF");
        }

        [BookShot("ch06-receive-shadow", W = 640, H = 420, Panels = 3)]
        static void ReceiveShadow(Shot s)
        {
            ShadowScene(s, "ShadowReceive", s.Panel == 0);
            s.Sun.shadows = s.Panel == 1 ? LightShadows.Hard : LightShadows.Soft;
            s.SunDir(45, -40);
            s.LookAt(new Vector3(0, 2.2f, -4.6f), new Vector3(0, 0.4f, 0.3f), 40);
        }

        [BookShot("ch06-soft-quality", W = 480, H = 360, Panels = 4)]
        static void SoftQuality(Shot s)
        {
            s.AssetProp("m_MainLightShadowmapResolution", 1024);
            Floor(s, "ShadowReceive", 60f, null, false);
            var m = Mat(s, "ShadowReceive", new Color(0.85f, 0.85f, 0.8f));
            var pole = s.Cylinder(m, new Vector3(0, 1f, 0), 1f);
            pole.transform.localScale = new Vector3(0.12f, 1f, 0.12f);
            var box = s.Cube(m, new Vector3(-0.6f, 0.25f, 0.4f), 0.5f);
            box.transform.rotation = Quaternion.Euler(0, 20, 0);
            if (s.Panel == 0) s.Sun.shadows = LightShadows.Hard;
            else
            {
                s.Sun.shadows = LightShadows.Soft;
                LightData(s.Sun).softShadowQuality = s.Panel == 1 ? SoftShadowQuality.Low : s.Panel == 2 ? SoftShadowQuality.Medium : SoftShadowQuality.High;
            }
            s.SunDir(40, 30);
            s.LookAt(new Vector3(-0.2f, 1.3f, -1.3f), new Vector3(0.45f, 0f, 0.75f), 42);
        }

        // ---------------- 6.4 投射阴影 ----------------
        [BookShot("ch06-no-caster", W = 640, H = 420, Panels = 2)]
        static void NoCaster(Shot s)
        {
            Floor(s, "ShadowReceive");
            var m = Mat(s, "ShadowReceive", new Color(0.85f, 0.45f, 0.25f));
            m.SetShaderPassEnabled("ShadowCaster", s.Panel == 1);
            s.Knot(m, new Vector3(0, 1.0f, 0.4f), 1.0f);
            s.SunDir(55, -40);
            s.LookAt(new Vector3(0, 2.2f, -4.2f), new Vector3(0, 0.5f, 0.4f), 38);
        }

        // ---------------- 6.5 Bias ----------------
        [BookShot("ch06-bias", W = 480, H = 400, Panels = 4)]
        static void Bias(Shot s)
        {
            // 0：无偏移（URP 光栅化时仍有固定的硬件斜率偏移，软阴影的大卷积核会把粉刺放大）
            // 1：默认 (1,1)  2：深度偏移 8  3：法线偏移 3
            Vector2[] bias = { new Vector2(0, 0), new Vector2(1, 1), new Vector2(8, 0), new Vector2(0, 3) };
            s.Asset.shadowDepthBias = bias[s.Panel].x;
            s.Asset.shadowNormalBias = bias[s.Panel].y;
            s.Asset.shadowCascadeCount = 1;
            s.Asset.shadowDistance = 14f;
            s.AssetProp("m_MainLightShadowmapResolution", 512);
            s.Sun.shadows = LightShadows.Soft;
            LightData(s.Sun).softShadowQuality = SoftShadowQuality.High;
            Floor(s, "ShadowReceive", 60f, new Color(0.75f, 0.75f, 0.75f), false);
            var m = Mat(s, "ShadowReceive", new Color(0.85f, 0.85f, 0.8f));
            var cube = s.Cube(m, new Vector3(0.6f, 0.4f, 0.6f), 0.8f);
            cube.transform.rotation = Quaternion.Euler(0, 10, 0);
            var plate = s.Cube(m, new Vector3(-0.3f, 0.75f, 1.6f), 1f);
            plate.transform.localScale = new Vector3(0.9f, 0.04f, 0.9f);   // 一块薄板：看 Normal Bias 把它“吃掉”
            s.Sphere(Mat(s, "ShadowReceive", new Color(0.3f, 0.5f, 0.8f)), new Vector3(-0.9f, 0.35f, -0.2f), 0.7f);
            s.SunDir(20, 80);
            s.LookAt(new Vector3(2.6f, 1.7f, -2.4f), new Vector3(0.6f, 0.2f, 0.7f), 42);
        }

        // ---------------- 6.6 级联 ----------------
        static void CascadeScene(Shot s, string shader)
        {
            Floor(s, shader, 120f);
            var m = Mat(s, shader, new Color(0.85f, 0.85f, 0.8f));
            for (int z = 0; z < 12; z++)
                for (int x = -1; x <= 1; x++)
                {
                    var c = s.Cube(m, new Vector3(x * 3.2f, 0.6f, z * 4f + 1f), 1.2f);
                    c.transform.rotation = Quaternion.Euler(0, 20 + x * 15 + z * 7, 0);
                }
        }

        [BookShot("ch06-cascades", W = 640, H = 400, Panels = 3)]
        static void Cascades(Shot s)
        {
            s.Asset.shadowDistance = 60f;
            s.Asset.shadowCascadeCount = s.Panel == 0 ? 1 : s.Panel == 1 ? 2 : 4;
            SetCascadeSplit4(s, new Vector3(0.1f, 0.25f, 0.5f));
            CascadeScene(s, "CascadeDebug");
            s.SunDir(40, -35);
            s.LookAt(new Vector3(0, 4f, -6f), new Vector3(0, 0, 14f), 50);
        }

        [BookShot("ch06-cascade-quality", W = 640, H = 400, Panels = 2)]
        static void CascadeQuality(Shot s)
        {
            s.Asset.shadowDistance = 80f;
            s.Asset.shadowCascadeCount = s.Panel == 0 ? 1 : 4;
            s.AssetProp("m_MainLightShadowmapResolution", 1024);
            s.Sun.shadows = LightShadows.Hard;
            CascadeScene(s, "ShadowReceive");
            s.SunDir(40, -35);
            s.LookAt(new Vector3(0.8f, 2.2f, -2.5f), new Vector3(0, 0.3f, 3f), 50);
        }

        // ---------------- 6.7 附加光阴影 ----------------
        [BookShot("ch06-additional-shadows", W = 640, H = 420, Panels = 2)]
        static void AdditionalShadows(Shot s)
        {
            s.Background(Night);
            Floor(s, "ClassicLit");
            var m = Mat(s, "ClassicLit", new Color(0.85f, 0.85f, 0.8f));
            for (int i = 0; i < 6; i++)
            {
                float a = i / 6f * Mathf.PI * 2f + 0.3f;
                var p = s.Cylinder(m, new Vector3(Mathf.Cos(a) * 1.3f, 0.6f, 0.6f + Mathf.Sin(a) * 1.3f), 1f);
                p.transform.localScale = new Vector3(0.25f, 0.6f, 0.25f);
            }
            var point = s.Point(new Vector3(0, 0.7f, 0.6f), new Color(1f, 0.7f, 0.4f), 3f, 6f);
            var spot = s.Spot(new Vector3(-2.8f, 2.5f, -1.2f), new Vector3(0.6f, 0, 0.8f), new Color(0.5f, 0.75f, 1f), 12f, 9f, 50f);
            var k = s.Knot(Mat(s, "ClassicLit", new Color(0.3f, 0.5f, 0.85f)), new Vector3(-1.9f, 0.6f, 1.6f), 0.6f);
            point.shadows = spot.shadows = s.Panel == 0 ? LightShadows.None : LightShadows.Soft;
            s.SunDir(50, -30, 0.03f);
            s.LookAt(new Vector3(0.6f, 3.6f, -3.8f), new Vector3(0, 0, 0.8f), 45);
        }

        // ---------------- Light Layers ----------------
        // URP 会用全局设置里“已命名的渲染层”过滤灯光的层掩码（RenderingLayerUtils.ToValidRenderingLayers）。
        // 工程默认只有 Default 一层，这里只在内存里临时加一层，拍完立刻还原，不改动工程文件。
        static void WithExtraRenderingLayer(Shot s)
        {
            // UniversalRenderPipelineGlobalSettings 是 internal 类，用公开的基类接口拿到它
            var gs = GraphicsSettings.GetSettingsForRenderPipeline<UniversalRenderPipeline>();
            var so = new SerializedObject(gs);
            var names = so.FindProperty("m_RenderingLayerNames");
            var valid = so.FindProperty("m_ValidRenderingLayers");
            int oldSize = names.arraySize;
            long oldValid = valid.longValue;
            if (oldSize < 2) { names.arraySize = 2; names.GetArrayElementAtIndex(1).stringValue = "Light Layer 1"; }
            valid.longValue = oldValid | 2;
            so.ApplyModifiedPropertiesWithoutUndo();
            int frames = 0;
            System.Action<ScriptableRenderContext, Camera> restore = null;
            restore = (ctx, cam) =>
            {
                if (++frames < 3) return;          // ShotRunner 每格渲染 3 次
                RenderPipelineManager.endCameraRendering -= restore;
                var so2 = new SerializedObject(gs);
                so2.FindProperty("m_RenderingLayerNames").arraySize = oldSize;
                so2.FindProperty("m_ValidRenderingLayers").longValue = oldValid;
                so2.ApplyModifiedPropertiesWithoutUndo();
            };
            RenderPipelineManager.endCameraRendering += restore;
        }

        [BookShot("ch06-lightlayers", W = 640, H = 420, Panels = 2)]
        static void LightLayers(Shot s)
        {
            WithExtraRenderingLayer(s);
            if (s.Panel == 1) s.AssetProp("m_SupportsLightLayers", true);
            Floor(s, "ClassicLit");
            var a = s.Sphere(Mat(s, "ClassicLit", new Color(0.85f, 0.85f, 0.85f)), new Vector3(-0.9f, 0.55f, 0.2f), 1.1f);
            var b = s.Sphere(Mat(s, "ClassicLit", new Color(0.85f, 0.85f, 0.85f)), new Vector3(0.9f, 0.55f, 0.2f), 1.1f);
            b.GetComponent<MeshRenderer>().renderingLayerMask = 1u | 2u;      // 右球：Default + Light Layer 1
            a.GetComponent<MeshRenderer>().renderingLayerMask = 1u;           // 左球与地面：只有 Default
            var red = s.Point(new Vector3(0, 0.9f, -0.6f), new Color(1f, 0.25f, 0.15f), 4f, 5f);
            LightData(red).renderingLayers = 2u;                              // 红灯只照 Light Layer 1
            s.SunDir(50, -30, 0.5f);
            s.LookAt(new Vector3(0, 1.9f, -4f), new Vector3(0, 0.5f, 0.2f), 36);
        }

        // ---------------- DepthNormals 与 SSAO ----------------
        static void AddSsao(Shot s)
        {
            var t = typeof(UniversalRendererData).Assembly.GetType("UnityEngine.Rendering.Universal.ScreenSpaceAmbientOcclusion");
            var f = (ScriptableRendererFeature)ScriptableObject.CreateInstance(t);
            ResourceReloader.ReloadAllNullIn(f, UniversalRenderPipelineAsset.packagePath);
            var fi = t.GetField("m_Settings", BindingFlags.NonPublic | BindingFlags.Instance);
            object settings = fi.GetValue(f);
            settings.GetType().GetField("Radius", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(settings, 0.35f);
            settings.GetType().GetField("Intensity", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(settings, 2.5f);
            fi.SetValue(f, settings);
            f.name = "SSAO";
            s.Temp.Add(f);
            s.Renderer.rendererFeatures.Add(f);
            s.Renderer.SetDirty();
        }

        [BookShot("ch06-depthnormals-ssao", W = 640, H = 420, Panels = 2)]
        static void DepthNormalsSsao(Shot s)
        {
            AddSsao(s);
            Floor(s, "ClassicLit", 60f, new Color(0.8f, 0.8f, 0.8f), false);
            var m = Mat(s, "ClassicLit", new Color(0.85f, 0.45f, 0.25f));
            m.SetShaderPassEnabled("DepthNormalsOnly", s.Panel == 1);
            s.Knot(m, new Vector3(0, 0.75f, 0.4f), 1.0f);
            var c = s.Cube(m, new Vector3(1.4f, 0.35f, 0.2f), 0.7f);
            c.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.SunDir(60, -40, 0.6f);
            s.LookAt(new Vector3(0, 2.0f, -3.6f), new Vector3(0.3f, 0.4f, 0.4f), 40);
        }

        // ---------------- 6.9 ClassicLit ----------------
        static void HeroScene(Shot s)
        {
            var floor = Floor(s, "ClassicLit");
            floor.GetComponent<MeshRenderer>().sharedMaterial.SetFloat("_Smoothness", 0.3f);
            var knot = Mat(s, "ClassicLit", new Color(0.8f, 0.2f, 0.15f));
            knot.SetColor("_SpecColor", new Color(0.35f, 0.35f, 0.35f));
            knot.SetFloat("_Smoothness", 0.7f);
            s.Knot(knot, new Vector3(0, 0.95f, 1.0f), 0.95f);

            var sphere = Mat(s, "ClassicLit", new Color(0.2f, 0.4f, 0.75f));
            sphere.SetFloat("_Smoothness", 0.8f);
            sphere.SetColor("_SpecColor", new Color(0.3f, 0.3f, 0.3f));
            s.Sphere(sphere, new Vector3(-1.6f, 0.5f, -0.1f), 1f);

            var brick = Mat(s, "ClassicLit", Color.white);
            brick.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            brick.SetFloat("_Smoothness", 0.2f);
            brick.SetColor("_SpecColor", new Color(0.05f, 0.05f, 0.05f));
            var cube = s.Cube(brick, new Vector3(1.5f, 0.45f, -0.1f), 0.9f);
            cube.transform.rotation = Quaternion.Euler(0, -25, 0);

            var glow = Mat(s, "ClassicLit", new Color(0.1f, 0.1f, 0.1f));
            glow.SetColor("_EmissionColor", new Color(2f, 1.1f, 0.4f));
            var bulb = s.Sphere(glow, new Vector3(-0.6f, 0.2f, -0.9f), 0.3f);
            bulb.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;   // “灯泡”自己不挡光

            var warm = s.Point(new Vector3(-0.6f, 0.25f, -0.9f), new Color(1f, 0.6f, 0.25f), 2.5f, 3f);
            warm.shadows = LightShadows.Soft;
            s.Point(new Vector3(1.8f, 1.2f, 1.6f), new Color(0.3f, 0.8f, 1f), 3f, 4f);
            var spot = s.Spot(new Vector3(2.6f, 3.2f, -1.6f), new Vector3(0.2f, 0.3f, 0.9f), new Color(1f, 0.95f, 0.85f), 10f, 10f, 40f);
            spot.shadows = LightShadows.Soft;
            s.SunDir(42, -150, 0.35f);
        }

        [BookShot("ch06-classiclit", W = 960, H = 540)]
        static void ClassicLitHero(Shot s)
        {
            HeroScene(s);
            s.LookAt(new Vector3(0, 2.4f, -4.6f), new Vector3(0, 0.45f, 0.4f), 38);
        }

        [BookShot("ch06-classiclit-paths", W = 640, H = 400, Panels = 3)]
        static void ClassicLitPaths(Shot s)
        {
            s.Renderer.renderingMode = s.Panel == 0 ? RenderingMode.Forward : s.Panel == 1 ? RenderingMode.ForwardPlus : RenderingMode.Deferred;
            HeroScene(s);
            s.LookAt(new Vector3(0, 2.4f, -4.6f), new Vector3(0, 0.45f, 0.4f), 40);
        }

        [BookShot("ch06-classiclit-vs-simplelit", W = 960, H = 420)]
        static void VsSimpleLit(Shot s)
        {
            s.Background(new Color(0.10f, 0.11f, 0.13f));
            s.LookAt(new Vector3(0, 1.1f, -8f), new Vector3(0, 1.1f, 0));
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = 1.36f;
            float[] sm = { 0.1f, 0.3f, 0.5f, 0.7f, 0.9f };
            var spec = new Color(0.2f, 0.2f, 0.2f);
            s.SphereRow(5, i =>
            {
                var m = s.Mat("Universal Render Pipeline/Simple Lit");
                m.SetColor("_BaseColor", new Color(0.2f, 0.35f, 0.6f));
                m.EnableKeyword("_SPECULAR_COLOR");
                m.SetColor("_SpecColor", new Color(spec.r, spec.g, spec.b, sm[i]));   // SimpleLit 的光滑度存在 _SpecColor.a 里
                m.SetFloat("_Smoothness", sm[i]);
                return m;
            }, y: 1.7f, step: 1.15f);
            s.SphereRow(5, i =>
            {
                var m = Mat(s, "ClassicLit", new Color(0.2f, 0.35f, 0.6f));
                m.SetColor("_SpecColor", spec);
                m.SetFloat("_Smoothness", sm[i]);
                return m;
            }, y: 0.5f, step: 1.15f);
            s.SunDir(35, 25, 1.2f);
        }
    }
}
