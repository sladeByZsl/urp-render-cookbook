// 第 4 章配图：正交相机正对一张铺满画面的面片，直接看 Shader 的输出
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch04
{
    static class Shots
    {
        static readonly Color Bg = new Color(0.08f, 0.10f, 0.12f);

        static void Ortho(Shot s, Color bg)
        {
            s.Background(bg);
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = 0.5f;
            s.Cam.transform.position = new Vector3(0, 0, -2);
            s.Cam.transform.rotation = Quaternion.identity;
        }

        static GameObject Flat(Shot s, Material m, Vector3 pos, Vector2 size)
        {
            var q = s.Quad(m, pos, 1f);
            q.transform.localScale = new Vector3(size.x, size.y, 1);
            return q;
        }

        static GameObject Full(Shot s, Material m)
        {
            Ortho(s, Color.black);
            return Flat(s, m, Vector3.zero, Vector2.one);
        }

        [BookShot("ch04-plot", W = 420, H = 420, Panels = 3)]
        static void Plot(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/FunctionPlot");
            m.SetFloat("_Mode", s.Panel);
            Full(s, m);
        }

        [BookShot("ch04-patterns", W = 400, H = 400, Panels = 3)]
        static void Patterns(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/Patterns");
            m.SetFloat("_Pattern", s.Panel);
            if (s.Panel == 0) { m.SetFloat("_Scale", 8); }
            if (s.Panel == 1) { m.SetFloat("_Scale", 9); m.SetFloat("_Angle", 30); m.SetFloat("_Duty", 0.45f); m.SetColor("_ColorA", new Color(0.91f, 0.45f, 0.23f)); }
            if (s.Panel == 2) { m.SetFloat("_Scale", 7); m.SetFloat("_Duty", 0.62f); m.SetFloat("_Angle", 0); m.SetColor("_ColorA", new Color(0.18f, 0.49f, 0.34f)); }
            Full(s, m);
        }

        [BookShot("ch04-progress", W = 420, H = 420, Panels = 3)]
        static void Progress(Shot s)
        {
            Ortho(s, Bg);
            var ring = s.Mat("Cookbook/Ch04/RingProgress");
            ring.SetFloat("_Progress", new[] { 0.25f, 0.6f, 0.92f }[s.Panel]);
            ring.SetColor("_BgColor", Bg);
            Flat(s, ring, new Vector3(0, 0.12f, 0), new Vector2(0.66f, 0.66f));

            var bar = s.Mat("Cookbook/Ch04/HealthBar");
            bar.SetFloat("_Health", new[] { 0.85f, 0.5f, 0.18f }[s.Panel]);
            bar.SetFloat("_Trail", new[] { 0.93f, 0.68f, 0.42f }[s.Panel]);
            bar.SetFloat("_Aspect", 6f);
            bar.SetFloat("_FlashPhase", Mathf.PI * 0.5f);
            bar.SetColor("_BgColor", Bg);
            Flat(s, bar, new Vector3(0, -0.34f, 0), new Vector2(0.84f, 0.14f));
        }

        [BookShot("ch04-polar", W = 400, H = 400, Panels = 3)]
        static void Polar(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/Polar");
            m.SetFloat("_Mode", s.Panel);
            m.SetFloat("_Speed", 0);
            m.SetFloat("_Count", new[] { 6f, 4f, 14f }[s.Panel]);
            m.SetFloat("_Angle", s.Panel == 0 ? 90f : 0f);
            if (s.Panel == 2) { m.SetColor("_ColorA", new Color(0.95f, 0.62f, 0.25f)); m.SetColor("_ColorB", new Color(0.86f, 0.36f, 0.18f)); }
            Full(s, m);
        }

        [BookShot("ch04-noise", W = 360, H = 360, Panels = 4)]
        static void Noise(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/Noise");
            m.SetFloat("_Mode", s.Panel);
            m.SetFloat("_Scale", 6);
            Full(s, m);
        }

        [BookShot("ch04-voronoi", W = 400, H = 400, Panels = 3)]
        static void Voronoi(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/Voronoi");
            m.SetFloat("_Mode", s.Panel);
            m.SetFloat("_Scale", 5);
            m.SetFloat("_Speed", 0);
            Full(s, m);
        }

        [BookShot("ch04-fbm", W = 400, H = 400, Panels = 3)]
        static void Fbm(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/FbmClouds");
            m.SetFloat("_Octaves", new[] { 1f, 3f, 8f }[s.Panel]);
            m.SetVector("_Wind", Vector4.zero);
            Full(s, m);
        }

        [BookShot("ch04-warp", W = 400, H = 400, Panels = 3)]
        static void Warp(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/DomainWarp");
            m.SetFloat("_Levels", s.Panel);
            m.SetFloat("_Speed", 0);
            Full(s, m);
        }

        [BookShot("ch04-sdf", W = 360, H = 360, Panels = 4)]
        static void Sdf(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/SDFIcon");
            m.SetFloat("_Mode", s.Panel);
            Full(s, m);
        }

        [BookShot("ch04-bayer", W = 360, H = 360, Panels = 4)]
        static void Bayer(Shot s)
        {
            var m = s.Mat("Cookbook/Ch04/BayerDither");
            m.SetFloat("_Mode", new[] { 0f, 2f, 3f, 2f }[s.Panel]);
            m.SetFloat("_Levels", s.Panel == 3 ? 4 : 2);
            m.SetFloat("_Resolution", 96);
            Full(s, m);
        }
    }
}
