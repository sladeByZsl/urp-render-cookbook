using System;
using Cookbook.Core;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Object = UnityEngine.Object;

namespace Cookbook.Ch23
{
    static class Shots
    {
        // ---------- 小工具 ----------
        static void AssetFloat(Shot s, string field, float v)
        {
            var so = new SerializedObject(s.Asset);
            so.FindProperty(field).floatValue = v;
            so.ApplyModifiedPropertiesWithoutUndo();
        }
        static void AssetVector3(Shot s, string field, Vector3 v)
        {
            var so = new SerializedObject(s.Asset);
            so.FindProperty(field).vector3Value = v;
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        /// 浅色网格地面：比棋盘格更容易看清阴影的浓淡和边缘
        static Texture2D s_Grid;
        static Material LightFloorMat(Shot s, Material m = null)
        {
            if (s_Grid == null)
            {
                const int n = 128;
                s_Grid = new Texture2D(n, n, TextureFormat.RGBA32, true) { name = "ch23_grid", wrapMode = TextureWrapMode.Repeat, anisoLevel = 8, hideFlags = HideFlags.DontSave };
                var px = new Color[n * n];
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        bool line = x < 2 || y < 2;
                        float v = line ? 0.55f : 0.86f;
                        px[y * n + x] = new Color(v, v, v * 0.97f, 1);
                    }
                s_Grid.SetPixels(px); s_Grid.Apply(true);
            }
            m ??= s.Lit(Color.white, 0, 0.1f);
            m.SetTexture("_BaseMap", s_Grid);
            m.SetTextureScale("_BaseMap", new Vector2(60, 60));   // 每格 1 米
            return m;
        }
        static GameObject LightFloor(Shot s, Material m = null) => s.Floor(LightFloorMat(s, m));

        /// 环境光整体缩放：默认天空环境光偏亮，阴影显得很淡
        static void Ambient(float k) => RenderSettings.ambientProbe = RenderSettings.ambientProbe * k;

        static GameObject Box(Shot s, Material m, Vector3 pos, Vector3 size, float yaw = 0)
        {
            var go = s.Cube(m, pos);
            go.transform.localScale = size;
            go.transform.rotation = Quaternion.Euler(0, yaw, 0);
            return go;
        }

        /// 本章参数对比用的“阴影测试台”：细栅栏 + 立柱 + 球 + 方块 + 纽结。主光从左侧来，影子往右铺开
        static void ShadowProps(Shot s, Func<Color, Material> mat = null)
        {
            mat ??= c => s.Lit(c, 0, 0.35f);
            var white = mat(new Color(0.9f, 0.9f, 0.88f));
            var orange = mat(new Color(0.9f, 0.45f, 0.2f));
            var blue = mat(new Color(0.25f, 0.45f, 0.85f));
            // 栅栏：一排很细的竖条，最考验阴影贴图分辨率
            for (int i = 0; i < 9; i++)
                Box(s, white, new Vector3(-2.3f + i * 0.16f, 0.6f, 1.2f), new Vector3(0.05f, 1.2f, 0.05f));
            Box(s, white, new Vector3(-1.66f, 1.22f, 1.2f), new Vector3(1.4f, 0.05f, 0.05f));
            s.Sphere(orange, new Vector3(-1.2f, 0.5f, -0.4f), 1f);
            Box(s, blue, new Vector3(0.2f, 0.35f, 0.5f), new Vector3(0.7f, 0.7f, 0.7f), 30);
            s.Knot(mat(new Color(0.4f, 0.75f, 0.45f)), new Vector3(-0.3f, 1.35f, 2.2f), 0.5f);
            var pole = s.Cylinder(white, new Vector3(-2.4f, 0.9f, -0.3f));
            pole.transform.localScale = new Vector3(0.08f, 0.9f, 0.08f);
        }

        static void PropsLight(Shot s) { s.SunDir(35, 105, 1.6f); Ambient(0.7f); }
        static void PropsCamera(Shot s) => s.LookAt(new Vector3(0.3f, 2.6f, -4.2f), new Vector3(-0.3f, 0.2f, 0.7f), 45);

        // ---------- 23.1 分辨率 ----------
        [BookShot("ch23-resolution", W = 640, H = 480, Panels = 3)]
        static void Resolution(Shot s)
        {
            int[] res = { 256, 1024, 4096 };
            s.AssetProp("m_MainLightShadowmapResolution", res[s.Panel]);
            s.AssetProp("m_SoftShadowsSupported", false);   // 关掉软阴影，锯齿看得最清楚
            s.Sun.shadows = LightShadows.Hard;
            s.Asset.shadowCascadeCount = 1;
            LightFloor(s);
            ShadowProps(s);
            PropsLight(s);
            PropsCamera(s);
        }

        // ---------- 23.1 软阴影质量 ----------
        [BookShot("ch23-softquality", W = 480, H = 400, Panels = 4)]
        static void SoftQuality(Shot s)
        {
            s.AssetProp("m_MainLightShadowmapResolution", 1024);
            s.Asset.shadowCascadeCount = 1;
            if (s.Panel == 0) s.Sun.shadows = LightShadows.Hard;
            else s.AssetProp("m_SoftShadowQuality", s.Panel);   // 1 Low / 2 Medium / 3 High
            LightFloor(s);
            ShadowProps(s);
            PropsLight(s);
            s.LookAt(new Vector3(-0.9f, 1.5f, 0.0f), new Vector3(-1.2f, 0.0f, 1.6f), 40);
        }

        // ---------- 23.1 阴影距离 ----------
        static void Colonnade(Shot s, bool lightFloor = true)
        {
            if (lightFloor) s.Floor(LightFloorMat(s), 200); else s.Floor(null, 200);
            var m = s.Lit(new Color(0.85f, 0.83f, 0.8f), 0, 0.3f);
            for (int i = 0; i < 16; i++)
            {
                float z = i * 5f;
                Box(s, m, new Vector3(-2.5f, 1.5f, z), new Vector3(0.5f, 3f, 0.5f));
                Box(s, m, new Vector3(2.5f, 1.5f, z), new Vector3(0.5f, 3f, 0.5f));
                Box(s, m, new Vector3(0, 3.1f, z), new Vector3(5.6f, 0.25f, 0.6f));
            }
            s.SunDir(35, -60, 1.5f);
            Ambient(0.7f);
            s.LookAt(new Vector3(0.4f, 1.7f, -6f), new Vector3(0, 1.0f, 20f), 50);
        }

        [BookShot("ch23-distance", W = 640, H = 420, Panels = 3)]
        static void Distance(Shot s)
        {
            float[] d = { 12, 30, 80 };
            s.Asset.shadowDistance = d[s.Panel];
            s.Asset.shadowCascadeCount = 1;
            s.Asset.cascadeBorder = 0.2f;
            Colonnade(s);
        }

        // ---------- 23.2 级联 ----------
        [BookShot("ch23-cascade-vis", W = 640, H = 420, Panels = 3)]
        static void CascadeVis(Shot s)
        {
            int[] c = { 1, 2, 4 };
            s.Asset.shadowDistance = 60;
            s.Asset.shadowCascadeCount = c[s.Panel];
            Colonnade(s);
            // 把所有物体换成级联可视化 Shader
            var dbg = s.Mat("Cookbook/Ch23/ShadowDebug");
            dbg.SetFloat("_Mode", 0);
            foreach (var r in Object.FindObjectsOfType<MeshRenderer>()) r.sharedMaterial = dbg;
        }

        [BookShot("ch23-cascade-quality", W = 640, H = 420, Panels = 3)]
        static void CascadeQuality(Shot s)
        {
            int[] c = { 1, 2, 4 };
            s.Asset.shadowDistance = 60;
            s.Asset.shadowCascadeCount = c[s.Panel];
            s.AssetProp("m_MainLightShadowmapResolution", 2048);
            Colonnade(s);
            // 近处放一排细栅栏，看近景阴影精度
            var m = s.Lit(new Color(0.9f, 0.5f, 0.25f), 0, 0.3f);
            for (int i = 0; i < 10; i++) Box(s, m, new Vector3(-1.2f + i * 0.2f, 0.45f, -2.8f), new Vector3(0.06f, 0.9f, 0.06f));
            Box(s, m, new Vector3(-0.3f, 0.92f, -2.8f), new Vector3(2.0f, 0.06f, 0.06f));
            s.LookAt(new Vector3(0.4f, 1.7f, -6f), new Vector3(-0.2f, 0.4f, -1.5f), 50);
        }

        // ---------- 23.1 Bias ----------
        static void BiasScene(Shot s)
        {
            s.AssetProp("m_MainLightShadowmapResolution", 512);
            s.AssetProp("m_SoftShadowsSupported", false);
            s.Sun.shadows = LightShadows.Hard;
            s.Asset.shadowCascadeCount = 1;
            LightFloor(s);
            var m = s.Lit(new Color(0.85f, 0.85f, 0.82f), 0, 0.3f);
            Box(s, m, new Vector3(0.5f, 0.5f, 0.6f), new Vector3(1f, 1f, 1f), 20);
            s.Sphere(s.Lit(new Color(0.9f, 0.45f, 0.2f), 0, 0.3f), new Vector3(-1.0f, 0.45f, 0.4f), 0.9f);
            for (int i = 0; i < 6; i++) Box(s, m, new Vector3(-2.4f + i * 0.14f, 0.6f, 0.9f), new Vector3(0.04f, 1.2f, 0.04f));
            // 低角度逆光：阴影朝相机方向铺开，接触处看得最清楚
            s.SunDir(18, 150, 1.6f);
            Ambient(0.7f);
            s.LookAt(new Vector3(0.0f, 1.6f, -2.8f), new Vector3(-0.5f, 0.2f, 0.4f), 48);
        }

        [BookShot("ch23-depthbias", W = 640, H = 480, Panels = 3)]
        static void DepthBias(Shot s)
        {
            float[] db = { 0f, 1f, 10f };
            s.Asset.shadowDepthBias = db[s.Panel];
            s.Asset.shadowNormalBias = 0f;
            BiasScene(s);
        }

        [BookShot("ch23-normalbias", W = 640, H = 480, Panels = 3)]
        static void NormalBias(Shot s)
        {
            float[] nb = { 0f, 1f, 4f };
            s.Asset.shadowDepthBias = 1f;
            s.Asset.shadowNormalBias = nb[s.Panel];
            BiasScene(s);
        }

        // ---------- 23.3 平面投影阴影 ----------
        static void Figure(Shot s, Material m, Vector3 o, float s1 = 1f)
        {
            // 用几个基本体拼一个“小人”：身体、头、两条胳膊，部件之间互相重叠
            var body = s.Capsule(m, o + new Vector3(0, 0.55f, 0) * s1); body.transform.localScale = new Vector3(0.55f, 0.55f, 0.55f) * s1;
            s.Sphere(m, o + new Vector3(0, 1.35f, 0) * s1, 0.42f * s1);
            var armL = s.Capsule(m, o + new Vector3(-0.38f, 0.7f, 0) * s1); armL.transform.localScale = new Vector3(0.18f, 0.35f, 0.18f) * s1; armL.transform.rotation = Quaternion.Euler(0, 0, -25);
            var armR = s.Capsule(m, o + new Vector3(0.38f, 0.7f, 0) * s1); armR.transform.localScale = new Vector3(0.18f, 0.35f, 0.18f) * s1; armR.transform.rotation = Quaternion.Euler(0, 0, 25);
        }

        [BookShot("ch23-planar", W = 640, H = 480, Panels = 3)]
        static void Planar(Shot s)
        {
            s.Sun.shadows = LightShadows.None;       // 关掉实时阴影，只看平面阴影
            LightFloor(s);
            var m = s.Mat("Cookbook/Ch23/PlanarShadow");
            m.SetColor("_BaseColor", new Color(0.95f, 0.6f, 0.3f));
            // 0：关模板（Always）  1：开模板（NotEqual）  2：开模板 + 冷色 + 更强的高度衰减
            m.SetFloat("_StencilComp", s.Panel == 0 ? (float)CompareFunction.Always : (float)CompareFunction.NotEqual);
            m.SetColor("_ShadowColor", new Color(0.05f, 0.06f, 0.1f, 0.5f));
            m.SetFloat("_ShadowFalloff", 0.15f);
            if (s.Panel == 2) { m.SetColor("_ShadowColor", new Color(0.12f, 0.14f, 0.4f, 0.7f)); m.SetFloat("_ShadowFalloff", 0.4f); }
            Figure(s, m, new Vector3(-1.0f, 0, 0.3f));
            Figure(s, m, new Vector3(0.1f, 0, 1.0f), 1.25f);
            s.SunDir(40, 115, 1.4f);
            Ambient(0.8f);
            s.LookAt(new Vector3(0.6f, 2.7f, -3.4f), new Vector3(0.3f, 0.4f, 0.8f), 45);
        }

        [BookShot("ch23-planar-limit", W = 640, H = 460, Panels = 2)]
        static void PlanarLimit(Shot s)
        {
            // 0：平面阴影   1：同一场景用阴影贴图
            s.Sun.shadows = s.Panel == 0 ? LightShadows.None : LightShadows.Soft;
            LightFloor(s);
            var m = s.Panel == 0 ? s.Mat("Cookbook/Ch23/PlanarShadow") : s.Lit(new Color(0.95f, 0.6f, 0.3f), 0, 0.4f);
            m.SetColor("_BaseColor", new Color(0.95f, 0.6f, 0.3f));
            Figure(s, m, new Vector3(-0.6f, 0, 0.2f));
            // 台阶：平面阴影只认 y = 0 的平面，会钻到台阶底下去
            var step = s.Lit(new Color(0.6f, 0.68f, 0.8f), 0, 0.3f);
            Box(s, step, new Vector3(0.9f, 0.15f, 0.6f), new Vector3(1.4f, 0.3f, 2.4f));
            Box(s, step, new Vector3(1.3f, 0.45f, 0.6f), new Vector3(0.6f, 0.3f, 2.4f));
            s.SunDir(40, 115, 1.4f);
            Ambient(0.8f);
            s.LookAt(new Vector3(0.0f, 2.8f, -3.2f), new Vector3(0.3f, 0.3f, 0.6f), 45);
        }

        // ---------- 23.4 Blob 阴影 ----------
        [BookShot("ch23-blob", W = 640, H = 480, Panels = 3)]
        static void Blob(Shot s)
        {
            s.Sun.shadows = s.Panel == 2 ? LightShadows.Soft : LightShadows.None;
            LightFloor(s);
            var blobMat = s.Mat("Cookbook/Ch23/BlobShadow");
            Color[] cols = { new Color(0.9f, 0.4f, 0.2f), new Color(0.3f, 0.6f, 0.95f), new Color(0.4f, 0.8f, 0.4f), new Color(0.95f, 0.8f, 0.3f) };
            Vector3[] pos = { new Vector3(-1.4f, 0.4f, 0.4f), new Vector3(-0.2f, 1.2f, 0.9f), new Vector3(0.9f, 0.4f, 0.1f), new Vector3(1.9f, 2.0f, 1.2f) };
            for (int i = 0; i < pos.Length; i++)
            {
                var ball = s.Sphere(s.Lit(cols[i], 0, 0.5f), pos[i], 0.8f);
                if (s.Panel == 1)
                {
                    var quad = s.Quad(blobMat, Vector3.zero);
                    quad.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
                    var blob = quad.AddComponent<BlobShadow>();
                    blob.target = ball.transform; blob.baseSize = 1.1f; blob.maxHeight = 3f;
                    blob.Apply();
                }
            }
            s.SunDir(60, -30, 1.4f);
            Ambient(0.75f);
            s.LookAt(new Vector3(0.2f, 2.4f, -4.4f), new Vector3(0.2f, 0.6f, 0.7f), 42);
        }

        // ---------- 23.6 自定义阴影颜色 ----------
        [BookShot("ch23-shadowcolor", W = 640, H = 480, Panels = 3)]
        static void ShadowColorShot(Shot s)
        {
            Material Make(Color c)
            {
                if (s.Panel == 0) return s.Lit(c, 0, 0.2f);
                var m = s.Mat("Cookbook/Ch23/ShadowColor");
                m.SetColor("_BaseColor", c);
                if (s.Panel == 1) m.SetColor("_ShadowColor", new Color(0.12f, 0.3f, 0.75f, 1));
                else { m.SetColor("_ShadowColor", new Color(0.5f, 0.25f, 0.55f, 1)); m.SetFloat("_AmbientScale", 0.55f); }
                return m;
            }
            LightFloor(s, Make(Color.white));
            s.Sphere(Make(new Color(0.95f, 0.75f, 0.55f)), new Vector3(-0.8f, 0.6f, 0.3f), 1.2f);
            Box(s, Make(new Color(0.6f, 0.8f, 0.95f)), new Vector3(0.9f, 0.45f, 0.6f), new Vector3(0.9f, 0.9f, 0.9f), 25);
            s.Knot(Make(new Color(0.95f, 0.9f, 0.6f)), new Vector3(0.2f, 1.7f, 1.6f), 0.6f);
            s.SunDir(42, 120, 1.5f);
            Ambient(0.8f);
            s.LookAt(new Vector3(0.4f, 2.5f, -3.8f), new Vector3(0.2f, 0.5f, 0.8f), 44);
        }

        // ---------- 23.7 屏幕空间阴影 ----------
        static void AddUrpScreenSpaceShadows(Shot s)
        {
            // ScreenSpaceShadows 是 internal 类，只能按类型名创建（编辑器里就是 Add Renderer Feature 菜单里的那一项）
            var type = typeof(UniversalRendererData).Assembly.GetType("UnityEngine.Rendering.Universal.ScreenSpaceShadows");
            var f = (ScriptableRendererFeature)ScriptableObject.CreateInstance(type);
            f.name = "ScreenSpaceShadows";
            s.Renderer.rendererFeatures.Add(f);
            s.Renderer.SetDirty();
        }

        [BookShot("ch23-screenspace", W = 640, H = 480, Panels = 2)]
        static void ScreenSpace(Shot s)
        {
            s.Asset.shadowCascadeCount = 4;
            AddUrpScreenSpaceShadows(s);
            LightFloor(s);
            ShadowProps(s);
            if (s.Panel == 1)
            {
                var dbg = s.Mat("Cookbook/Ch23/ShadowDebug");
                dbg.SetFloat("_Mode", 1);
                foreach (var r in Object.FindObjectsOfType<MeshRenderer>()) r.sharedMaterial = dbg;
            }
            PropsLight(s);
            PropsCamera(s);
        }

        // ---------- 23.8 抖动阴影 ----------
        [BookShot("ch23-dither", W = 640, H = 480, Panels = 3)]
        static void Dither(Shot s)
        {
            LightFloor(s);
            float[] alpha = { 0.4f, 0.4f, 0.15f };
            var m = s.Mat("Cookbook/Ch23/DitherShadow");
            m.SetColor("_BaseColor", new Color(0.3f, 0.7f, 1f, alpha[s.Panel]));
            m.SetFloat("_DitherShadow", s.Panel == 0 ? 0 : 1);
            // 左边一块玻璃板、右边一个玻璃球；前面放个不透明方块做对照
            Box(s, m, new Vector3(-1.2f, 0.8f, 0.8f), new Vector3(1.2f, 1.6f, 0.06f), 10);
            s.Sphere(m, new Vector3(0.7f, 0.7f, 0.9f), 1.2f);
            Box(s, s.Lit(new Color(0.9f, 0.5f, 0.25f), 0, 0.3f), new Vector3(-0.3f, 0.25f, 0.0f), new Vector3(0.5f, 0.5f, 0.5f), 20);
            s.SunDir(40, 160, 1.5f);
            Ambient(0.75f);
            s.LookAt(new Vector3(0.0f, 2.5f, -3.4f), new Vector3(-0.2f, 0.3f, 0.4f), 48);
        }

        // ---------- 23.9 接触阴影 ----------
        [BookShot("ch23-contact", W = 640, H = 480, Panels = 3)]
        static void Contact(Shot s)
        {
            // 低分辨率 + 大距离：模拟“阴影贴图照顾不到小物体”的常见项目设置
            s.AssetProp("m_MainLightShadowmapResolution", 512);
            s.Asset.shadowDistance = 60;
            s.Asset.shadowCascadeCount = 1;
            if (s.Panel > 0)
            {
                var f = s.Feature<ContactShadowFeature>();
                f.settings.length = 0.4f; f.settings.steps = 24; f.settings.thickness = 0.12f;
            }
            Material Make(Color c)
            {
                var m = s.Mat("Cookbook/Ch23/ContactShadowLit");
                m.SetColor("_BaseColor", c);
                m.SetFloat("_UseContact", s.Panel > 0 ? 1 : 0);
                m.SetFloat("_ShowContact", s.Panel == 2 ? 1 : 0);
                return m;
            }
            LightFloor(s, Make(Color.white));
            var rnd = new System.Random(3);
            Color[] cols = { new Color(0.9f, 0.45f, 0.2f), new Color(0.3f, 0.55f, 0.9f), new Color(0.85f, 0.85f, 0.8f), new Color(0.45f, 0.8f, 0.45f) };
            for (int i = 0; i < 16; i++)
            {
                float x = (float)rnd.NextDouble() * 2.6f - 1.5f, z = (float)rnd.NextDouble() * 1.4f - 0.5f;
                float sz = 0.06f + (float)rnd.NextDouble() * 0.12f;
                var m = Make(cols[i % cols.Length]);
                if (i % 2 == 0) s.Sphere(m, new Vector3(x, sz * 0.5f, z), sz);
                else Box(s, m, new Vector3(x, sz * 0.5f, z), Vector3.one * sz, (float)rnd.NextDouble() * 90);
            }
            var cap = s.Capsule(Make(new Color(0.9f, 0.85f, 0.75f)), new Vector3(0.9f, 0.4f, 1.1f));
            cap.transform.localScale = new Vector3(0.3f, 0.4f, 0.3f);
            s.SunDir(28, 120, 1.6f);
            Ambient(0.7f);
            s.LookAt(new Vector3(-0.1f, 1.3f, -1.9f), new Vector3(0f, 0.1f, 0.4f), 42);
        }
    }
}
