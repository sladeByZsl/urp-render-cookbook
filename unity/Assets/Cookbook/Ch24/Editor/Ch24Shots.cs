using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch24
{
    // 本章所有效果图都由“与 Shader Graph 等价的手写 Shader”渲染（见各 *Equivalent.shader）
    static class Shots
    {
        static Texture2D s_Grid;
        static Material LightFloor(Shot s)
        {
            if (s_Grid == null)
            {
                const int n = 128;
                s_Grid = new Texture2D(n, n, TextureFormat.RGBA32, true) { name = "ch24_grid", wrapMode = TextureWrapMode.Repeat, anisoLevel = 8, hideFlags = HideFlags.DontSave };
                var px = new Color[n * n];
                for (int y = 0; y < n; y++)
                    for (int x = 0; x < n; x++)
                    {
                        float v = (x < 2 || y < 2) ? 0.55f : 0.82f;
                        px[y * n + x] = new Color(v, v, v * 0.97f, 1);
                    }
                s_Grid.SetPixels(px); s_Grid.Apply(true);
            }
            var m = s.Lit(Color.white, 0, 0.1f);
            m.SetTexture("_BaseMap", s_Grid);
            m.SetTextureScale("_BaseMap", new Vector2(60, 60));
            s.Floor(m);
            return m;
        }

        static void Ambient(float k) => RenderSettings.ambientProbe = RenderSettings.ambientProbe * k;

        static Material Toon(Shot s, Color c, float steps = 3, bool addLights = true)
        {
            var m = s.Mat("Cookbook/Ch24/SGToonEquivalent");
            m.SetColor("_BaseColor", c);
            m.SetFloat("_Steps", steps);
            m.SetFloat("_AddLights", addLights ? 1 : 0);
            return m;
        }

        static void ToonScene(Shot s, System.Func<Color, Material> mat)
        {
            LightFloor(s);
            s.Sphere(mat(new Color(0.95f, 0.6f, 0.45f)), new Vector3(-1.1f, 0.6f, 0.4f), 1.2f);
            s.Knot(mat(new Color(0.55f, 0.75f, 0.95f)), new Vector3(0.6f, 0.95f, 0.6f), 0.75f);
            var cap = s.Capsule(mat(new Color(0.7f, 0.9f, 0.55f)), new Vector3(1.9f, 0.6f, 1.4f));
            cap.transform.localScale = new Vector3(0.6f, 0.6f, 0.6f);
            s.SunDir(35, 70, 1.3f);
            Ambient(0.8f);
            s.LookAt(new Vector3(0.3f, 2.0f, -3.8f), new Vector3(0.3f, 0.6f, 0.7f), 42);
        }

        [BookShot("ch24-toon", W = 640, H = 480, Panels = 3)]
        static void ToonShot(Shot s)
        {
            // 0：两级色阶  1：三级色阶 + 边缘光  2：再加两盏附加点光
            float steps = s.Panel == 0 ? 2 : 3;
            ToonScene(s, c =>
            {
                var m = Toon(s, c, steps, s.Panel == 2);
                if (s.Panel == 0) m.SetColor("_RimColor", Color.black);
                if (s.Panel == 1) m.SetFloat("_UseHalf", 1);   // 顺便验证 _half 版本的结果一致
                return m;
            });
            if (s.Panel == 2)
            {
                s.Point(new Vector3(-0.1f, 0.6f, -0.3f), new Color(1f, 0.3f, 0.55f), 1.6f, 2.2f);
                s.Point(new Vector3(1.5f, 1.5f, 0.3f), new Color(0.3f, 0.75f, 1f), 1.6f, 2.2f);
            }
        }

        [BookShot("ch24-preview", W = 640, H = 480, Panels = 2)]
        static void Preview(Shot s)
        {
            // 0：SHADERGRAPH_PREVIEW 分支（固定光向、无阴影）  1：场景中的真实结果
            LightFloor(s);
            var m = Toon(s, new Color(0.95f, 0.6f, 0.45f), 3, false);
            if (s.Panel == 0) m.EnableKeyword("SHADERGRAPH_PREVIEW");
            s.Sphere(m, new Vector3(0, 0.8f, 0.3f), 1.6f);
            var post = s.Cylinder(s.Lit(new Color(0.85f, 0.85f, 0.8f), 0, 0.3f), new Vector3(-1.3f, 1.2f, -0.4f));
            post.transform.localScale = new Vector3(0.25f, 1.2f, 0.25f);
            s.SunDir(30, 60, 1.3f);   // 场景主光从右后方来，与预览分支的固定光向明显不同
            Ambient(0.8f);
            s.LookAt(new Vector3(0, 1.6f, -3.6f), new Vector3(0, 0.75f, 0.3f), 42);
        }

        [BookShot("ch24-dissolve", W = 640, H = 480, Panels = 3, Hdr = true)]
        static void Dissolve(Shot s)
        {
            float[] p = { 0.15f, 0.45f, 0.75f };
            LightFloor(s);
            var m = s.Mat("Cookbook/Ch24/SGDissolveEquivalent");
            m.SetTexture("_NoiseMap", s.CoreTex("noise_fbm"));
            m.SetFloat("_Progress", p[s.Panel]);
            m.SetFloat("_EdgeWidth", 0.12f);
            m.SetVector("_EdgeColor", new Vector4(4f, 0.9f, 0.12f, 1f));
            s.Knot(m, new Vector3(0, 1.0f, 0.4f), 0.85f);
            var prof = s.Post();
            var bloom = prof.Add<Bloom>(); bloom.intensity.Override(1.2f); bloom.threshold.Override(1.0f);
            var tm = prof.Add<Tonemapping>(); tm.mode.Override(TonemappingMode.Neutral);
            s.SunDir(45, -35, 1.4f);
            Ambient(0.8f);
            s.LookAt(new Vector3(0, 1.8f, -3.4f), new Vector3(0, 0.85f, 0.4f), 40);
        }

        [BookShot("ch24-keywords", W = 640, H = 480, Panels = 3)]
        static void Keywords(Shot s)
        {
            string[] kw = { "_PATTERN_STRIPES", "_PATTERN_DOTS", "_PATTERN_CHECKER" };
            LightFloor(s);
            var m = s.Mat("Cookbook/Ch24/SGKeywordEquivalent");
            m.SetFloat("_PATTERN", s.Panel);
            // 用代码建的材质要手动开关键字（Inspector 上改才会自动同步），而且要先关掉同组的其他关键字
            foreach (var k in kw) m.DisableKeyword(k);
            m.EnableKeyword(kw[s.Panel]);
            if (s.Panel == 2) { m.SetFloat("_USE_RIM", 1); m.EnableKeyword("_USE_RIM_ON"); }
            s.Sphere(m, new Vector3(-0.7f, 0.65f, 0.4f), 1.3f);
            var c = s.Cube(m, new Vector3(0.9f, 0.5f, 0.6f)); c.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.SunDir(45, -35, 1.3f);
            s.LookAt(new Vector3(0.1f, 1.7f, -3.2f), new Vector3(0.1f, 0.55f, 0.5f), 40);
        }
    }
}
