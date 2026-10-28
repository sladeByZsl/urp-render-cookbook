// 第 17 章配图。拍摄时 _Time≈0，所有动画都用材质上的 _Phase/_Progress/_Frame 摆出姿态。
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch17
{
    static class Shots17
    {
        // 程序化旗面图案：三色横条 + 圆形徽记
        static Texture2D FlagTex()
        {
            const int W = 256, H = 160;
            var t = new Texture2D(W, H, TextureFormat.RGBA32, true, false) { wrapMode = TextureWrapMode.Clamp, hideFlags = HideFlags.DontSave };
            var px = new Color[W * H];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    float v = (float)y / H;
                    Color c = v > 0.66f ? new Color(0.12f, 0.3f, 0.6f) : v > 0.33f ? new Color(0.95f, 0.93f, 0.88f) : new Color(0.75f, 0.15f, 0.15f);
                    float dx = (x - W * 0.3f) / H, dy = (y - H * 0.5f) / H;
                    float r = Mathf.Sqrt(dx * dx + dy * dy);
                    if (r < 0.22f) c = r > 0.17f ? new Color(0.95f, 0.75f, 0.2f) : new Color(0.12f, 0.3f, 0.6f);
                    px[y * W + x] = c;
                }
            t.SetPixels(px); t.Apply(true);
            return t;
        }

        static GameObject FlagWithPole(Shot s, Material flag, Vector3 polePos)
        {
            s.Cylinder(s.Lit(new Color(0.55f, 0.55f, 0.58f), 0.8f, 0.6f), polePos + new Vector3(0, 1.4f, 0), 1f)
                .transform.localScale = new Vector3(0.06f, 1.4f, 0.06f);
            // 网格是物体空间 XZ 平面（2×2 米）：绕 X 转 -90° 立起来，再把 Z 压成 1.25 米高
            var go = s.MeshObj(Meshes.Grid(2f, 80), flag, polePos + new Vector3(1.0f, 2.1f, 0), 1f, "Flag");
            go.transform.rotation = Quaternion.Euler(-90, 0, 0);
            go.transform.localScale = new Vector3(1f, 1f, 0.62f);
            return go;
        }

        static Material FlagMat(Shot s)
        {
            var m = s.Mat("Cookbook/Ch17/Flag");
            m.SetTexture("_BaseMap", FlagTex());
            m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
            m.SetFloat("_Phase", 1.3f);
            return m;
        }

        [BookShot("ch17-flag", W = 640, H = 480, Panels = 3)]
        static void Flag(Shot s)
        {
            var m = FlagMat(s);
            m.SetFloat("_RecalcNormal", s.Panel == 0 ? 0 : 1);
            m.SetFloat("_NoiseStrength", s.Panel == 2 ? 0.5f : 0f);
            s.Floor();
            FlagWithPole(s, m, new Vector3(-1.0f, 0, 0));
            s.LookAt(new Vector3(0.6f, 2.3f, -3.6f), new Vector3(0, 1.9f, 0), 40);
            s.SunDir(35, -60, 1.3f);
        }

        [BookShot("ch17-shadowsync", W = 640, H = 480, Panels = 2)]
        static void ShadowSync(Shot s)
        {
            var m = FlagMat(s);
            m.SetFloat("_Amplitude", 0.25f);
            m.SetFloat("_DeformShadow", s.Panel);
            s.Floor();
            FlagWithPole(s, m, new Vector3(-1.0f, 0, 0));
            s.LookAt(new Vector3(0.3f, 4.2f, -3.2f), new Vector3(0.1f, 0.6f, 0.9f), 45);
            s.SunDir(62, -20, 1.3f);
        }

        // ---------------- 草 ----------------
        [BookShot("ch17-grass", W = 640, H = 480, Panels = 2)]
        static void Grass(Shot s)
        {
            var ground = s.Lit(new Color(0.16f, 0.24f, 0.08f), 0, 0.1f);
            s.Floor(ground);
            var m = s.Mat("Cookbook/Ch17/Grass");
            m.SetTexture("_WindNoise", s.CoreTex("noise_fbm"));
            m.SetFloat("_WindStrength", s.Panel == 0 ? 0 : 0.45f);
            m.SetFloat("_Sway", s.Panel == 0 ? 0 : 0.12f);
            m.SetFloat("_Phase", 2f);
            s.MeshObj(GrassField.Build(14f, 60000), m, new Vector3(0, 0, 4.5f), 1f, "Grass");
            s.Sphere(s.Lit(new Color(0.8f, 0.3f, 0.25f), 0, 0.5f), new Vector3(0.9f, 0.5f, 2.2f), 1f);
            s.LookAt(new Vector3(0, 1.5f, -2.4f), new Vector3(0, 0.3f, 2.5f), 45);
            s.SunDir(35, -40, 1.3f);
        }

        // ---------------- Gerstner ----------------
        [BookShot("ch17-gerstner", W = 640, H = 480, Panels = 3)]
        static void Gerstner(Shot s)
        {
            var m = s.Mat("Cookbook/Ch17/Gerstner");
            m.SetFloat("_Phase", 0.7f);
            if (s.Panel < 2)
            {
                // 单个波：左 = 只有竖直位移的正弦波，中 = 同样参数的 Gerstner 波
                m.SetVector("_WaveA", new Vector4(1, 0.15f, 0.85f, 3.2f));
                m.SetVector("_WaveB", Vector4.zero); m.SetVector("_WaveC", Vector4.zero); m.SetVector("_WaveD", Vector4.zero);
                m.SetFloat("_Horizontal", s.Panel);
                m.SetFloat("_FoamThreshold", 0.25f);
            }
            else
            {
                m.SetVector("_WaveA", new Vector4(1, 0.2f, 0.4f, 4.5f));
                m.SetVector("_WaveB", new Vector4(0.3f, 1, 0.25f, 3.1f));
                m.SetVector("_WaveC", new Vector4(1, 0.8f, 0.2f, 1.7f));
                m.SetVector("_WaveD", new Vector4(-0.5f, 1, 0.12f, 1.1f));
            }
            s.Grid(m, new Vector3(0, 0, 4), 18, 260);
            s.LookAt(new Vector3(0, 2.4f, -3.2f), new Vector3(0, 0.0f, 3.5f), 45);
            s.SunDir(22, 160, 1.4f);   // 逆光，便于看到高光带和波峰轮廓
        }

        // ---------------- 膨胀 / 呼吸 ----------------
        [BookShot("ch17-inflate", W = 480, H = 400, Panels = 4)]
        static void Inflate(Shot s)
        {
            s.Floor();
            Material M(float amount, bool radial, float pulse = 0)
            {
                var m = s.Mat("Cookbook/Ch17/Inflate");
                m.SetFloat("_Amount", amount);
                m.SetFloat("_PulseFreq", pulse);
                m.DisableKeyword("_DIR_NORMAL"); m.DisableKeyword("_DIR_RADIAL");
                m.EnableKeyword(radial ? "_DIR_RADIAL" : "_DIR_NORMAL");
                m.SetFloat("_Dir", radial ? 1 : 0);
                return m;
            }
            if (s.Panel < 3)
            {
                var m = s.Panel == 0 ? M(0, false) : s.Panel == 1 ? M(0.07f, false) : M(0.09f, false, 14f);
                if (s.Panel == 2) m.SetFloat("_Phase", 0f);
                s.Knot(m, new Vector3(0, 1.0f, 0), 1.1f);
                s.LookAt(new Vector3(0, 1.9f, -3.6f), new Vector3(0, 0.9f, 0), 38);
            }
            else
            {
                s.Cube(M(0.12f, false), new Vector3(-0.75f, 0.55f, 0), 0.8f).transform.rotation = Quaternion.Euler(0, 35, 0);
                s.Cube(M(0.12f, true), new Vector3(0.75f, 0.55f, 0), 0.8f).transform.rotation = Quaternion.Euler(0, 35, 0);
                s.LookAt(new Vector3(0, 1.9f, -3.6f), new Vector3(0, 0.6f, 0), 38);
            }
            s.SunDir(45, -35, 1.2f);
        }

        // ---------------- 碎裂 ----------------
        [BookShot("ch17-shatter", W = 640, H = 480, Panels = 3)]
        static void Shatter(Shot s)
        {
            s.Floor();
            float[] prog = { 0f, 0.3f, 0.55f };
            var m = s.Mat("Cookbook/Ch17/Shatter");
            m.SetFloat("_Progress", prog[s.Panel]);
            m.SetVector("_SweepDir", new Vector4(0, 0, 1, 0));   // 圆环物体空间的 z 轴立起来后朝上
            m.SetFloat("_Distance", 0.5f); m.SetFloat("_Spin", 5f);
            var torus = s.MeshObj(ShatterMesh.Build(Meshes.Torus(0.75f, 0.3f)), m, new Vector3(-0.8f, 1.1f, 0.2f), 1f, "Torus");
            torus.transform.rotation = Quaternion.Euler(80, 20, 0);
            var src2 = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            var mesh2 = ShatterMesh.Build(src2.GetComponent<MeshFilter>().sharedMesh, 11);
            Object.DestroyImmediate(src2);
            var m2 = s.Mat("Cookbook/Ch17/Shatter");
            m2.SetFloat("_Progress", prog[s.Panel]);
            m2.SetColor("_BaseColor", new Color(0.85f, 0.5f, 0.3f));
            m2.SetVector("_SweepDir", new Vector4(1, 0, 0, 0));
            m2.SetFloat("_Distance", 0.6f); m2.SetFloat("_Gravity", 0.9f);
            s.MeshObj(mesh2, m2, new Vector3(0.9f, 0.8f, 0.2f), 1.4f, "Sphere");
            s.LookAt(new Vector3(0, 2.0f, -4.6f), new Vector3(0, 1.0f, 0), 38);
            s.SunDir(45, -35, 1.2f);
            s.Background(new Color(0.12f, 0.13f, 0.16f));
        }

        // ---------------- VAT ----------------
        static VatBaker.Result s_Vat;
        const int VatFrames = 48;
        static void EnsureVat()
        {
            if (s_Vat.mesh != null) return;
            var baseMesh = VatBaker.Tentacle();
            var rest = baseMesh.vertices;
            s_Vat = VatBaker.Bake(baseMesh, VatFrames, f => VatBaker.TentacleFrame(rest, f, VatFrames));
            s_Vat.mesh.hideFlags = s_Vat.position.hideFlags = s_Vat.normal.hideFlags = HideFlags.DontSave;
        }

        // 把位置贴图可视化：按包围盒把 xyz 映射到 0..1 显示
        static Texture2D VisualizeVat(Texture2D pos, Bounds b)
        {
            var px = pos.GetPixels();
            var outPx = new Color[px.Length];
            for (int i = 0; i < px.Length; i++)
            {
                var p = new Vector3(px[i].r, px[i].g, px[i].b) - b.min;
                outPx[i] = new Color(p.x / b.size.x, p.y / b.size.y, p.z / b.size.z, 1);
            }
            var t = new Texture2D(pos.width, pos.height, TextureFormat.RGBA32, false, true) { filterMode = FilterMode.Point, hideFlags = HideFlags.DontSave };
            t.SetPixels(outPx); t.Apply(false);
            return t;
        }

        [BookShot("ch17-vat", W = 640, H = 480, Panels = 2)]
        static void Vat(Shot s)
        {
            EnsureVat();
            if (s.Panel == 0)
            {
                s.Background(new Color(0.95f, 0.95f, 0.95f));
                s.Cam.orthographic = true; s.Cam.orthographicSize = 0.5f;
                s.Cam.transform.SetPositionAndRotation(new Vector3(0, 0, -5), Quaternion.identity);
                var m = s.Mat("Universal Render Pipeline/Unlit");
                m.SetTexture("_BaseMap", VisualizeVat(s_Vat.position, s_Vat.mesh.bounds));
                // 只显示靠近触手尖端的后 40% 顶点（列），纵向是全部 48 帧
                m.SetTextureScale("_BaseMap", new Vector2(0.4f, 1));
                m.SetTextureOffset("_BaseMap", new Vector2(0.6f, 0));
                var q = s.Quad(m, Vector3.zero);
                q.transform.localScale = new Vector3(1.25f, 0.92f, 1);
                return;
            }
            s.Floor();
            for (int i = 0; i < 5; i++)
            {
                var m = s.Mat("Cookbook/Ch17/VAT");
                m.SetTexture("_PosTex", s_Vat.position);
                m.SetTexture("_NrmTex", s_Vat.normal);
                m.SetFloat("_Frame", i * 4.5f);           // 同一份数据，不同的帧偏移
                var go = new GameObject("Tentacle");
                go.transform.position = new Vector3(-2.0f + i * 1.0f, 0, 0.3f);
                go.AddComponent<MeshFilter>().sharedMesh = s_Vat.mesh;
                go.AddComponent<MeshRenderer>().sharedMaterial = m;
            }
            s.LookAt(new Vector3(0, 1.9f, -5.6f), new Vector3(0, 1.1f, 0.3f), 40);
            s.SunDir(40, -30, 1.3f);
        }
    }
}
