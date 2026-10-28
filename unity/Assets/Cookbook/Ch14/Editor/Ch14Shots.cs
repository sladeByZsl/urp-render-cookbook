// 第 14 章配图
using System.Collections.Generic;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch14
{
    static class Shots
    {
        // ---------- 小工具 ----------
        static void Kw(Material m, string prefix, string[] opts, int pick)
        {
            for (int i = 0; i < opts.Length; i++)
                if (i == pick) m.EnableKeyword(prefix + opts[i]); else m.DisableKeyword(prefix + opts[i]);
        }

        static Material Toon(Shot s, Color c, float outline = 2.5f)
        {
            var m = s.Mat("Cookbook/Ch14/ToonLit");
            m.SetColor("_BaseColor", c);
            m.SetFloat("_OutlineWidth", outline);
            Kw(m, "_OUTLINENORMAL_", new[] { "MESH", "TANGENT", "VERTEXCOLOR" }, 0);
            return m;
        }

        // 卡通场景的“摄影棚”：浅色背景 + 同样用卡通 Shader 的地面（这样地面上的影子也是硬边）
        static void Stage(Shot s, Color? floor = null)
        {
            s.Background(new Color(0.78f, 0.84f, 0.9f));
            var f = Toon(s, floor ?? new Color(0.86f, 0.88f, 0.82f), 0);
            f.SetColor("_ShadeColor", new Color(0.72f, 0.74f, 0.86f));
            f.SetFloat("_Shade2Strength", 0); f.SetFloat("_SpecStrength", 0); f.SetFloat("_RimStrength", 0);
            s.Floor(f);
        }

        static Texture2D Gen(Shot s, Texture2D t) { t.hideFlags = HideFlags.DontSave; s.Temp.Add(t); return t; }

        // 带鼻子、眼窝起伏的“头”：在单位球上做几处位移，再重新算法线
        static Mesh FaceMesh()
        {
            var tmp = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            var mesh = Object.Instantiate(tmp.GetComponent<MeshFilter>().sharedMesh);
            Object.DestroyImmediate(tmp);
            var v = mesh.vertices;
            for (int i = 0; i < v.Length; i++)
            {
                Vector3 p = v[i];
                if (p.z > 0) continue;   // 只动正面（-Z）
                float nose = Mathf.Exp(-(p.x * p.x) / 0.004f - Mathf.Pow(p.y + 0.03f, 2) / 0.012f);
                float sockets = Mathf.Exp(-Mathf.Pow(Mathf.Abs(p.x) - 0.15f, 2) / 0.006f - Mathf.Pow(p.y - 0.06f, 2) / 0.004f);
                float cheeks = Mathf.Exp(-Mathf.Pow(Mathf.Abs(p.x) - 0.2f, 2) / 0.01f - Mathf.Pow(p.y + 0.08f, 2) / 0.01f);
                v[i] = p + p.normalized * (0.09f * nose - 0.035f * sockets + 0.02f * cheeks);
            }
            mesh.vertices = v;
            mesh.RecalculateNormals(); mesh.RecalculateTangents(); mesh.RecalculateBounds();
            return mesh;
        }

        static Texture2D s_FaceSdf, s_MaskViz, s_SdfViz;
        static Texture2D FaceSdf()
        {
            if (s_FaceSdf == null)
            {
                s_FaceSdf = FaceSdfGenerator.Generate(256, 9, out s_MaskViz, out s_SdfViz);
                s_FaceSdf.hideFlags = s_MaskViz.hideFlags = s_SdfViz.hideFlags = HideFlags.DontSave;
            }
            return s_FaceSdf;
        }

        static Material FaceMat(Shot s, int mode)
        {
            var m = s.Mat("Cookbook/Ch14/ToonFace");
            Kw(m, "_FACESHADOW_", new[] { "NORMAL", "SDF" }, mode);
            m.SetTexture("_FaceSdf", FaceSdf());
            return m;
        }

        // 发丝噪声：沿 V 不变、沿 U 随机（与第 12 章同样的思路，这里单独生成，不依赖别的章节）
        static Texture2D StrandNoise(Shot s)
        {
            const int W = 256, H = 16;
            var t = new Texture2D(W, H, TextureFormat.RGBA32, true, true) { wrapMode = TextureWrapMode.Repeat };
            var rnd = new System.Random(11);
            var lo = new float[25]; for (int k = 0; k < 25; k++) lo[k] = (float)rnd.NextDouble(); lo[24] = lo[0];
            var px = new Color[W * H];
            for (int x = 0; x < W; x++)
            {
                float f = x / (float)W * 24f; int i0 = (int)f; float w = f - i0; w = w * w * (3 - 2 * w);
                float v = 0.75f * Mathf.Lerp(lo[i0], lo[i0 + 1], w) + 0.25f * (float)rnd.NextDouble();
                for (int y = 0; y < H; y++) px[y * W + x] = new Color(v, v, v, 1);
            }
            t.SetPixels(px); t.Apply();
            return Gen(s, t);
        }

        static Material HairMat(Shot s, int ring)
        {
            var m = s.Mat("Cookbook/Ch14/ToonHair");
            Kw(m, "_RING_", new[] { "OFF", "SMOOTH", "TOON" }, ring);
            m.SetTexture("_ShiftTex", StrandNoise(s));
            return m;
        }

        // ---------- 14.2 色阶 ----------
        static Material RampMat(Shot s, int mode)
        {
            var m = s.Mat("Cookbook/Ch14/ToonRamp");
            Kw(m, "_RAMP_", new[] { "LAMBERT", "STEP", "SMOOTH", "TEXTURE" }, mode);
            m.SetTexture("_RampTex", s.CoreTex("ramp_toon3"));
            return m;
        }

        [BookShot("ch14-ramp", W = 480, H = 400, Panels = 4)]
        static void Ramp(Shot s)
        {
            Stage(s);
            var m = RampMat(s, s.Panel);
            s.Sphere(m, new Vector3(-0.35f, 0.75f, 0), 1.3f);
            s.Knot(m, new Vector3(0.75f, 0.45f, -0.6f), 0.5f);
            s.SunDir(40, -60, 1.2f);
            s.LookAt(new Vector3(0, 1.4f, -3.8f), new Vector3(0.1f, 0.6f, 0), 36);
        }

        // 故意用很低的分辨率渲染，正文里放大显示，像素台阶一目了然
        [BookShot("ch14-ramp-aa", W = 160, H = 100, Panels = 2)]
        static void RampAA(Shot s)
        {
            s.Background(new Color(0.78f, 0.84f, 0.9f));
            var m = RampMat(s, s.Panel == 0 ? 1 : 2);
            m.SetFloat("_Softness", 0f);   // 只靠 fwidth 给出的“一像素过渡”
            s.Sphere(m, new Vector3(0, 0, 0), 2f);
            s.SunDir(10, -95, 1.2f);    // 让明暗交界线斜穿画面
            s.LookAt(new Vector3(0.0f, 0.55f, -1.6f), new Vector3(0.0f, 0.5f, -0.6f), 22);
            s.CamData.antialiasing = AntialiasingMode.None;
            s.Asset.msaaSampleCount = 1;   // 关掉 MSAA：着色锯齿与几何锯齿无关，MSAA 救不了它
        }

        // ---------- 14.3 阴影色 ----------
        [BookShot("ch14-shade", W = 640, H = 420, Panels = 3)]
        static void Shade(Shot s)
        {
            Stage(s);
            var m = RampMat(s, 2);
            var baseC = new Color(0.95f, 0.55f, 0.4f);
            m.SetColor("_BaseColor", baseC);
            if (s.Panel == 0) m.SetColor("_ShadeColor", baseC * 0.45f);              // 灰暗：固有色 × 0.45
            else m.SetColor("_ShadeColor", new Color(0.62f, 0.32f, 0.42f));         // 手挑：偏紫、饱和度不降
            m.SetFloat("_Shade2Strength", s.Panel == 2 ? 1 : 0);
            s.Sphere(m, new Vector3(-0.55f, 0.7f, 0.2f), 1.2f);
            var c = s.Cylinder(m, new Vector3(0.75f, 0.55f, -0.2f), 1);
            c.transform.localScale = new Vector3(0.7f, 0.55f, 0.7f);
            s.SunDir(35, -55, 1.2f);
            s.LookAt(new Vector3(0, 1.5f, -3.8f), new Vector3(0.1f, 0.6f, 0), 36);
        }

        // ---------- 14.4 边缘光 ----------
        static void Bust(Shot s, Material body, Material head)
        {
            var b = s.Capsule(body, new Vector3(0, 0.75f, 0), 1);
            b.transform.localScale = new Vector3(0.85f, 0.75f, 0.6f);
            s.Sphere(head, new Vector3(0, 1.85f, 0), 0.85f);
        }

        [BookShot("ch14-rim", W = 480, H = 480, Panels = 4)]
        static void Rim(Shot s)
        {
            Stage(s, new Color(0.3f, 0.32f, 0.4f));
            s.Background(new Color(0.12f, 0.14f, 0.2f));   // 深色背景，亮色边缘光才看得清
            s.Renderer.copyDepthMode = CopyDepthMode.ForcePrepass;   // 深度边缘光要在不透明物体着色时就能读到深度
            var m = s.Mat("Cookbook/Ch14/ToonRimSpec");
            Kw(m, "_RIM_", new[] { "OFF", "FRESNEL", "LIGHTMASKED", "DEPTH" }, s.Panel);
            Kw(m, "_SPEC_", new[] { "OFF", "BLINN", "TOON", "STYLIZED" }, 0);
            m.SetColor("_RimColor", new Color(1.3f, 1.05f, 0.6f));
            m.SetFloat("_RimWidth", 0.35f); m.SetFloat("_RimWidthPx", 6f);
            Bust(s, m, m);
            s.SunDir(30, 120, 1.3f);   // 侧后方的主光，边缘光应出现在右后侧轮廓
            s.LookAt(new Vector3(0, 1.6f, -4.2f), new Vector3(0, 1.25f, 0), 38);
        }

        // ---------- 14.5 风格化高光 ----------
        [BookShot("ch14-spec", W = 480, H = 400, Panels = 4)]
        static void Spec(Shot s)
        {
            Stage(s);
            var m = s.Mat("Cookbook/Ch14/ToonRimSpec");
            Kw(m, "_RIM_", new[] { "OFF", "FRESNEL", "LIGHTMASKED", "DEPTH" }, 0);
            int mode = s.Panel == 0 ? 1 : s.Panel == 1 ? 2 : 3;
            Kw(m, "_SPEC_", new[] { "OFF", "BLINN", "TOON", "STYLIZED" }, mode);
            m.SetFloat("_SpecThreshold", 0.96f);
            if (s.Panel == 2) { m.SetVector("_SpecShiftScale", new Vector4(0.15f, 0.05f, 0.65f, 0)); }
            if (s.Panel == 3) { m.SetVector("_SpecSplit", new Vector4(0.13f, 0.13f, 0, 0)); m.SetFloat("_SpecSquare", 1f); m.SetFloat("_SpecThreshold", 0.993f); }
            s.Sphere(m, new Vector3(0, 0.9f, 0), 1.6f);
            s.SunDir(35, -20, 1.2f);
            s.LookAt(new Vector3(0, 1.3f, -3.6f), new Vector3(0, 0.85f, 0), 36);
        }

        // ---------- 14.6 描边：线宽 ----------
        [BookShot("ch14-outline-width", W = 640, H = 400, Panels = 2)]
        static void OutlineWidth(Shot s)
        {
            Stage(s);
            for (int k = 0; k < 5; k++)
            {
                var m = s.Mat("Cookbook/Ch14/ToonOutline");
                Kw(m, "_OUTLINESPACE_", new[] { "OBJECT", "CLIP" }, s.Panel);
                Kw(m, "_OUTLINENORMAL_", new[] { "MESH", "TANGENT", "VERTEXCOLOR" }, 0);
                m.SetFloat("_OutlineWidthOS", 0.03f); m.SetFloat("_OutlineWidth", 2.5f);
                s.Capsule(m, new Vector3(-1.6f + k * 1.3f, 0.55f, -1.5f + k * 2.8f), 0.55f);
            }
            s.SunDir(40, -40, 1.2f);
            s.LookAt(new Vector3(-1.2f, 1.2f, -4.0f), new Vector3(0.4f, 0.6f, 3), 40);
        }

        // ---------- 14.7 描边：平滑法线 ----------
        // 程序化的“硬边”网格：每个面独立顶点（平直着色），描边会在棱角处断开
        static Mesh Prism(int sides, float radius, float height)
        {
            var v = new List<Vector3>(); var t = new List<int>(); var uv = new List<Vector2>();
            void Tri(Vector3 a, Vector3 b, Vector3 c)
            {
                int i = v.Count; v.Add(a); v.Add(b); v.Add(c);
                uv.Add(Vector2.zero); uv.Add(Vector2.right); uv.Add(Vector2.up);
                t.Add(i); t.Add(i + 1); t.Add(i + 2);
            }
            Vector3 P(int k, float y) { float a = k * Mathf.PI * 2 / sides; return new Vector3(Mathf.Cos(a) * radius, y, Mathf.Sin(a) * radius); }
            for (int k = 0; k < sides; k++)
            {
                Vector3 a0 = P(k, 0), a1 = P(k + 1, 0), b0 = P(k, height), b1 = P(k + 1, height);
                Tri(a0, b0, b1); Tri(a0, b1, a1);
                Tri(new Vector3(0, height, 0), b1, b0);
                Tri(Vector3.zero, a0, a1);
            }
            var m = new Mesh();
            m.SetVertices(v); m.SetTriangles(t, 0); m.SetUVs(0, uv);
            m.RecalculateNormals(); m.RecalculateTangents(); m.RecalculateBounds();
            return m;
        }

        // 低多边形宝石：八面体细分一次后不平滑，所有面都是硬边
        static Mesh Gem()
        {
            Vector3[] o = { Vector3.up, Vector3.down, Vector3.left, Vector3.right, Vector3.forward, Vector3.back };
            int[,] f = { { 0, 4, 3 }, { 0, 3, 5 }, { 0, 5, 2 }, { 0, 2, 4 }, { 1, 3, 4 }, { 1, 5, 3 }, { 1, 2, 5 }, { 1, 4, 2 } };
            var v = new List<Vector3>(); var t = new List<int>(); var uv = new List<Vector2>();
            for (int i = 0; i < 8; i++)
            {
                Vector3 a = o[f[i, 0]], b = o[f[i, 1]], c = o[f[i, 2]];
                Vector3 ab = (a + b).normalized, bc = (b + c).normalized, ca = (c + a).normalized;
                foreach (var tri in new[] { new[] { a, ab, ca }, new[] { ab, b, bc }, new[] { ca, bc, c }, new[] { ab, bc, ca } })
                {
                    int n = v.Count;
                    foreach (var p in tri) { v.Add(new Vector3(p.x * 0.5f, p.y * 0.75f, p.z * 0.5f)); uv.Add(new Vector2(p.x, p.z)); }
                    t.Add(n); t.Add(n + 1); t.Add(n + 2);
                }
            }
            var m = new Mesh();
            m.SetVertices(v); m.SetTriangles(t, 0); m.SetUVs(0, uv);
            m.RecalculateNormals(); m.RecalculateTangents(); m.RecalculateBounds();
            return m;
        }

        [BookShot("ch14-outline-smooth", W = 640, H = 400, Panels = 2)]
        static void OutlineSmooth(Shot s)
        {
            Stage(s);
            bool smooth = s.Panel == 1;
            Material Mat()
            {
                var m = s.Mat("Cookbook/Ch14/ToonOutline");
                Kw(m, "_OUTLINESPACE_", new[] { "OBJECT", "CLIP" }, 1);
                Kw(m, "_OUTLINENORMAL_", new[] { "MESH", "TANGENT", "VERTEXCOLOR" }, smooth ? 1 : 0);
                m.SetFloat("_OutlineWidth", 5f);
                return m;
            }
            // 与编辑器菜单调用的是同一个 SmoothNormalBaker.Bake
            Mesh Prep(Mesh mesh) { if (smooth) SmoothNormalBaker.Bake(mesh, SmoothNormalBaker.Target.Tangent); return mesh; }

            var tmp = GameObject.CreatePrimitive(PrimitiveType.Cube);
            var cube = Object.Instantiate(tmp.GetComponent<MeshFilter>().sharedMesh);   // 内置网格是共享的，先复制
            Object.DestroyImmediate(tmp);
            var go = s.MeshObj(Prep(cube), Mat(), new Vector3(-1.25f, 0.5f, 0), 0.9f, "Cube");
            go.transform.rotation = Quaternion.Euler(0, 35, 0);
            s.MeshObj(Prep(Prism(6, 0.5f, 0.9f)), Mat(), new Vector3(0.05f, 0.0f, 0.3f), 1, "Prism");
            var gem = s.MeshObj(Prep(Gem()), Mat(), new Vector3(1.25f, 0.75f, -0.1f), 1, "Gem");
            gem.transform.rotation = Quaternion.Euler(0, 20, 0);
            s.SunDir(40, -40, 1.2f);
            s.LookAt(new Vector3(0, 1.8f, -3.9f), new Vector3(0, 0.5f, 0), 38);
        }

        // ---------- 14.8 天使环 ----------
        [BookShot("ch14-angelring", W = 480, H = 440, Panels = 3)]
        static void AngelRing(Shot s)
        {
            Stage(s);
            s.Sphere(HairMat(s, s.Panel), new Vector3(0, 1.0f, 0), 1.5f);
            s.SunDir(35, -35, 1.2f);
            s.LookAt(new Vector3(0, 1.5f, -3.6f), new Vector3(0, 0.95f, 0), 34);
        }

        // ---------- 14.9 面部 SDF ----------
        [BookShot("ch14-face-sdfmap", W = 400, H = 400, Panels = 3)]
        static void FaceSdfMap(Shot s)
        {
            FaceSdf();
            var tex = s.Panel == 0 ? s_MaskViz : s.Panel == 1 ? s_SdfViz : s_FaceSdf;
            var m = s.Mat("Universal Render Pipeline/Unlit");
            m.SetTexture("_BaseMap", tex);
            s.Quad(m, Vector3.zero, 1);
            s.Background(Color.white);
            s.Cam.orthographic = true; s.Cam.orthographicSize = 0.5f;
            s.Cam.transform.position = new Vector3(0, 0, -2); s.Cam.transform.rotation = Quaternion.identity;
            s.Sun.intensity = 0;
        }

        static void FaceScene(Shot s, Material face, float lightYaw)
        {
            s.Background(new Color(0.78f, 0.84f, 0.9f));
            s.MeshObj(FaceMesh(), face, new Vector3(0, 0, 0), 1.6f, "Head");
            // 光在头部的水平面内绕一圈：yaw = 光“照向”的方向
            s.Sun.transform.rotation = Quaternion.Euler(15, lightYaw, 0);
            s.Sun.intensity = 1.2f;
            s.Sun.shadows = LightShadows.None;
            s.LookAt(new Vector3(0, 0.1f, -3.4f), new Vector3(0, 0, 0), 32);
        }

        [BookShot("ch14-face-compare", W = 480, H = 440, Panels = 2)]
        static void FaceCompare(Shot s) => FaceScene(s, FaceMat(s, s.Panel), -60);

        [BookShot("ch14-face-angles", W = 400, H = 400, Panels = 4)]
        static void FaceAngles(Shot s)
        {
            // 光从画面右侧（+X）照来：照向的方向 yaw = 180 + 夹角... 这里用 -(夹角) 表示从正面逐渐转到右侧再到背后
            float phi = new[] { 20f, 60f, 100f, 140f }[s.Panel];
            FaceScene(s, FaceMat(s, 1), -phi);
        }

        // ---------- 14.10 卡通化接收阴影 ----------
        // 三格：不接收阴影 / 接收但不卡通化 / 卡通化
        [BookShot("ch14-toon-shadow", W = 560, H = 420, Panels = 3)]
        static void ToonShadow(Shot s)
        {
            Stage(s);
            // 故意把阴影图降到 512：软阴影的过渡带和交界线锯齿都会被放大，便于观察
            s.AssetProp("m_MainLightShadowmapResolution", 512);
            var body = Toon(s, new Color(0.95f, 0.7f, 0.5f), 2.5f);
            var floor = GameObject.Find("Floor").GetComponent<MeshRenderer>().sharedMaterial;
            foreach (var m in new[] { body, floor })
            {
                m.SetFloat("_ReceiveShadow", s.Panel == 0 ? 0 : 1);
                m.SetFloat("_ShadowSoftness", s.Panel == 1 ? 0.5f : 0.03f);
            }
            body.SetFloat("_SpecStrength", 0);
            var cap = s.Capsule(body, new Vector3(0.3f, 1.0f, 0), 1);
            cap.transform.localScale = new Vector3(1.1f, 1.0f, 1.1f);
            var pillar = s.Cube(Toon(s, new Color(0.55f, 0.65f, 0.85f)), new Vector3(-1.5f, 1.4f, -1.2f), 1);
            pillar.transform.localScale = new Vector3(0.35f, 2.8f, 0.35f);
            s.SunDir(30, 60, 1.3f);   // 从左前方照来，柱子的影子斜穿胶囊的受光面
            s.LookAt(new Vector3(-0.2f, 1.6f, -4.4f), new Vector3(-0.3f, 0.9f, 0), 40);
        }

        // ---------- 14.11 完整的 Toon Shader ----------
        static void ToyScene(Shot s, int stage)
        {
            Stage(s, new Color(0.82f, 0.9f, 0.78f));
            var floor = GameObject.Find("Floor").GetComponent<MeshRenderer>().sharedMaterial;
            Material M(Color c)
            {
                var m = Toon(s, c, stage >= 3 ? 2.5f : 0f);
                m.SetFloat("_ReceiveShadow", stage >= 1 ? 1 : 0);
                m.SetFloat("_Shade2Strength", stage >= 1 ? 1 : 0);
                m.SetFloat("_SpecStrength", stage >= 2 ? 1 : 0);
                m.SetFloat("_RimStrength", stage >= 2 ? 0.6f : 0);
                // 描边用平滑法线（顶点色模式）：运行时对网格副本调用烘焙函数
                Kw(m, "_OUTLINENORMAL_", new[] { "MESH", "TANGENT", "VERTEXCOLOR" }, 2);
                return m;
            }
            floor.SetFloat("_ReceiveShadow", stage >= 1 ? 1 : 0);
            floor.SetFloat("_AddLightStrength", 0.35f);

            GameObject Smooth(GameObject go)
            {
                var mf = go.GetComponent<MeshFilter>();
                var mesh = Object.Instantiate(mf.sharedMesh);
                SmoothNormalBaker.Bake(mesh, SmoothNormalBaker.Target.VertexColor);
                mf.sharedMesh = mesh; s.Temp.Add(mesh);
                return go;
            }

            // 小人：身体、四肢、头、头发
            var shirt = M(new Color(0.95f, 0.45f, 0.4f));
            var skin = M(new Color(1f, 0.85f, 0.75f));
            var pants = M(new Color(0.35f, 0.45f, 0.8f));
            var body = Smooth(s.Capsule(shirt, new Vector3(0, 1.0f, 0), 1));
            body.transform.localScale = new Vector3(0.7f, 0.45f, 0.55f);
            foreach (float x in new[] { -0.17f, 0.17f })
            {
                var leg = Smooth(s.Capsule(pants, new Vector3(x, 0.35f, 0), 1));
                leg.transform.localScale = new Vector3(0.26f, 0.35f, 0.26f);
                var arm = Smooth(s.Capsule(skin, new Vector3(x * 2.6f, 1.0f, 0), 1));
                arm.transform.localScale = new Vector3(0.18f, 0.32f, 0.18f);
                arm.transform.rotation = Quaternion.Euler(0, 0, x > 0 ? 25 : -25);
            }
            var faceMat = FaceMat(s, 1);
            if (stage < 1) Kw(faceMat, "_FACESHADOW_", new[] { "NORMAL", "SDF" }, 0);
            var head = s.MeshObj(FaceMesh(), faceMat, new Vector3(0, 1.75f, 0), 0.8f, "Head");
            var hairMat = HairMat(s, stage >= 2 ? 2 : 0);
            faceMat.SetFloat("_OutlineWidth", stage >= 3 ? 2.5f : 0);
            hairMat.SetFloat("_OutlineWidth", stage >= 3 ? 2.5f : 0);
            var hair = s.Sphere(hairMat, new Vector3(0, 1.82f, 0.07f), 0.86f);

            // 道具
            var knot = Smooth(s.Knot(M(new Color(0.98f, 0.8f, 0.3f)), new Vector3(1.55f, 0.55f, 0.3f), 0.55f));
            var box = Smooth(s.Cube(M(new Color(0.55f, 0.8f, 0.7f)), new Vector3(-1.45f, 0.4f, 0.2f), 0.8f));
            box.transform.rotation = Quaternion.Euler(0, 30, 0);
            var ball = Smooth(s.Sphere(M(new Color(0.75f, 0.55f, 0.95f)), new Vector3(-0.9f, 0.25f, -0.8f), 0.5f));

            s.SunDir(40, -40, 1.25f);
            // 两盏彩色点光：卡通化后是边界清晰的彩色光斑
            s.Point(new Vector3(1.2f, 1.2f, -0.7f), new Color(1f, 0.45f, 0.7f), 0.9f, 2.0f);
            s.Point(new Vector3(-1.5f, 1.1f, -0.6f), new Color(0.35f, 0.75f, 1f), 0.9f, 2.0f);
            s.LookAt(new Vector3(0, 1.9f, -5.0f), new Vector3(0, 0.95f, 0), 36);
        }

        [BookShot("ch14-final", W = 960, H = 540)]
        static void Final(Shot s) => ToyScene(s, 3);

        [BookShot("ch14-final-breakdown", W = 480, H = 360, Panels = 4)]
        static void Breakdown(Shot s) => ToyScene(s, s.Panel);
    }
}
