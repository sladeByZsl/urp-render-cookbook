// 第 15 章配图
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch15
{
    static class Shots15
    {
        static readonly Color Paper = new Color(0.96f, 0.94f, 0.88f);

        // 三件套静物：纽结、球、方块
        static void StillLife(Shot s, Material knot, Material sphere, Material cube)
        {
            s.Knot(knot, new Vector3(-0.95f, 0.95f, 0.35f), 1.0f);
            s.Sphere(sphere, new Vector3(1.15f, 0.55f, 0.1f), 1.1f);
            var c = s.Cube(cube, new Vector3(0.15f, 0.35f, -0.95f), 0.7f);
            c.transform.rotation = Quaternion.Euler(0, 35, 0);
            s.LookAt(new Vector3(0, 2.0f, -4.8f), new Vector3(0, 0.55f, 0), 38);
        }

        static Material Unlit(Shot s, Texture tex)
        {
            var m = s.Mat("Universal Render Pipeline/Unlit");
            m.SetTexture("_BaseMap", tex);
            return m;
        }

        // ---------------- Gooch ----------------
        [BookShot("ch15-gooch", W = 640, H = 480, Panels = 3)]
        static void Gooch(Shot s)
        {
            s.Background(new Color(0.8f, 0.82f, 0.85f));
            s.Floor(s.Lit(new Color(0.78f, 0.78f, 0.78f), 0, 0.1f));
            Color[] cols = { new Color(0.8f, 0.25f, 0.2f), new Color(0.25f, 0.5f, 0.8f), new Color(0.9f, 0.75f, 0.3f) };
            Material M(int i)
            {
                if (s.Panel == 0) return s.Lit(cols[i], 0, 0.6f);
                var m = s.Mat("Cookbook/Ch15/Gooch");
                m.SetColor("_BaseColor", cols[i]);
                if (s.Panel == 1) { m.SetFloat("_OutlineWidth", 0); m.SetFloat("_SpecStrength", 0); }
                return m;
            }
            StillLife(s, M(0), M(1), M(2));
            s.SunDir(42, -35, 1.3f);
        }

        // ---------------- Hatching ----------------
        static Texture2D s_H0, s_H1, s_HPreview;
        static void EnsureHatch()
        {
            if (s_H0 != null) return;
            var lv = HatchTextures.BuildLevels(256);
            HatchTextures.Pack(lv, 256, out s_H0, out s_H1);
            s_HPreview = HatchTextures.Preview(lv, 256);
            s_H0.hideFlags = s_H1.hideFlags = s_HPreview.hideFlags = HideFlags.DontSave;
        }

        [BookShot("ch15-tam", W = 960, H = 152)]
        static void Tam(Shot s)
        {
            EnsureHatch();
            s.Background(Color.white);
            s.Cam.orthographic = true; s.Cam.orthographicSize = 0.5f;
            s.Cam.transform.position = new Vector3(0, 0, -5); s.Cam.transform.rotation = Quaternion.identity;
            var q = s.Quad(Unlit(s, s_HPreview), Vector3.zero);
            q.transform.localScale = new Vector3((float)s_HPreview.width / s_HPreview.height, 1, 1);
        }

        [BookShot("ch15-hatching", W = 640, H = 480, Panels = 3)]
        static void Hatching(Shot s)
        {
            EnsureHatch();
            s.Background(Paper);
            Material H(float scale, Color tint)
            {
                var m = s.Mat("Cookbook/Ch15/Hatching");
                m.SetTexture("_Hatch0", s_H0); m.SetTexture("_Hatch1", s_H1);
                m.SetFloat("_HatchScale", scale);
                m.SetFloat("_ScreenSpace", s.Panel == 1 ? 1 : 0);
                if (s.Panel == 2)
                {
                    m.SetColor("_BaseColor", tint); m.SetFloat("_Tint", 0.75f);
                    m.SetColor("_InkColor", new Color(0.12f, 0.1f, 0.3f));
                }
                return m;
            }
            var floor = H(30, new Color(0.9f, 0.85f, 0.7f));
            floor.SetFloat("_OutlineWidth", 0);
            floor.SetFloat("_Exposure", 1.3f);
            s.Floor(floor);
            StillLife(s, H(1.2f, new Color(0.95f, 0.45f, 0.35f)), H(3f, new Color(0.45f, 0.65f, 0.95f)), H(1.5f, new Color(0.95f, 0.85f, 0.4f)));
            s.SunDir(40, -40, 1.3f);
        }

        // ---------------- Halftone ----------------
        [BookShot("ch15-halftone", W = 640, H = 480, Panels = 3)]
        static void Halftone(Shot s)
        {
            s.Background(Paper);
            string[] kw = { "_STYLE_OFF", "_STYLE_MONO", "_STYLE_CMYK" };
            Material M(Color c)
            {
                var m = s.Mat("Cookbook/Ch15/Halftone");
                m.SetColor("_BaseColor", c);
                m.SetFloat("_Style", s.Panel);
                foreach (var k in kw) m.DisableKeyword(k);
                m.EnableKeyword(kw[s.Panel]);
                m.SetFloat("_CellSize", 7);
                return m;
            }
            s.Floor(M(new Color(0.75f, 0.85f, 0.7f)));
            StillLife(s, M(new Color(0.85f, 0.25f, 0.25f)), M(new Color(0.2f, 0.5f, 0.85f)), M(new Color(0.95f, 0.8f, 0.25f)));
            s.SunDir(40, -40, 1.2f);
        }

        // ---------------- Watercolor ----------------
        [BookShot("ch15-watercolor", W = 640, H = 480, Panels = 2)]
        static void Watercolor(Shot s)
        {
            s.Background(Paper);
            Material M(Color c, float density = 1.1f)
            {
                if (s.Panel == 0) return s.Lit(c, 0, 0.3f);
                var m = s.Mat("Cookbook/Ch15/Watercolor");
                m.SetColor("_BaseColor", c);
                m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
                m.SetFloat("_Density", density);
                return m;
            }
            s.Floor(M(new Color(0.85f, 0.8f, 0.68f), 0.55f));
            StillLife(s, M(new Color(0.3f, 0.6f, 0.65f)), M(new Color(0.9f, 0.35f, 0.3f)), M(new Color(0.95f, 0.75f, 0.25f)));
            s.SunDir(40, -40, 1.3f);
        }

        // ---------------- Retro / PS1 ----------------
        static Texture2D PixelTex(int size, System.Func<int, int, Color> f, string name)
        {
            var t = new Texture2D(size, size, TextureFormat.RGBA32, false, false)
            { name = name, filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Repeat, hideFlags = HideFlags.DontSave };
            var px = new Color[size * size];
            for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) px[y * size + x] = f(x, y);
            t.SetPixels(px); t.Apply();
            return t;
        }
        static float Hash(int x, int y) { uint h = (uint)(x * 374761393 + y * 668265263); h = (h ^ (h >> 13)) * 1274126177u; return (h & 0xffff) / 65535f; }

        static Texture2D StoneTiles() => PixelTex(32, (x, y) =>
        {
            bool mortar = x % 16 == 0 || y % 16 == 0;
            int tile = (x / 16) + (y / 16) * 2;
            float n = Hash(x, y) * 0.15f + Hash(tile, 7) * 0.1f;
            return mortar ? new Color(0.25f, 0.22f, 0.2f) : new Color(0.55f + n, 0.5f + n, 0.42f + n * 0.8f);
        }, "StoneTiles");

        static Texture2D Crate() => PixelTex(32, (x, y) =>
        {
            bool border = x < 3 || y < 3 || x > 28 || y > 28;
            bool diag = Mathf.Abs(x - y) < 2 || Mathf.Abs(x - (31 - y)) < 2;
            bool plank = y % 8 == 0;
            float n = Hash(x, y) * 0.08f;
            if (border || diag) return new Color(0.42f + n, 0.26f + n, 0.12f);
            return plank ? new Color(0.45f, 0.3f, 0.15f) : new Color(0.7f + n, 0.5f + n, 0.26f);
        }, "Crate");

        [BookShot("ch15-retro", W = 640, H = 480, Panels = 3)]
        static void Retro(Shot s)
        {
            var stone = StoneTiles(); var crate = Crate();
            Material M(Texture2D tex, Vector2 tiling)
            {
                var m = s.Mat("Cookbook/Ch15/RetroPS1");
                m.SetTexture("_BaseMap", tex); m.SetTextureScale("_BaseMap", tiling);
                m.SetVector("_VirtualRes", new Vector4(128, 96, 0, 0));
                m.SetFloat("_VertexSnap", s.Panel == 2 ? 1 : 0);
                m.SetFloat("_Affine", s.Panel >= 1 ? 1 : 0);
                m.SetFloat("_PointSample", s.Panel >= 1 ? 1 : 0);
                m.SetFloat("_Quantize", s.Panel == 2 ? 1 : 0);
                m.SetFloat("_ColorBits", 3);
                return m;
            }
            s.Background(new Color(0.18f, 0.16f, 0.22f));
            s.Grid(M(stone, new Vector2(8, 8)), new Vector3(0, 0, 3), 16, 2);       // 只有 8 个三角形的大地板
            var wall = s.Grid(M(stone, new Vector2(8, 2)), new Vector3(0, 2, 7), 16, 2);
            wall.transform.rotation = Quaternion.Euler(-90, 0, 0);
            wall.transform.localScale = new Vector3(1, 1, 0.25f);
            var c1 = s.Cube(M(crate, Vector2.one), new Vector3(-1.1f, 0.5f, 0.6f), 1f); c1.transform.rotation = Quaternion.Euler(0, 25, 0);
            var c2 = s.Cube(M(crate, Vector2.one), new Vector3(0.9f, 0.4f, 1.8f), 0.8f); c2.transform.rotation = Quaternion.Euler(0, -15, 0);
            s.Cube(M(crate, Vector2.one), new Vector3(-0.9f, 1.25f, 0.7f), 0.5f).transform.rotation = Quaternion.Euler(0, 50, 0);
            s.LookAt(new Vector3(0.4f, 1.1f, -2.6f), new Vector3(0, 0.6f, 2f), 60);
            s.SunDir(35, -50, 1.2f);
        }

        // ---------------- Matcap ----------------
        static Texture2D s_McClay, s_McToon, s_McChrome;
        static void EnsureMatcaps()
        {
            if (s_McClay != null) return;
            s_McClay = MatcapGenerator.Build(256, MatcapGenerator.Clay, "Clay");
            s_McToon = MatcapGenerator.Build(256, MatcapGenerator.Toon, "Toon");
            s_McChrome = MatcapGenerator.Build(256, MatcapGenerator.Chrome, "Chrome");
            s_McClay.hideFlags = s_McToon.hideFlags = s_McChrome.hideFlags = HideFlags.DontSave;
        }

        // 在画面左上角放一张“贴图缩略图”
        static void Inset(Shot s, Texture2D tex, float size = 0.55f)
        {
            var t = s.Cam.transform;
            var mat = Unlit(s, DiscOnly(tex));
            mat.SetFloat("_AlphaClip", 1); mat.SetFloat("_Cutoff", 0.5f); mat.EnableKeyword("_ALPHATEST_ON");
            var q = s.Quad(mat, Vector3.zero, size);
            float dist = 3f;
            float h = Mathf.Tan(s.Cam.fieldOfView * 0.5f * Mathf.Deg2Rad) * dist;
            float w = h * 640f / 480f;
            q.transform.position = t.position + t.forward * dist - t.right * (w - size * 0.62f) + t.up * (h - size * 0.62f);
            q.transform.rotation = t.rotation;
        }

        // 把圆盘外的像素设为透明（配合 Alpha Clip），缩略图看起来就是一个“球”
        static Texture2D DiscOnly(Texture2D src)
        {
            int n = src.width;
            var px = src.GetPixels();
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                {
                    float u = (x + 0.5f) / n * 2 - 1, v = (y + 0.5f) / n * 2 - 1;
                    if (u * u + v * v > 0.98f) px[y * n + x] = new Color(0, 0, 0, 0);
                }
            var t = new Texture2D(n, n, TextureFormat.RGBA32, false) { hideFlags = HideFlags.DontSave };
            t.SetPixels(px); t.Apply();
            return t;
        }

        [BookShot("ch15-matcap", W = 640, H = 480, Panels = 3)]
        static void Matcap(Shot s)
        {
            EnsureMatcaps();
            var tex = new[] { s_McClay, s_McToon, s_McChrome }[s.Panel];
            var m = s.Mat("Cookbook/Ch15/MatcapStylized");
            m.SetTexture("_MatCap", tex);
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.Floor(s.Lit(new Color(0.3f, 0.3f, 0.32f), 0, 0.1f));
            s.Knot(m, new Vector3(-0.3f, 1.0f, 0.3f), 1.05f);
            s.Sphere(m, new Vector3(1.3f, 0.5f, -0.3f), 1.0f);
            s.Capsule(m, new Vector3(-1.75f, 0.75f, -0.4f), 0.75f);
            s.LookAt(new Vector3(0, 1.9f, -4.8f), new Vector3(0, 0.6f, 0), 38);
            s.SunDir(55, -30, 1.2f);
            Inset(s, tex);
        }

        [BookShot("ch15-matcap-fix", W = 640, H = 400, Panels = 2)]
        static void MatcapFix(Shot s)
        {
            EnsureMatcaps();
            var m = s.Mat("Cookbook/Ch15/MatcapStylized");
            m.SetTexture("_MatCap", s_McChrome);
            m.SetFloat("_PerspectiveFix", s.Panel);
            m.SetFloat("_ShadowStrength", 0);
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            for (int j = -1; j <= 1; j++)
                for (int i = 0; i < 5; i++)
                    s.Sphere(m, new Vector3(-2.6f + i * 1.3f, j * 1.2f, 0), 1.0f);
            s.LookAt(new Vector3(0, 0, -2.2f), Vector3.zero, 90);
        }

        // ---------------- Flat shading ----------------
        [BookShot("ch15-flat", W = 640, H = 480, Panels = 2)]
        static void Flat(Shot s)
        {
            var terrain = s.Mat("Cookbook/Ch15/FlatShading");
            terrain.SetFloat("_Terrain", 1);
            terrain.SetFloat("_Flat", s.Panel);
            terrain.SetTexture("_HeightTex", s.CoreTex("noise_fbm"));
            terrain.SetFloat("_HeightScale", 1.5f); terrain.SetFloat("_NoiseTiling", 0.05f);
            s.Grid(terrain, new Vector3(0, 0, 0.5f), 11, 30);
            var ball = s.Mat("Cookbook/Ch15/FlatShading");
            ball.SetFloat("_Flat", s.Panel);
            s.MeshObj(BarycentricBaker.Icosphere(1), ball, new Vector3(2.2f, 2.6f, 1.5f), 1.3f);
            s.LookAt(new Vector3(0, 8.5f, -11.5f), new Vector3(0, -0.3f, 0.8f), 40);
            s.SunDir(38, -55, 1.1f);
        }

        // ---------------- Wireframe ----------------
        [BookShot("ch15-wireframe", W = 640, H = 480, Panels = 3, Hdr = true)]
        static void Wireframe(Shot s)
        {
            Mesh B(PrimitiveType type, bool hide)
            {
                var go = GameObject.CreatePrimitive(type);
                var mesh = BarycentricBaker.Bake(go.GetComponent<MeshFilter>().sharedMesh, hide);
                Object.DestroyImmediate(go);
                return mesh;
            }
            if (s.Panel < 2)
            {
                bool hide = s.Panel == 1;
                var m = s.Mat("Cookbook/Ch15/BaryWireframe");
                s.Background(new Color(0.85f, 0.87f, 0.9f));
                s.Floor(s.Lit(new Color(0.7f, 0.7f, 0.72f), 0, 0.1f));
                s.MeshObj(B(PrimitiveType.Sphere, hide), m, new Vector3(-1.2f, 0.65f, 0.2f), 1.3f);
                s.MeshObj(B(PrimitiveType.Cube, hide), m, new Vector3(0.35f, 0.45f, -0.6f), 0.9f).transform.rotation = Quaternion.Euler(0, 30, 0);
                if (hide) s.MeshObj(BarycentricBaker.Bake(Meshes.Grid(1.4f, 6), true), m, new Vector3(1.45f, 0.75f, 0.6f)).transform.rotation = Quaternion.Euler(-70, -20, 0);
                else s.MeshObj(BarycentricBaker.Bake(BarycentricBaker.Icosphere(1), false), m, new Vector3(1.4f, 0.65f, 0.5f), 1.3f);
                s.LookAt(new Vector3(0, 2.0f, -4.4f), new Vector3(0, 0.55f, 0), 38);
                s.SunDir(45, -35, 1.2f);
            }
            else
            {
                var m = s.Mat("Cookbook/Ch15/HoloWireframe");
                m.SetFloat("_Phase", 0.3f);
                s.Background(new Color(0.01f, 0.015f, 0.03f));
                s.MeshObj(BarycentricBaker.Bake(BarycentricBaker.Icosphere(2), false), m, new Vector3(-1.2f, 0.75f, 0.2f), 1.4f);
                s.MeshObj(B(PrimitiveType.Capsule, true), m, new Vector3(0.25f, 0.9f, -0.4f), 0.9f);
                s.MeshObj(BarycentricBaker.Bake(Meshes.Grid(8, 16), true), m, new Vector3(0, 0, 1));
                s.MeshObj(B(PrimitiveType.Cube, true), m, new Vector3(1.45f, 0.5f, 0.4f), 0.9f).transform.rotation = Quaternion.Euler(0, 30, 0);
                s.LookAt(new Vector3(0, 2.0f, -4.4f), new Vector3(0, 0.55f, 0), 38);
                var p = s.Post();
                var b = p.Add<Bloom>(); b.intensity.Override(1.2f); b.threshold.Override(0.8f); b.scatter.Override(0.6f);
            }
        }
    }
}
