// 第 30 章配图：调试视图与几种“错误效果”的现场还原
using System.IO;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch30
{
    static class Shots
    {
        [BookShot("ch30-debugview", W = 480, H = 360, Panels = 4)]
        static void DebugViews(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch30/DebugView");
            m.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            m.SetTexture("_BumpMap", s.CoreTex("bricks_normal"));
            m.SetFloat("_DebugView", new[] { 0f, 1f, 2f, 3f }[s.Panel]);
            s.Sphere(m, new Vector3(-0.9f, 0.6f, 0.6f), 1.2f);
            var c = s.Cube(m, new Vector3(0.9f, 0.5f, 0.9f));
            c.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Knot(m, new Vector3(0.1f, 0.45f, -0.6f), 0.3f);
            s.SunDir(45, -50, 1.3f);
            s.LookAt(new Vector3(0, 2.0f, -3.6f), new Vector3(0, 0.5f, 0.4f), 40);
        }

        static void Props(Shot s)
        {
            s.Floor();
            s.Cube(s.Lit(new Color(0.85f, 0.3f, 0.2f)), new Vector3(-1.5f, 0.5f, 2.5f));
            s.Sphere(s.Lit(new Color(0.2f, 0.5f, 0.9f)), new Vector3(1.4f, 0.6f, 2.8f), 1.2f);
            var tall = s.Cylinder(s.Lit(new Color(0.95f, 0.8f, 0.3f)), new Vector3(0.1f, 1.0f, 3.6f));
            tall.transform.localScale = new Vector3(0.8f, 1.0f, 0.8f);
        }

        [BookShot("ch30-err-uvflip", W = 800, H = 450, Panels = 2)]
        static void UVFlip(Shot s)
        {
            Props(s);
            var glass = s.Mat("Cookbook/Ch30/ScreenUVGlass");
            glass.SetFloat("_FlipBug", s.Panel);
            var q = s.Quad(glass, new Vector3(0, 0.95f, 0.8f), 1.7f);
            q.transform.localScale = new Vector3(2.6f, 1.7f, 1);
            s.LookAt(new Vector3(0, 1.3f, -3.4f), new Vector3(0, 0.85f, 2f), 42);
        }

        // 把 PNG 重新读成一张新贴图，可以指定是否当作线性数据、是否对像素做处理，
        // 用来还原“导入设置错了”的情况（正常项目里这些是 Import Settings 的勾选项）
        static Texture2D Reload(Shot s, string core, bool linear, System.Func<Color32, Color32> fn = null)
        {
            var src = new Texture2D(2, 2);
            src.LoadImage(File.ReadAllBytes("Assets/Cookbook/_Core/Textures/" + core + ".png"));
            var px = src.GetPixels32();
            if (fn != null) for (int i = 0; i < px.Length; i++) px[i] = fn(px[i]);
            var t = new Texture2D(src.width, src.height, TextureFormat.RGBA32, true, linear) { wrapMode = TextureWrapMode.Repeat, anisoLevel = 4 };
            t.SetPixels32(px);
            t.Apply(true);
            Object.DestroyImmediate(src);
            s.Temp.Add(t);
            return t;
        }

        [BookShot("ch30-err-gamma", W = 640, H = 420, Panels = 3)]
        static void Gamma(Shot s)
        {
            s.Floor();
            var bricks = s.Lit(Color.white, 0, 0.3f);
            // 面板 1：颜色贴图的 sRGB 勾选被去掉，GPU 不再做 sRGB→线性解码
            bricks.SetTexture("_BaseMap", s.Panel == 1 ? Reload(s, "bricks_albedo", true) : s.CoreTex("bricks_albedo"));
            var metal = s.Lit(Color.white, 0, 0.5f);
            metal.SetTexture("_BaseMap", s.Panel == 1 ? Reload(s, "paintedmetal_albedo", true) : s.CoreTex("paintedmetal_albedo"));
            s.Cube(bricks, new Vector3(-0.9f, 0.6f, 0.8f), 1.2f);
            s.Sphere(metal, new Vector3(0.9f, 0.6f, 0.6f), 1.2f);
            // 一排纯色小球
            var cols = new[] { new Color(0.8f, 0.2f, 0.15f), new Color(0.95f, 0.75f, 0.2f), new Color(0.3f, 0.7f, 0.35f), new Color(0.2f, 0.4f, 0.85f), new Color(0.5f, 0.5f, 0.5f) };
            for (int i = 0; i < cols.Length; i++)
            {
                var m = s.Lit(Color.white, 0, 0.4f);
                m.SetColor("_BaseColor", cols[i]);
                s.Sphere(m, new Vector3(-1.6f + i * 0.8f, 0.3f, -0.6f), 0.55f);
            }
            s.LookAt(new Vector3(0, 1.9f, -3.6f), new Vector3(0, 0.5f, 0.4f), 42);
            // 面板 2：自定义后处理里多做了一次 Gamma 校正
            if (s.Panel == 2)
            {
                var f = s.Feature<FullscreenDebugFeature>();
                f.settings.material = s.Mat("Cookbook/Ch30/ManualGamma");
                f.settings.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            }
        }

        [BookShot("ch30-err-normal", W = 640, H = 420, Panels = 3)]
        static void NormalMap(Shot s)
        {
            s.Floor();
            Texture2D bump;
            if (s.Panel == 0) bump = s.CoreTex("bricks_normal");                        // 正确：Texture Type = Normal map
            else if (s.Panel == 1) bump = Reload(s, "bricks_normal", false);             // 错误：当成普通 sRGB 颜色贴图
            else bump = Reload(s, "bricks_normal", true, c => new Color32(c.r, (byte)(255 - c.g), c.b, c.a)); // 错误：G 通道方向相反
            var m = s.Lit(new Color(0.85f, 0.85f, 0.85f), 0, 0.45f);
            m.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            m.SetTexture("_BumpMap", bump);
            m.EnableKeyword("_NORMALMAP");
            var wall = s.Quad(m, new Vector3(0, 1.1f, 0.8f), 2.2f);
            wall.transform.rotation = Quaternion.Euler(0, 0, 0);
            s.Sphere(m, new Vector3(1.6f, 0.55f, 0.2f), 1.1f);
            s.Sphere(m, new Vector3(-1.6f, 0.55f, 0.2f), 1.1f);
            s.SunDir(38, 15, 1.6f);     // 从上方偏右掠射，砖缝的上下边缘最明显（G 通道翻转时上下明暗颠倒）
            s.LookAt(new Vector3(0, 1.3f, -3.4f), new Vector3(0, 0.9f, 0.6f), 45);
        }

        [BookShot("ch30-firefly", W = 800, H = 450, Panels = 2, Hdr = true)]
        static void Firefly(Shot s)
        {
            Props(s);
            var m = s.Mat("Cookbook/Ch30/FireflySource");
            m.SetColor("_BaseColor", new Color(0.45f, 0.47f, 0.52f));
            m.SetFloat("_Fix", s.Panel);
            s.Sphere(m, new Vector3(-0.2f, 0.75f, 1.0f), 1.5f);
            s.LookAt(new Vector3(0, 1.4f, -2.6f), new Vector3(-0.1f, 0.8f, 1.2f), 42);
            var bloom = s.Post().Add<Bloom>();
            bloom.intensity.Override(1.5f);
            bloom.threshold.Override(0.85f);
            bloom.scatter.Override(0.75f);
        }

        [BookShot("ch30-nan", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void NaN(Shot s)
        {
            Props(s);
            var m = s.Mat("Cookbook/Ch30/NaNSource");
            m.SetColor("_BaseColor", new Color(0.75f, 0.75f, 0.78f));
            s.Sphere(m, new Vector3(-0.2f, 0.75f, 1.0f), 1.5f);
            s.LookAt(new Vector3(0, 1.5f, -3.4f), new Vector3(0, 0.8f, 1.5f), 45);
            if (s.Panel == 1)
            {
                var f = s.Feature<FullscreenDebugFeature>();
                f.settings.material = s.Mat("Cookbook/Ch30/PixelValidator");
            }
            else
            {
                var bloom = s.Post().Add<Bloom>();
                bloom.intensity.Override(1.0f);
                bloom.threshold.Override(1.0f);
            }
            s.CamData.stopNaN = s.Panel == 2;
            Shader.SetGlobalInteger("_NaNBits", 0x7FC00000);   // NaN 的位模式，运行时传入
            s.Asset.msaaSampleCount = 1;
        }
    }
}
