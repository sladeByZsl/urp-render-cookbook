// 第 5 章配图：经典光照模型的参数扫描与对比
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch05
{
    static class Ch05Shots
    {
        static readonly Color Orange = new Color(0.85f, 0.5f, 0.25f);
        static readonly Color DarkBg = new Color(0.10f, 0.11f, 0.13f);

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

        // 低多边形 UV 球：用来放大逐顶点光照的问题
        static Mesh UvSphere(int lon, int lat)
        {
            var verts = new System.Collections.Generic.List<Vector3>();
            var tris = new System.Collections.Generic.List<int>();
            for (int y = 0; y <= lat; y++)
            {
                float v = (float)y / lat * Mathf.PI;
                for (int x = 0; x <= lon; x++)
                {
                    float u = (float)x / lon * Mathf.PI * 2f;
                    verts.Add(new Vector3(Mathf.Sin(v) * Mathf.Cos(u), Mathf.Cos(v), Mathf.Sin(v) * Mathf.Sin(u)) * 0.5f);
                }
            }
            for (int y = 0; y < lat; y++)
                for (int x = 0; x < lon; x++)
                {
                    int a = y * (lon + 1) + x, b = a + lon + 1;
                    tris.Add(a); tris.Add(a + 1); tris.Add(b);
                    tris.Add(b); tris.Add(a + 1); tris.Add(b + 1);
                }
            var m = new Mesh();
            m.SetVertices(verts);
            m.SetTriangles(tris, 0);
            var n = new Vector3[verts.Count];
            for (int i = 0; i < n.Length; i++) n[i] = verts[i].normalized;   // 光滑法线
            m.normals = n;
            m.RecalculateBounds();
            return m;
        }

        // 一排球用正交相机拍：每个球的观察角度完全相同，对比才公平
        static void RowCamera(Shot s, float y = 0.5f, float halfHeight = 0.97f)
        {
            s.Background(DarkBg);
            s.LookAt(new Vector3(0, y, -8f), new Vector3(0, y, 0));
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = halfHeight;
        }

        [BookShot("ch05-lambert", W = 640, H = 480, Panels = 3)]
        static void Lambert(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch05/Lambert");
            m.SetColor("_BaseColor", s.Panel == 0 ? Color.white * 0.8f : Orange);
            m.SetFloat("_AmbientStrength", s.Panel == 2 ? 1f : 0f);
            s.Sphere(m, new Vector3(0, 0.8f, 0), 1.5f);
            s.SunDir(30, -95);
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.75f, 0), 32);
        }

        [BookShot("ch05-lightcolor", W = 640, H = 480, Panels = 3)]
        static void LightColor(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch05/Lambert");
            m.SetColor("_BaseColor", new Color(0.8f, 0.8f, 0.8f));
            m.SetFloat("_AmbientStrength", 0.15f);
            s.Sphere(m, new Vector3(0, 0.8f, 0), 1.5f);
            s.SunDir(40, -60, 1f);
            if (s.Panel == 1) s.Sun.color = new Color(1f, 0.55f, 0.25f);
            if (s.Panel == 2) s.Sun.intensity = 3f;
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.75f, 0), 32);
        }

        [BookShot("ch05-halflambert", W = 640, H = 480, Panels = 3)]
        static void HalfLambert(Shot s)
        {
            s.Floor();
            Material m;
            if (s.Panel == 0) m = s.Mat("Cookbook/Ch05/Lambert");
            else { m = s.Mat("Cookbook/Ch05/HalfLambert"); m.SetFloat("_Power", s.Panel == 1 ? 1f : 2f); }
            m.SetColor("_BaseColor", Orange);
            m.SetFloat("_AmbientStrength", 0f);
            s.Sphere(m, new Vector3(0, 0.8f, 0), 1.5f);
            s.SunDir(30, -95);
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.75f, 0), 32);
        }

        [BookShot("ch05-wrap", W = 960, H = 420)]
        static void Wrap(Shot s)
        {
            RowCamera(s, 1.1f, 1.36f);
            float[] w = { 0f, 0.25f, 0.5f, 0.75f, 1f };
            for (int row = 0; row < 2; row++)
            {
                int r = row;
                s.SphereRow(5, i =>
                {
                    var m = s.Mat("Cookbook/Ch05/WrapLighting");
                    m.SetColor("_BaseColor", Orange);
                    m.SetFloat("_Wrap", w[i]);
                    m.SetFloat("_AmbientStrength", 0.15f);
                    if (r == 0) m.EnableKeyword("_WRAP_ENERGY_CONSERVING");
                    return m;
                }, y: row == 0 ? 0.5f : 1.7f, step: 1.15f);
            }
            s.SunDir(10, -90);
        }

        [BookShot("ch05-wrap-tint", W = 640, H = 480, Panels = 2)]
        static void WrapTint(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch05/WrapLighting");
            m.SetColor("_BaseColor", new Color(0.8f, 0.6f, 0.5f));
            m.SetFloat("_Wrap", s.Panel == 0 ? 0f : 0.5f);
            m.EnableKeyword("_WRAP_ENERGY_CONSERVING");
            m.SetColor("_TerminatorTint", s.Panel == 0 ? Color.black : new Color(0.7f, 0.12f, 0.05f));
            m.SetFloat("_AmbientStrength", 0.3f);
            s.Sphere(m, new Vector3(0, 0.8f, 0), 1.5f);
            s.SunDir(25, -95);
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.75f, 0), 32);
        }

        [BookShot("ch05-phong-shininess", W = 960, H = 300)]
        static void PhongShininess(Shot s)
        {
            RowCamera(s);
            float[] n = { 2f, 8f, 32f, 128f, 512f };
            s.SphereRow(5, i =>
            {
                var m = s.Mat("Cookbook/Ch05/Phong");
                m.SetFloat("_Shininess", n[i]);
                m.SetFloat("_AmbientStrength", 0.4f);
                return m;
            }, step: 1.15f);
            s.SunDir(35, 25);
        }

        [BookShot("ch05-phong-vs-blinn", W = 640, H = 480, Panels = 3)]
        static void PhongVsBlinn(Shot s)
        {
            s.Background(DarkBg);
            Material m = s.Mat(s.Panel == 0 ? "Cookbook/Ch05/Phong" : "Cookbook/Ch05/BlinnPhong");
            m.SetColor("_BaseColor", new Color(0.12f, 0.16f, 0.22f));
            m.SetColor("_SpecColor", new Color(0.8f, 0.8f, 0.8f));
            m.SetFloat("_Shininess", s.Panel == 2 ? 128f : 32f);
            m.SetFloat("_AmbientStrength", 0.3f);
            s.Grid(m, new Vector3(0, 0, 15f), 40f, 16);
            // 逆光、低角度：光从远处贴着平面照向相机，这是两种模型差异最大的情形
            s.SunDir(12, 180, 1.2f);
            s.LookAt(new Vector3(0, 1.3f, -3f), new Vector3(0, 0f, 2.5f), 45);
        }

        [BookShot("ch05-normalized", W = 960, H = 420)]
        static void Normalized(Shot s)
        {
            RowCamera(s, 1.1f, 1.36f);
            float[] n = { 8f, 32f, 128f, 512f, 2048f };
            for (int row = 0; row < 2; row++)
            {
                int r = row;
                s.SphereRow(5, i =>
                {
                    var m = s.Mat("Cookbook/Ch05/SpecularNormalized");
                    m.SetFloat("_Shininess", n[i]);
                    SetKeywordEnum(m, "_Model", new[] { "BlinnPhong", "Phong" }, 0);
                    if (r == 0) m.EnableKeyword("_NORMALIZE_SPECULAR"); else m.DisableKeyword("_NORMALIZE_SPECULAR");
                    m.SetFloat("_AmbientStrength", 0.5f);
                    return m;
                }, y: row == 0 ? 0.5f : 1.7f, step: 1.15f);
            }
            s.SunDir(35, 25, 1.2f);
        }

        static void RoughRow(Shot s)
        {
            RowCamera(s);
            s.SphereRow(5, i =>
            {
                var m = s.Mat("Cookbook/Ch05/RoughDiffuse");
                SetKeywordEnum(m, "_Model", new[] { "Lambert", "OrenNayar", "Minnaert" }, i == 0 ? 0 : i == 4 ? 2 : 1);
                m.SetFloat("_Roughness", i == 1 ? 0.25f : i == 2 ? 0.5f : 1.0f);
                m.SetFloat("_MinnaertK", 0.7f);
                m.SetFloat("_AmbientStrength", 0.15f);
                return m;
            }, step: 1.15f);
        }

        [BookShot("ch05-roughdiffuse-front", W = 960, H = 300)]
        static void RoughFront(Shot s) { RoughRow(s); s.SunDir(8, 3, 1.3f); }      // 光源几乎在相机身后

        [BookShot("ch05-roughdiffuse-side", W = 960, H = 300)]
        static void RoughSide(Shot s) { RoughRow(s); s.SunDir(15, -80, 1.3f); }    // 侧光

        [BookShot("ch05-gouraud", W = 640, H = 480, Panels = 3)]
        static void Gouraud(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch05/Gouraud");
            if (s.Panel == 1) m.DisableKeyword("_PER_VERTEX"); else m.EnableKeyword("_PER_VERTEX");
            var pos = new Vector3(0, 0.8f, 0);
            if (s.Panel == 2) s.Sphere(m, pos, 1.5f);
            else s.MeshObj(UvSphere(14, 9), m, pos, 1.5f, "LowPolySphere");
            s.SunDir(40, 25);
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.75f, 0), 32);
        }

        [BookShot("ch05-classiclab", W = 480, H = 420, Panels = 4)]
        static void ClassicLab(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch05/ClassicLab");
            int[] spec = { 1, 2, 2, 0 };   // Phong, BlinnPhong, BlinnPhong, None
            Color[] col = { new Color(0.2f, 0.35f, 0.65f), Orange, new Color(0.8f, 0.55f, 0.45f), new Color(0.7f, 0.68f, 0.62f) };
            SetKeywordEnum(m, "_Diffuse", new[] { "Lambert", "HalfLambert", "Wrap", "OrenNayar" }, s.Panel);
            SetKeywordEnum(m, "_Specular", new[] { "None", "Phong", "BlinnPhong" }, spec[s.Panel]);
            m.SetColor("_BaseColor", col[s.Panel]);
            m.SetFloat("_Smoothness", s.Panel == 2 ? 0.45f : 0.6f);
            m.SetFloat("_Wrap", 0.5f);
            m.SetFloat("_Roughness", 0.8f);
            m.SetFloat("_AmbientStrength", 0.6f);
            s.Knot(m, new Vector3(0, 1.0f, 0), 1.1f);
            s.SunDir(35, -60);
            s.LookAt(new Vector3(0, 1.7f, -4.3f), new Vector3(0, 0.9f, 0), 34);
        }
    }
}
