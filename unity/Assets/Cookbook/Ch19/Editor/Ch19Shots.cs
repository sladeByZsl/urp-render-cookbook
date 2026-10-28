// 第 19 章配图：一个小水池场景，水面材质按案例逐步打开各个特性。
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch19
{
    static class Shots
    {
        // ---------------- 场景 ----------------
        // 水池地形：中间深、左后方是缓坡沙滩，高度场网格
        static float BasinHeight(float x, float z)
        {
            float s = Mathf.SmoothStep(0, 1, Mathf.InverseLerp(1.0f, 6.5f, -x * 0.75f + z * 0.65f));
            float h = Mathf.Lerp(-1.7f, 0.7f, s);
            h += 0.12f * Mathf.Sin(x * 1.3f + 0.5f) * Mathf.Sin(z * 1.1f);
            return h;
        }

        static Mesh BasinMesh(float size = 60f, int n = 300)
        {
            var v = new Vector3[(n + 1) * (n + 1)];
            var uv = new Vector2[v.Length];
            for (int z = 0; z <= n; z++)
                for (int x = 0; x <= n; x++)
                {
                    float px = ((float)x / n - 0.5f) * size, pz = ((float)z / n - 0.5f) * size;
                    v[z * (n + 1) + x] = new Vector3(px, BasinHeight(px, pz), pz);
                    uv[z * (n + 1) + x] = new Vector2(px, pz) * 0.5f;
                }
            var idx = new int[n * n * 6]; int p = 0;
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++)
                {
                    int a = z * (n + 1) + x, b = a + n + 1;
                    idx[p++] = a; idx[p++] = b; idx[p++] = a + 1;
                    idx[p++] = a + 1; idx[p++] = b; idx[p++] = b + 1;
                }
            var m = new Mesh { indexFormat = IndexFormat.UInt32, vertices = v, uv = uv, triangles = idx };
            m.RecalculateNormals(); m.RecalculateTangents(); m.RecalculateBounds();
            return m;
        }

        static GameObject Rock(Shot s, Material m, Vector3 pos, Vector3 scale, float yaw)
        {
            var go = s.Sphere(m, pos);
            go.transform.localScale = scale;
            go.transform.rotation = Quaternion.Euler(8, yaw, -6);
            return go;
        }

        static void Pool(Shot s)
        {
            var sand = s.Lit(new Color(0.9f, 0.8f, 0.62f), 0, 0.15f);
            sand.SetTexture("_BaseMap", s.CoreTex("checker"));
            s.MeshObj(BasinMesh(), sand, Vector3.zero, 1, "Basin");

            var rock = s.Lit(new Color(0.42f, 0.42f, 0.45f), 0, 0.25f);
            rock.SetTexture("_BaseMap", s.CoreTex("noise_fbm"));
            Rock(s, rock, new Vector3(-1.2f, -0.55f, 0.6f), new Vector3(1.6f, 0.9f, 1.3f), 20);   // 水下暗礁，顶部离水面很近
            Rock(s, rock, new Vector3(2.6f, -0.35f, 2.4f), new Vector3(2.0f, 1.3f, 1.6f), -30);   // 露出水面的大石头
            Rock(s, rock, new Vector3(-3.4f, 0.1f, 3.2f), new Vector3(1.2f, 0.8f, 1.0f), 60);     // 沙滩上的石头

            var stone = s.Lit(new Color(0.75f, 0.72f, 0.68f), 0, 0.3f);
            foreach (var px in new[] { new Vector3(0.9f, 0, 1.4f), new Vector3(-0.3f, 0, 3.6f), new Vector3(3.6f, 0, -0.4f) })
            {
                var c = s.Cylinder(stone, new Vector3(px.x, -0.1f, px.z));
                c.transform.localScale = new Vector3(0.45f, 1.6f, 0.45f);                         // 柱子：从水底一直伸出水面
            }

            // 木栈道：前景横跨水面，用来演示折射的“前景泄漏”和平面反射
            var wood = s.Lit(new Color(0.45f, 0.3f, 0.18f), 0, 0.3f);
            var deck = s.Cube(wood, new Vector3(-2.2f, 0.32f, -1.2f));
            deck.transform.localScale = new Vector3(4.0f, 0.12f, 0.9f);
            deck.transform.rotation = Quaternion.Euler(0, 25, 0);
            foreach (var dx in new[] { -1.6f, 0f, 1.6f })
            {
                var post = s.Cylinder(wood, deck.transform.TransformPoint(new Vector3(dx / 4f, 0, 0)) + Vector3.down * 0.9f);
                post.transform.localScale = new Vector3(0.14f, 0.95f, 0.14f);
            }
        }

        static void DefaultView(Shot s) => s.LookAt(new Vector3(0.6f, 2.5f, -6.6f), new Vector3(0, -0.3f, 1.2f), 45);

        static Material WaterMat(Shot s)
        {
            var m = s.Mat("Cookbook/Ch19/Water");
            // 用程序生成的可平铺法线（见案例 19.3，公共贴图 water_normal 按同样规则生成，也可直接换用）
            m.SetTexture("_NormalMap", WaterNormalGenerator.Create());
            m.SetTexture("_FoamNoise", s.CoreTex("noise_fbm"));
            m.SetFloat("_Phase", 3.0f);
            return m;
        }

        // 只保留 on 里列出的特性
        static void Features(Material m, params string[] on)
        {
            string[] all = { "_REFRACTION", "_NORMALS", "_REFLECTION", "_PLANAR_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS", "_GERSTNER" };
            foreach (var k in all)
            {
                bool e = System.Array.IndexOf(on, k) >= 0;
                if (e) m.EnableKeyword(k); else m.DisableKeyword(k);
                // 同步 Toggle 属性，便于在检视面板里看出当前状态
                string prop = k == "_PLANAR_REFLECTION" ? "_PlanarReflection" : "_" + k.Substring(1, 1) + k.Substring(2).ToLowerInvariant();
                if (m.HasProperty(prop)) m.SetFloat(prop, e ? 1 : 0);
            }
        }

        static GameObject Water(Shot s, Material m, int n = 240, float size = 60f)
        {
            var go = s.Grid(m, new Vector3(0, 0, 0), size, n);
            go.layer = 4;     // Water 层：平面反射相机不渲染它
            return go;
        }

        static void Glow(Shot s, float bloom = 0.6f)
        {
            var p = s.Post();
            var b = p.Add<Bloom>(); b.intensity.Override(bloom); b.threshold.Override(1.1f); b.scatter.Override(0.6f);
            var t = p.Add<Tonemapping>(); t.mode.Override(TonemappingMode.Neutral);
        }

        // ---------------- 19.1 场景与深度 ----------------
        [BookShot("ch19-pool", W = 640, H = 420, Panels = 2)]
        static void PoolShot(Shot s)
        {
            Pool(s); DefaultView(s);
            if (s.Panel == 1)
            {
                // 最朴素的水：单色半透明
                var m = WaterMat(s); Features(m);
                m.SetColor("_ShallowColor", new Color(0.15f, 0.45f, 0.6f, 0.6f));
                m.SetColor("_DeepColor", new Color(0.15f, 0.45f, 0.6f, 0.6f));
                m.SetFloat("_EdgeFade", 0.001f);
                Water(s, m);
            }
        }

        [BookShot("ch19-depth", W = 640, H = 420, Panels = 3)]
        static void Depth(Shot s)
        {
            Pool(s); DefaultView(s);
            var m = WaterMat(s); Features(m);
            if (s.Panel == 0) m.SetFloat("_DebugView", 1);
            if (s.Panel == 1) m.SetFloat("_DebugView", 2);
            Water(s, m);
        }

        // ---------------- 19.2 折射 ----------------
        [BookShot("ch19-refraction", W = 640, H = 420, Panels = 3)]
        static void Refraction(Shot s)
        {
            Pool(s);
            // 一个悬在水面上方的橙色箱子：它完全不在水里，水面上却“折射”出橙色，就是前景泄漏
            s.Cube(s.Lit(new Color(1f, 0.45f, 0.1f), 0, 0.4f), new Vector3(0.2f, 0.45f, -2.6f), 0.5f)
             .transform.rotation = Quaternion.Euler(0, 30, 0);
            s.LookAt(new Vector3(0.6f, 1.5f, -4.6f), new Vector3(0.0f, 0.0f, -1.8f), 40);
            var m = WaterMat(s); Features(m, "_REFRACTION", "_NORMALS");
            m.SetVector("_FlowB", new Vector4(0, 0, 0, 0));       // 先只用一层法线
            m.SetVector("_FlowA", new Vector4(0.03f, 0.02f, 1.0f, 0));
            m.SetFloat("_RefractionStrength", s.Panel == 0 ? 0f : 0.2f);
            m.SetFloat("_RefractLeakFix", s.Panel == 2 ? 1 : 0);
            Water(s, m);
        }

        // ---------------- 19.3 双法线 ----------------
        [BookShot("ch19-normals", W = 640, H = 420, Panels = 3)]
        static void Normals(Shot s)
        {
            Pool(s); DefaultView(s);
            var m = WaterMat(s); Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION");
            if (s.Panel == 0) { m.SetVector("_FlowB", Vector4.zero); m.SetFloat("_DebugView", 3); }
            if (s.Panel == 1) { m.SetFloat("_DebugView", 3); }
            Water(s, m);
        }

        // ---------------- 19.4 菲涅尔与反射 ----------------
        [BookShot("ch19-fresnel", W = 640, H = 420, Panels = 3)]
        static void Fresnel(Shot s)
        {
            Pool(s); DefaultView(s);
            var m = WaterMat(s);
            if (s.Panel == 0) Features(m, "_REFRACTION", "_NORMALS");
            else Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION");
            if (s.Panel == 1) { m.SetFloat("_UseFresnel", 0); m.SetFloat("_ReflectionStrength", 0.5f); }
            Water(s, m);
        }

        // ---------------- 19.5 高光 ----------------
        [BookShot("ch19-specular", W = 640, H = 420, Panels = 3)]
        static void Specular(Shot s)
        {
            Pool(s);
            s.SunDir(18, 175, 1.5f);     // 太阳在相机对面低角度：水面上拉出一条亮带
            s.LookAt(new Vector3(0.6f, 2.0f, -6.6f), new Vector3(0, 0.0f, 2.0f), 45);
            var m = WaterMat(s);
            if (s.Panel == 0) Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION");
            else Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR");
            if (s.Panel == 1) m.SetFloat("_SpecPower", 120);
            if (s.Panel == 2) m.SetFloat("_SpecPower", 1200);
            Water(s, m);
        }

        // ---------------- 19.6 泡沫 ----------------
        [BookShot("ch19-foam", W = 640, H = 420, Panels = 3)]
        static void Foam(Shot s)
        {
            Pool(s);
            s.LookAt(new Vector3(-1.0f, 2.4f, -2.6f), new Vector3(-2.0f, -0.2f, 2.4f), 45);
            var m = WaterMat(s);
            if (s.Panel == 0) Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR");
            else Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR", "_FOAM");
            if (s.Panel == 1) m.SetFloat("_DebugView", 4);
            Water(s, m);
        }

        // ---------------- 19.7 焦散 ----------------
        [BookShot("ch19-caustics", W = 640, H = 420, Panels = 3)]
        static void Caustics(Shot s)
        {
            Pool(s);
            s.LookAt(new Vector3(-0.6f, 2.6f, -3.4f), new Vector3(-0.9f, -0.6f, 0.9f), 45);
            var m = WaterMat(s);
            if (s.Panel == 0) { Features(m, "_REFRACTION", "_NORMALS"); m.SetFloat("_DebugView", 5); }
            if (s.Panel == 1) Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR", "_FOAM");
            if (s.Panel == 2) Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS");
            Water(s, m);
        }

        // ---------------- 19.8 Gerstner 波 ----------------
        [BookShot("ch19-gerstner", W = 640, H = 420, Panels = 3)]
        static void Gerstner(Shot s)
        {
            Pool(s);
            s.LookAt(new Vector3(0.6f, 1.5f, -6.6f), new Vector3(0, 0.0f, 2.0f), 45);
            var m = WaterMat(s);
            if (s.Panel == 0) Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS");
            else Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS", "_GERSTNER");
            if (s.Panel == 1) { m.SetVector("_WaveB", new Vector4(1, 0, 0, 1)); m.SetVector("_WaveC", new Vector4(1, 0, 0, 1)); m.SetVector("_WaveA", new Vector4(1, 0.3f, 0.28f, 6)); }
            Water(s, m, 400);
        }

        // ---------------- 19.9 平面反射 ----------------
        [BookShot("ch19-planar", W = 640, H = 420, Panels = 2)]
        static void Planar(Shot s)
        {
            Pool(s);
            s.LookAt(new Vector3(0.6f, 1.2f, -6.6f), new Vector3(0, 0.2f, 2.0f), 45);
            var m = WaterMat(s);
            if (s.Panel == 0) Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS");
            else Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_PLANAR_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS");
            var w = Water(s, m);
            if (s.Panel == 1) AddPlanar(s, w, 640, 420);
        }

        // 拍摄时没有 LateUpdate：在主相机渲染之前手动提交一次反射渲染请求
        static void AddPlanar(Shot s, GameObject water, int w, int h)
        {
            var pr = water.AddComponent<PlanarReflection>();
            pr.updateMode = PlanarReflection.UpdateMode.Manual;
            pr.resolutionScale = 1f;
            var tmp = RenderTexture.GetTemporary(w, h, 24);
            s.Cam.targetTexture = tmp;
            s.Cam.aspect = (float)w / h;
            pr.RenderFor(s.Cam);
            s.Cam.targetTexture = null;
            RenderTexture.ReleaseTemporary(tmp);
        }

        // ---------------- 19.10 最终合成 ----------------
        static void Final(Shot s, Material m)
        {
            Features(m, "_REFRACTION", "_NORMALS", "_REFLECTION", "_PLANAR_REFLECTION", "_SPECULAR", "_FOAM", "_CAUSTICS", "_GERSTNER");
            // 最终版用更平缓的波：小水池里浪太大会漫上沙滩
            m.SetVector("_WaveA", new Vector4(1, 0.3f, 0.07f, 7));
            m.SetVector("_WaveB", new Vector4(0.4f, 1, 0.06f, 4.3f));
            m.SetVector("_WaveC", new Vector4(-0.7f, 0.6f, 0.05f, 2.6f));
            m.SetFloat("_SpecIntensity", 0.25f);
            m.SetFloat("_SpecPower", 2048);
            m.SetFloat("_CausticIntensity", 0.9f);
            AddPlanar(s, Water(s, m, 400), 960, 560);
            Glow(s);
        }

        [BookShot("ch19-final", Hdr = true, W = 960, H = 560)]
        static void FinalWide(Shot s)
        {
            Pool(s);
            s.SunDir(30, 170, 1.5f);
            s.LookAt(new Vector3(1.2f, 2.2f, -6.8f), new Vector3(-0.4f, -0.2f, 1.6f), 48);
            Final(s, WaterMat(s));
        }

        [BookShot("ch19-final-close", Hdr = true, W = 960, H = 560)]
        static void FinalClose(Shot s)
        {
            Pool(s);
            s.SunDir(40, -60, 1.4f);
            s.LookAt(new Vector3(0.4f, 1.5f, -1.5f), new Vector3(-1.3f, -0.4f, 1.4f), 50);
            Final(s, WaterMat(s));
        }
    }
}
