// 第 29 章配图
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch29
{
    static class Shots
    {
        [BookShot("ch29-overdraw", W = 800, H = 450, Panels = 2)]
        static void Overdraw(Shot s)
        {
            s.Floor();
            s.Cube(s.Lit(new Color(0.8f, 0.35f, 0.25f)), new Vector3(-1.8f, 0.5f, 1.2f));
            s.Sphere(s.Lit(new Color(0.25f, 0.5f, 0.85f)), new Vector3(1.6f, 0.6f, 1.5f), 1.2f);
            var wall = s.Cube(s.Lit(new Color(0.7f, 0.7f, 0.72f)), new Vector3(0, 1.2f, 3.5f));
            wall.transform.localScale = new Vector3(8f, 2.4f, 0.3f);
            // 一团“烟”：40 张互相重叠的半透明面片
            var smoke = s.Mat("Cookbook/Ch29/SoftQuad");
            smoke.SetTexture("_BaseMap", s.CoreTex("particle_soft"));
            smoke.SetColor("_BaseColor", new Color(0.32f, 0.3f, 0.3f, 0.45f));
            var rnd = new System.Random(3);
            for (int i = 0; i < 40; i++)
            {
                float r() => (float)rnd.NextDouble();
                var q = s.Quad(smoke, new Vector3(-0.2f + (r() - 0.5f) * 1.6f, 0.9f + r() * 1.0f, 0.6f + r() * 1.2f), 0.8f + r() * 1.0f);
                q.transform.rotation = Quaternion.Euler(0, 0, r() * 360f);
            }
            s.LookAt(new Vector3(0, 1.5f, -4.0f), new Vector3(0, 0.9f, 1f), 45);
            if (s.Panel == 1)
            {
                var f = s.Feature<OverdrawFeature>();
                f.settings.countMaterial = s.Mat("Cookbook/Ch29/OverdrawCount");
                f.settings.heatmapMaterial = s.Mat("Cookbook/Ch29/OverdrawHeatmap");
            }
        }

        [BookShot("ch29-mipviz", W = 800, H = 450, Panels = 2)]
        static void MipViz(Shot s)
        {
            var m = s.Mat(s.Panel == 0 ? "Universal Render Pipeline/Unlit" : "Cookbook/Ch29/MipLevelViz");
            m.SetTexture("_BaseMap", s.CoreTex("checker"));
            m.SetTextureScale("_BaseMap", new Vector2(12, 12));
            if (s.Panel == 1) m.SetFloat("_Blend", 0.8f);
            s.Floor(m, 60f);
            var wall = s.Quad(m, new Vector3(-3.2f, 1.5f, 3f), 3f);
            wall.transform.rotation = Quaternion.Euler(0, -35, 0);
            s.LookAt(new Vector3(0, 1.6f, -3f), new Vector3(0, 0.4f, 6f), 55);
        }

        [BookShot("ch29-half", W = 800, H = 450, Panels = 2)]
        static void Half(Shot s)
        {
            var origin = new Vector3(300f, 0, 300f);   // 远离世界原点 300 米
            var m = s.Mat("Cookbook/Ch29/HalfPrecisionDemo");
            m.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            m.SetFloat("_Tiling", 0.25f);
            m.SetFloat("_EmulateHalf", s.Panel);
            var plane = s.Prim(PrimitiveType.Plane, m, origin);
            plane.transform.localScale = new Vector3(4, 1, 4);
            s.Cube(m, origin + new Vector3(0.5f, 0.75f, 1.0f), 1.5f);
            s.LookAt(origin + new Vector3(0, 3.0f, -5.5f), origin + new Vector3(0, 0, 1.5f), 50);
        }
    }
}
