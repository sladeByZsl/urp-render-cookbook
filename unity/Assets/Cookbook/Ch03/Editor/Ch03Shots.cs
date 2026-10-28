// 第 3 章配图
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch03
{
    static class Shots
    {
        // ---------- 程序生成的辅助贴图 ----------
        static Texture2D s_Dots, s_Fence;

        /// RGB：暖色格子；A：每格中心一个由内向外递减的圆形渐变（中心 1，边缘 0）
        static Texture2D DotsTex()
        {
            if (s_Dots != null) return s_Dots;
            const int N = 256, cells = 4;
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true, false) { name = "ch03_dots", hideFlags = HideFlags.DontSave, wrapMode = TextureWrapMode.Repeat };
            var px = new Color[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = (x + 0.5f) / N * cells, v = (y + 0.5f) / N * cells;
                    float fu = u - Mathf.Floor(u) - 0.5f, fv = v - Mathf.Floor(v) - 0.5f;
                    float d = Mathf.Sqrt(fu * fu + fv * fv) / 0.5f;          // 0 中心 … 1 内切圆边
                    float a = Mathf.Clamp01(1f - d);
                    int ci = ((int)Mathf.Floor(u) + (int)Mathf.Floor(v)) & 1;
                    Color c = ci == 0 ? new Color(0.95f, 0.62f, 0.25f) : new Color(0.25f, 0.6f, 0.85f);
                    c = Color.Lerp(c * 0.55f, c, a);
                    c.a = a;
                    px[y * N + x] = c;
                }
            t.SetPixels(px); t.Apply(true);
            return s_Dots = t;
        }

        /// 镂空栅栏：竖条 + 横条，条上 alpha=1，空隙 alpha=0
        static Texture2D FenceTex()
        {
            if (s_Fence != null) return s_Fence;
            const int N = 256;
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true, false) { name = "ch03_fence", hideFlags = HideFlags.DontSave, wrapMode = TextureWrapMode.Repeat };
            var px = new Color[N * N];
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = (x + 0.5f) / N * 4f, v = (y + 0.5f) / N * 4f;
                    float fu = u - Mathf.Floor(u), fv = v - Mathf.Floor(v);
                    bool bar = fu < 0.28f || fv < 0.28f;
                    float wood = 0.75f + 0.25f * Mathf.Sin(v * 37f + Mathf.Sin(u * 9f) * 2f);
                    var c = new Color(0.62f, 0.42f, 0.25f) * wood;
                    c.a = bar ? 1f : 0f;
                    px[y * N + x] = c;
                }
            t.SetPixels(px); t.Apply(true);
            return s_Fence = t;
        }

        /// 复制一个网格并按位置刷上顶点色（色相绕 Y 轴变化，亮度随高度变化）
        static Mesh PaintedCopy(Mesh src, float hueOffset = 0f)
        {
            var m = Object.Instantiate(src);
            var v = m.vertices;
            var b = m.bounds;
            var cols = new Color[v.Length];
            for (int i = 0; i < v.Length; i++)
            {
                float hue = Mathf.Repeat(Mathf.Atan2(v[i].z, v[i].x) / (2 * Mathf.PI) + hueOffset, 1f);
                float h01 = Mathf.InverseLerp(b.min.y, b.max.y, v[i].y);
                cols[i] = Color.HSVToRGB(hue, 0.75f, Mathf.Lerp(0.45f, 1f, h01));
            }
            m.colors = cols;
            return m;
        }

        static Mesh PrimMesh(PrimitiveType t)
        {
            var go = GameObject.CreatePrimitive(t);
            var mesh = go.GetComponent<MeshFilter>().sharedMesh;
            Object.DestroyImmediate(go);
            return mesh;
        }

        // ---------- 图 3-x ----------

        [BookShot("ch03-solidcolor", W = 960, H = 420)]
        static void SolidColorShot(Shot s)
        {
            s.Floor();
            Material Solid(Color c) { var m = s.Mat("Cookbook/Ch03/SolidColor"); m.SetColor("_BaseColor", c); return m; }
            s.Sphere(Solid(new Color(0.95f, 0.45f, 0.15f)), new Vector3(-1.9f, 0.5f, 0), 1f);
            var cube = s.Cube(Solid(new Color(0.2f, 0.55f, 0.85f)), new Vector3(-0.6f, 0.45f, 0.1f), 0.9f);
            cube.transform.rotation = Quaternion.Euler(0, 35, 0);
            s.Knot(Solid(new Color(0.35f, 0.75f, 0.4f)), new Vector3(0.75f, 0.62f, 0.1f), 0.75f);
            // 对照：URP 自带 Lit 的同色球
            s.Sphere(s.Lit(new Color(0.95f, 0.45f, 0.15f), 0, 0.5f), new Vector3(2.05f, 0.5f, 0), 1f);
            s.LookAt(new Vector3(0, 1.6f, -5.2f), new Vector3(0.05f, 0.45f, 0), 35);
        }

        [BookShot("ch03-texture", W = 640, H = 440, Panels = 3)]
        static void TextureShot(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch03/Textured");
            m.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            if (s.Panel == 1) m.SetTextureScale("_BaseMap", new Vector2(2, 2));
            if (s.Panel == 2) { m.SetTextureScale("_BaseMap", new Vector2(1, 1)); m.SetTextureOffset("_BaseMap", new Vector2(0.5f, 0.25f)); }
            var cube = s.Cube(m, new Vector3(-0.65f, 0.55f, 0), 1.1f);
            cube.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Sphere(m, new Vector3(0.75f, 0.55f, 0), 1.1f);
            s.LookAt(new Vector3(0, 1.7f, -3.9f), new Vector3(0.05f, 0.5f, 0), 38);
        }

        [BookShot("ch03-vertexcolor", W = 640, H = 440, Panels = 3)]
        static void VertexColorShot(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch03/VertexColor");
            m.SetFloat("_VertexColorStrength", s.Panel == 0 ? 0f : 1f);
            m.SetTexture("_BaseMap", s.Panel == 2 ? s.CoreTex("checker") : Texture2D.whiteTexture);
            if (s.Panel == 2) m.SetTextureScale("_BaseMap", new Vector2(4, 4));
            s.MeshObj(PaintedCopy(PrimMesh(PrimitiveType.Sphere)), m, new Vector3(-0.7f, 0.55f, 0), 1.1f, "PaintedSphere");
            var knot = Meshes.TorusKnot();
            s.MeshObj(PaintedCopy(knot, 0.3f), m, new Vector3(0.75f, 0.62f, 0.1f), 0.72f, "PaintedKnot");
            s.LookAt(new Vector3(0, 1.6f, -3.9f), new Vector3(0.05f, 0.5f, 0), 38);
        }

        [BookShot("ch03-alphaclip", W = 640, H = 440, Panels = 3)]
        static void AlphaClipShot(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch03/AlphaClip");
            m.SetTexture("_BaseMap", DotsTex());
            m.SetFloat("_Cutoff", new[] { 0.15f, 0.5f, 0.8f }[s.Panel]);
            var q = s.Quad(m, new Vector3(-0.75f, 0.65f, 0.2f), 1.25f);
            q.transform.rotation = Quaternion.Euler(0, -15, 0);
            s.Sphere(m, new Vector3(0.75f, 0.6f, 0), 1.15f);
            s.Background(new Color(0.16f, 0.18f, 0.2f));
            s.LookAt(new Vector3(0, 1.5f, -3.8f), new Vector3(0, 0.6f, 0), 38);
        }

        [BookShot("ch03-fog", W = 960, H = 420, Panels = 2)]
        static void FogShot(Shot s)
        {
            var fogCol = new Color(0.62f, 0.68f, 0.75f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogStartDistance = 3f;
            RenderSettings.fogEndDistance = 26f;
            RenderSettings.fogColor = fogCol;
            s.Floor(null, 120f);
            s.Background(fogCol);
            var m = s.Mat(s.Panel == 0 ? "Cookbook/Ch03/AlphaClip" : "Cookbook/Ch03/Fog");
            m.SetColor("_BaseColor", new Color(0.85f, 0.35f, 0.15f));
            m.SetFloat("_Cull", 2);
            for (int i = 0; i < 9; i++)
            {
                float z = i * 3f;
                foreach (var x in new[] { -1.6f, 1.6f })
                {
                    var c = s.Cube(m, new Vector3(x, 1.2f, z), 1f);
                    c.transform.localScale = new Vector3(0.6f, 2.4f, 0.6f);
                }
            }
            s.LookAt(new Vector3(0, 1.7f, -4.5f), new Vector3(0, 1.0f, 10f), 50);
        }

        [BookShot("ch03-batcher", W = 960, H = 400)]
        static void BatcherShot(Shot s)
        {
            SRPBatcherCheck.LogChapter();   // 顺便把本章所有 Shader 的兼容性打印到日志（正文表格据此填写）
            s.Floor();
            for (int z = 0; z < 5; z++)
                for (int x = 0; x < 12; x++)
                {
                    var m = s.Mat("Cookbook/Ch03/SRPBatcher");    // 每个物体一份独立材质
                    m.SetColor("_BaseColor", Color.HSVToRGB((x / 12f + z * 0.07f) % 1f, 0.65f, 0.95f));
                    var c = s.Cube(m, new Vector3((x - 5.5f) * 0.62f, 0.22f, z * 0.62f), 0.42f);
                    c.transform.rotation = Quaternion.Euler(0, x * 13 + z * 21, 0);
                }
            s.LookAt(new Vector3(0, 3.0f, -5.0f), new Vector3(0, 0.1f, 1.3f), 42);
        }

        [BookShot("ch03-shadowcaster", W = 640, H = 440, Panels = 2)]
        static void ShadowCasterShot(Shot s)
        {
            s.Floor();
            var m = s.Mat(s.Panel == 0 ? "Cookbook/Ch03/SRPBatcher" : "Cookbook/Ch03/ShadowDepth");
            m.SetTexture("_BaseMap", FenceTex());
            m.SetFloat("_Cull", 0);
            var q = s.Quad(m, new Vector3(-0.55f, 0.75f, 0.3f), 1.4f);
            q.transform.rotation = Quaternion.Euler(0, -25, 0);
            var m2 = s.Mat(s.Panel == 0 ? "Cookbook/Ch03/SRPBatcher" : "Cookbook/Ch03/ShadowDepth");
            m2.SetColor("_BaseColor", new Color(0.3f, 0.65f, 0.9f));
            s.Sphere(m2, new Vector3(0.95f, 0.45f, -0.2f), 0.9f);
            s.SunDir(42, -50, 1.4f);
            s.LookAt(new Vector3(0.3f, 1.8f, -3.9f), new Vector3(0.1f, 0.45f, 0.3f), 40);
        }

        [BookShot("ch03-depthonly", W = 640, H = 440, Panels = 2)]
        static void DepthOnlyShot(Shot s)
        {
            // 用一个 Renderer Feature 触发深度预渲染（Depth Prepass），这时只有带 DepthOnly Pass 的物体会被写进深度图
            s.Feature<DepthPrepassFeature>();
            s.Floor();
            var a = s.Mat("Cookbook/Ch03/SRPBatcher"); a.SetColor("_BaseColor", new Color(0.95f, 0.5f, 0.2f));
            var b = s.Mat("Cookbook/Ch03/ShadowDepth"); b.SetColor("_BaseColor", new Color(0.3f, 0.65f, 0.9f));
            s.Sphere(a, new Vector3(-0.75f, 0.55f, 0), 1.1f);
            s.Sphere(b, new Vector3(0.75f, 0.55f, 0), 1.1f);
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.55f, 0), 35);
            if (s.Panel == 1)
            {
                // 贴在相机近处、铺满画面的面片，显示深度图
                var dv = s.Mat("Cookbook/Ch03/Debug/DepthView");
                dv.SetFloat("_Range", 9f);
                var q = s.Quad(dv, Vector3.zero, 1f);
                q.transform.SetParent(s.Cam.transform, false);
                q.transform.localPosition = new Vector3(0, 0, 0.5f);
                float h = 2f * 0.5f * Mathf.Tan(35f * 0.5f * Mathf.Deg2Rad) * 1.05f;
                q.transform.localScale = new Vector3(h * 640f / 440f, h, 1);
            }
        }

        [BookShot("ch03-keywords", W = 640, H = 440, Panels = 3)]
        static void KeywordsShot(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch03/Keywords");
            m.SetTexture("_BaseMap", DotsTex());
            if (s.Panel >= 1) { m.SetFloat("_UseVertexColor", 1); m.EnableKeyword("_VERTEX_COLOR_ON"); }
            if (s.Panel == 2)
            {
                m.SetFloat("_AlphaClip", 1); m.EnableKeyword("_ALPHATEST_ON");
                m.SetFloat("_Cutoff", 0.35f);
                m.SetFloat("_UVSource", 1); m.DisableKeyword("_UVSOURCE_MESH"); m.EnableKeyword("_UVSOURCE_WORLDXZ");   // new Material 会按默认值自动开 _UVSOURCE_MESH，要先关掉
                m.SetFloat("_WorldUVScale", 0.9f);
                m.SetFloat("_Cull", 0);
                m.renderQueue = (int)RenderQueue.AlphaTest;
            }
            else m.EnableKeyword("_UVSOURCE_MESH");
            var cubeMesh = PaintedCopy(PrimMesh(PrimitiveType.Cube), 0.1f);
            var g1 = s.MeshObj(cubeMesh, m, new Vector3(-0.8f, 0.35f, 0.1f), 1f, "Box1");
            g1.transform.localScale = new Vector3(1.0f, 0.7f, 1.0f);
            var g2 = s.MeshObj(Object.Instantiate(cubeMesh), m, new Vector3(0.25f, 0.25f, 0.1f), 1f, "Box2");
            g2.transform.localScale = new Vector3(1.1f, 0.5f, 1.0f);
            s.MeshObj(PaintedCopy(PrimMesh(PrimitiveType.Sphere), 0.5f), m, new Vector3(1.2f, 0.45f, -0.1f), 0.9f, "Ball");
            s.LookAt(new Vector3(0, 2.2f, -3.7f), new Vector3(0.1f, 0.3f, 0.2f), 40);
        }

        [BookShot("ch03-scroll", W = 640, H = 400, Panels = 3)]
        static void ScrollShot(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch03/ScrollMigrated");
            m.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            m.SetTextureScale("_BaseMap", new Vector2(3, 1));
            m.SetVector("_ScrollSpeed", Vector4.zero);
            m.SetVector("_ScrollOffset", new Vector4(s.Panel * 0.25f, 0, 0, 0));
            var c = s.Cylinder(m, new Vector3(0, 0.6f, 0), 1f);
            c.transform.localScale = new Vector3(1.0f, 0.6f, 1.0f);
            s.LookAt(new Vector3(0, 1.5f, -3.2f), new Vector3(0, 0.55f, 0), 38);
        }

        [BookShot("ch03-pink", W = 960, H = 380)]
        static void PinkShot(Shot s)
        {
            s.Floor();
            // 左：Built-in 管线的 Standard 材质，在 URP 下没有可用的 Pass → 洋红色
            var builtin = new Material(Shader.Find("Standard"));
            builtin.SetColor("_Color", new Color(0.3f, 0.6f, 0.9f));
            s.Sphere(builtin, new Vector3(-1.3f, 0.55f, 0), 1.1f);
            // 右：同色的 URP Lit
            s.Sphere(s.Lit(new Color(0.3f, 0.6f, 0.9f), 0, 0.5f), new Vector3(1.3f, 0.55f, 0), 1.1f);
            s.LookAt(new Vector3(0, 1.4f, -4.6f), new Vector3(0, 0.55f, 0), 35);
            s.Temp.Add(builtin);
        }

        [BookShot("ch03-deferred", W = 640, H = 360, Panels = 2)]
        static void DeferredShot(Shot s)
        {
            // 左：Forward+；右：Deferred。左球 LightMode=UniversalForward，右球 LightMode=UniversalForwardOnly
            s.Renderer.renderingMode = s.Panel == 0 ? RenderingMode.ForwardPlus : RenderingMode.Deferred;
            s.Floor();
            var a = s.Mat("Cookbook/Ch03/SolidColor");
            s.Sphere(a, new Vector3(-0.65f, 0.55f, 0), 1.1f);
            var b = s.Mat("Cookbook/Ch03/Keywords");
            b.SetColor("_BaseColor", new Color(0.3f, 0.65f, 0.9f));
            b.EnableKeyword("_UVSOURCE_MESH");
            s.Sphere(b, new Vector3(0.65f, 0.55f, 0), 1.1f);
            s.LookAt(new Vector3(0, 1.4f, -4.0f), new Vector3(0, 0.55f, 0), 35);
        }
    }
}
