// 第 12 章配图
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch12
{
    static class Shots
    {
        // ---------- 小工具 ----------
        static void Kw(Material m, string prefix, string[] opts, int pick)
        {
            for (int i = 0; i < opts.Length; i++)
                if (i == pick) m.EnableKeyword(prefix + opts[i]); else m.DisableKeyword(prefix + opts[i]);
        }

        // 深色哑光地面 + 灰蓝背景：材质展示用的“摄影棚”
        static void Studio(Shot s, float floorGray = 0.18f)
        {
            var f = s.Lit(new Color(floorGray, floorGray, floorGray), 0, 0.25f);
            s.Floor(f);
            s.Background(new Color(0.16f, 0.18f, 0.21f));
        }

        // 程序生成“发丝噪声”：沿 V 方向几乎不变，沿 U 方向逐列随机
        static Texture2D StrandNoise(Shot s)
        {
            const int W = 512, H = 64;
            var t = new Texture2D(W, H, TextureFormat.RGBA32, true, true) { wrapMode = TextureWrapMode.Repeat, name = "StrandNoise" };
            var rnd = new System.Random(3);
            // 两层一维值噪声：低频 = 一绺一绺的发束，高频 = 单根发丝
            var lo = new float[33]; var hi = new float[W];
            for (int k = 0; k < lo.Length; k++) lo[k] = (float)rnd.NextDouble();
            lo[32] = lo[0];
            for (int x = 0; x < W; x++) hi[x] = (float)rnd.NextDouble();
            var px = new Color[W * H];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    float f = x / (float)W * 32f; int i0 = (int)f; float w = f - i0;
                    w = w * w * (3 - 2 * w);
                    float v = 0.7f * Mathf.Lerp(lo[i0], lo[i0 + 1], w) + 0.3f * hi[x];
                    px[y * W + x] = new Color(v, v, v, 1);
                }
            t.SetPixels(px); t.Apply();
            s.Temp.Add(t);
            return t;
        }

        // 圆盘网格：UV 与 XZ 平面坐标对应（中心 0.5,0.5），给径向拉丝用
        static Mesh Disc(float radius, int rings, int segs)
        {
            var v = new System.Collections.Generic.List<Vector3>();
            var uv = new System.Collections.Generic.List<Vector2>();
            var idx = new System.Collections.Generic.List<int>();
            v.Add(Vector3.zero); uv.Add(new Vector2(0.5f, 0.5f));
            for (int r = 1; r <= rings; r++)
                for (int k = 0; k < segs; k++)
                {
                    float a = k * Mathf.PI * 2 / segs, rr = radius * r / rings;
                    var p = new Vector3(Mathf.Cos(a) * rr, 0, Mathf.Sin(a) * rr);
                    v.Add(p); uv.Add(new Vector2(p.x / radius * 0.5f + 0.5f, p.z / radius * 0.5f + 0.5f));
                }
            for (int k = 0; k < segs; k++) { idx.Add(0); idx.Add(1 + (k + 1) % segs); idx.Add(1 + k); }
            for (int r = 1; r < rings; r++)
                for (int k = 0; k < segs; k++)
                {
                    int a = 1 + (r - 1) * segs + k, b = 1 + (r - 1) * segs + (k + 1) % segs;
                    int c = a + segs, d = b + segs;
                    idx.Add(a); idx.Add(b); idx.Add(c); idx.Add(b); idx.Add(d); idx.Add(c);
                }
            var m = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
            m.SetVertices(v); m.SetUVs(0, uv); m.SetTriangles(idx, 0);
            m.RecalculateNormals(); m.RecalculateTangents(); m.RecalculateBounds();
            return m;
        }

        // 两排球：上排金属（金），下排电介质（红），光滑度从左到右 0.1 → 0.95
        static void SphereGrid(Shot s, System.Func<Color, float, float, Material> make)
        {
            Color gold = new Color(1.0f, 0.78f, 0.34f), red = new Color(0.7f, 0.08f, 0.06f);
            for (int row = 0; row < 2; row++)
                s.SphereRow(5, i =>
                {
                    float sm = Mathf.Lerp(0.1f, 0.95f, i / 4f);
                    return row == 0 ? make(gold, 1, sm) : make(red, 0, sm);
                }, y: row == 0 ? 1.55f : 0.5f, step: 1.05f, scale: 0.95f);
        }

        // ---------- 12.2 基准 ----------
        [BookShot("ch12-base-check", W = 640, H = 420, Panels = 2)]
        static void BaseCheck(Shot s)
        {
            s.Floor();
            SphereGrid(s, (c, metal, sm) =>
            {
                if (s.Panel == 0) return s.Lit(c, metal, sm);
                var m = s.Mat("Cookbook/Ch12/BaseGGX");
                m.SetColor("_BaseColor", c); m.SetFloat("_Metallic", metal); m.SetFloat("_Smoothness", sm);
                return m;
            });
            s.LookAt(new Vector3(0, 1.6f, -7.2f), new Vector3(0, 1.0f, 0), 34);
        }

        // ---------- 12.3 清漆 ----------
        static Material CarPaint(Shot s, float coat, float energy, float flakes = 0.2f)
        {
            var m = s.Mat("Cookbook/Ch12/ClearCoat");
            m.SetColor("_BaseColor", new Color(0.55f, 0.03f, 0.03f));
            m.SetFloat("_Metallic", 0.6f); m.SetFloat("_Smoothness", 0.45f);
            m.SetFloat("_FlakeDensity", 300); m.SetFloat("_FlakeStrength", flakes);
            m.SetFloat("_CoatMask", coat); m.SetFloat("_CoatSmoothness", 0.95f);
            m.SetFloat("_CoatEnergy", energy); m.SetFloat("_CoatAffectBase", 1);
            return m;
        }

        [BookShot("ch12-clearcoat", W = 640, H = 480, Panels = 3)]
        static void ClearCoatPanels(Shot s)
        {
            Studio(s);
            var m = s.Panel == 0 ? CarPaint(s, 0, 1) : s.Panel == 1 ? CarPaint(s, 1, 1) : CarPaint(s, 1, 0);
            s.Knot(m, new Vector3(0, 0.95f, 0), 1.15f);
            s.SunDir(35, -40, 1.6f);
            s.Point(new Vector3(-1.8f, 2.2f, -1.5f), new Color(1f, 0.95f, 0.9f), 3, 6);
            s.LookAt(new Vector3(0, 1.7f, -3.6f), new Vector3(0, 0.9f, 0), 36);
        }

        [BookShot("ch12-clearcoat-row", W = 960, H = 330)]
        static void ClearCoatRow(Shot s)
        {
            Studio(s);
            s.SphereRow(5, i =>
            {
                var m = CarPaint(s, i / 4f, 1, 0.25f);
                m.SetFloat("_Smoothness", 0.3f);
                return m;
            }, y: 0.5f, step: 1.1f, scale: 0.95f);
            s.SunDir(40, -35, 1.5f);
            s.LookAt(new Vector3(0, 1.1f, -5.6f), new Vector3(0, 0.5f, 0), 33);
        }

        [BookShot("ch12-clearcoat-urp", W = 640, H = 360, Panels = 2)]
        static void ClearCoatVsUrp(Shot s)
        {
            Studio(s);
            Color col = new Color(0.08f, 0.2f, 0.55f);
            for (int k = 0; k < 3; k++)
            {
                const float baseSm = 0.4f;
                float coatSm = new[] { 0.6f, 0.8f, 0.95f }[k];
                Material m;
                if (s.Panel == 0)
                {
                    m = s.Mat("Universal Render Pipeline/Complex Lit");
                    m.SetColor("_BaseColor", col); m.SetFloat("_Metallic", 0.3f); m.SetFloat("_Smoothness", baseSm);
                    m.SetFloat("_ClearCoat", 1); m.EnableKeyword("_CLEARCOAT");
                    m.SetFloat("_ClearCoatMask", 1); m.SetFloat("_ClearCoatSmoothness", coatSm);
                }
                else
                {
                    m = s.Mat("Cookbook/Ch12/ClearCoat");
                    m.SetColor("_BaseColor", col); m.SetFloat("_Metallic", 0.3f); m.SetFloat("_Smoothness", baseSm);
                    m.SetFloat("_FlakeStrength", 0); m.SetFloat("_CoatMask", 1); m.SetFloat("_CoatSmoothness", coatSm);
                    m.SetFloat("_CoatEnergy", 1); m.SetFloat("_CoatAffectBase", 1);
                }
                s.Sphere(m, new Vector3((k - 1) * 1.15f, 0.55f, 0), 1.0f);
            }
            s.SunDir(50, -30, 1.5f);   // 与天空盒里太阳的方向一致，直接光高光和环境反射里的太阳重合
            s.LookAt(new Vector3(0, 1.2f, -5.0f), new Vector3(0, 0.55f, 0), 34);
        }

        // 白炉测试（Furnace Test）：均匀的 0.5 灰环境，没有直接光。
        // 能量守恒的材质应该和背景“融为一体”，多出来的能量会在边缘发亮
        [BookShot("ch12-clearcoat-furnace", W = 640, H = 400, Panels = 3)]
        static void ClearCoatFurnace(Shot s)
        {
            //#region furnace
            const float L = 0.5f;
            var cube = new Cubemap(16, TextureFormat.RGBAHalf, true) { hideFlags = HideFlags.DontSave };
            var px = new Color[16 * 16];
            for (int k = 0; k < px.Length; k++) px[k] = new Color(L, L, L, 1);
            for (int f = 0; f < 6; f++) cube.SetPixels(px, (CubemapFace)f);
            cube.Apply(true);
            s.Temp.Add(cube);
            RenderSettings.customReflectionTexture = cube;
            var sh = new UnityEngine.Rendering.SphericalHarmonicsL2();
            sh.AddAmbientLight(new Color(L, L, L));
            RenderSettings.ambientProbe = sh;
            s.Background(new Color(L, L, L).gamma);   // 背景色按 sRGB 解释，要换算成线性 0.5
            s.Sun.intensity = 0;
            //#endregion

            var m = s.Mat("Cookbook/Ch12/ClearCoat");
            m.SetColor("_BaseColor", Color.white);
            m.SetFloat("_Metallic", 0); m.SetFloat("_Smoothness", 0.5f); m.SetFloat("_FlakeStrength", 0);
            m.SetFloat("_CoatMask", s.Panel == 0 ? 0 : 1); m.SetFloat("_CoatSmoothness", 0.9f);
            m.SetFloat("_CoatEnergy", s.Panel == 2 ? 0 : 1); m.SetFloat("_CoatAffectBase", 1);
            s.Sphere(m, new Vector3(0, 0, 0), 1.6f);
            s.LookAt(new Vector3(0, 0, -4.2f), Vector3.zero, 34);
        }

        // ---------- 12.4 各向异性 ----------
        static Material Brushed(Shot s, float aniso, int dir, float ibl = 1)
        {
            var m = s.Mat("Cookbook/Ch12/Anisotropic");
            m.SetColor("_BaseColor", new Color(0.93f, 0.92f, 0.9f));
            m.SetFloat("_Smoothness", 0.62f); m.SetFloat("_Anisotropy", aniso);
            m.SetTexture("_BrushTex", s.CoreTex("noise_streak"));
            m.SetFloat("_BrushStrength", 0.25f); m.SetFloat("_AnisoIBL", ibl);
            Kw(m, "_DIR_", new[] { "TANGENT", "BITANGENT", "RADIAL" }, dir);
            return m;
        }

        [BookShot("ch12-aniso", W = 640, H = 480, Panels = 3)]
        static void AnisoPanels(Shot s)
        {
            Studio(s);
            float k = new[] { 0f, 0.5f, 0.85f }[s.Panel];
            s.Knot(Brushed(s, k, 0), new Vector3(0, 0.95f, 0), 1.15f);
            s.SunDir(30, -20, 1.2f);
            s.Point(new Vector3(-1.2f, 1.8f, -1.6f), new Color(1f, 0.9f, 0.8f), 4, 5);
            s.Point(new Vector3(1.4f, 1.2f, -1.4f), new Color(0.7f, 0.85f, 1f), 3, 5);
            s.LookAt(new Vector3(0, 1.7f, -3.6f), new Vector3(0, 0.9f, 0), 36);
        }

        [BookShot("ch12-aniso-disc", W = 640, H = 420, Panels = 2)]
        static void AnisoDisc(Shot s)
        {
            Studio(s, 0.1f);
            var m = Brushed(s, s.Panel == 0 ? 0f : 0.85f, 2);
            m.SetFloat("_Smoothness", 0.7f);
            m.SetTextureScale("_BrushTex", new Vector2(1, 1));
            var go = s.MeshObj(Disc(1.4f, 48, 160), m, new Vector3(0, 0.02f, 0), 1, "Disc");
            // 主光放在相机身后，它的镜面反射不会落进画面；高光全部来自两盏点光
            s.SunDir(50, -30, 0.6f);
            s.Point(new Vector3(-0.7f, 1.0f, 0.6f), new Color(1f, 0.95f, 0.88f), 1.0f, 6);
            s.Point(new Vector3(0.8f, 0.8f, -0.3f), new Color(0.75f, 0.85f, 1f), 0.5f, 5);
            s.LookAt(new Vector3(0, 2.6f, -2.4f), new Vector3(0, 0, 0.1f), 42);
        }

        [BookShot("ch12-aniso-ibl", W = 640, H = 400, Panels = 2)]
        static void AnisoIbl(Shot s)
        {
            Studio(s);
            // 球体的切线沿纬线（水平），拉丝水平 → 环境里的地平线应被竖直方向拉开
            var m = Brushed(s, 0.85f, 0, s.Panel);
            m.SetFloat("_Smoothness", 0.85f); m.SetFloat("_BrushStrength", 0.1f);
            s.Sphere(m, new Vector3(0, 0.85f, 0), 1.5f);
            s.Sun.intensity = 0.0f;   // 只看环境反射
            s.LookAt(new Vector3(0, 1.2f, -3.6f), new Vector3(0, 0.85f, 0), 36);
        }

        // ---------- 12.5 头发 ----------
        static Material Hair(Shot s, int mode, float shiftAmount = 0.3f)
        {
            var m = s.Mat("Cookbook/Ch12/HairKK");
            Kw(m, "_MODE_", new[] { "BLINNPHONG", "SINGLE", "DUAL" }, mode);
            m.SetTexture("_ShiftTex", StrandNoise(s));
            m.SetFloat("_StrandAlongV", 1); m.SetFloat("_ShiftAmount", shiftAmount);
            return m;
        }

        static void HairScene(Shot s, Material m)
        {
            Studio(s);
            var head = s.Sphere(m, new Vector3(0, 1.0f, 0), 1.6f);
            head.transform.rotation = Quaternion.Euler(0, 0, 0);
            s.SunDir(35, -25, 1.5f);
            s.LookAt(new Vector3(0, 1.45f, -3.6f), new Vector3(0, 0.95f, 0), 34);
        }

        [BookShot("ch12-hair", W = 640, H = 480, Panels = 3)]
        static void HairPanels(Shot s) => HairScene(s, Hair(s, s.Panel));

        [BookShot("ch12-hair-shift", W = 640, H = 420, Panels = 2)]
        static void HairShift(Shot s) => HairScene(s, Hair(s, 2, s.Panel == 0 ? 0f : 0.3f));

        // ---------- 12.6 布料 ----------
        static Material Velvet(Shot s, int model, float sheenRough = 0.45f)
        {
            var m = s.Mat("Cookbook/Ch12/Cloth");
            Kw(m, "_MODEL_", new[] { "GGX", "CHARLIE", "SUBSURFACE" }, model);
            m.SetFloat("_SheenRoughness", sheenRough);
            m.SetFloat("_WeaveScale", 90);
            m.SetColor("_BaseColor", new Color(0.22f, 0.015f, 0.04f));
            m.SetColor("_SheenColor", new Color(0.95f, 0.55f, 0.6f));
            m.SetColor("_SubsurfaceColor", new Color(0.6f, 0.08f, 0.15f));
            m.SetFloat("_Wrap", 0.6f);
            return m;
        }

        [BookShot("ch12-cloth", W = 640, H = 480, Panels = 3)]
        static void ClothPanels(Shot s)
        {
            Studio(s, 0.12f);
            var m = Velvet(s, s.Panel);
            // 一个“抱枕”：压扁的球 + 一个纽结
            var pillow = s.Sphere(m, new Vector3(-0.55f, 0.38f, 0.2f), 1);
            pillow.transform.localScale = new Vector3(1.5f, 0.75f, 1.2f);
            s.Knot(m, new Vector3(0.75f, 0.85f, -0.1f), 0.75f);
            // 逆光为主：布料的绒毛反光主要出现在轮廓和掠射角
            s.SunDir(25, 160, 2.2f);
            s.Point(new Vector3(-1.5f, 1.6f, -2.0f), new Color(1f, 0.95f, 0.9f), 1.2f, 6);
            s.LookAt(new Vector3(0, 1.6f, -3.4f), new Vector3(0.05f, 0.55f, 0), 38);
        }

        [BookShot("ch12-cloth-row", W = 960, H = 330)]
        static void ClothRow(Shot s)
        {
            Studio(s, 0.12f);
            s.SphereRow(5, i => Velvet(s, 1, Mathf.Lerp(0.15f, 1f, i / 4f)), y: 0.5f, step: 1.1f, scale: 0.95f);
            s.SunDir(25, 160, 2.2f);
            s.Point(new Vector3(0, 1.6f, -2.5f), new Color(1f, 0.95f, 0.9f), 1.5f, 8);
            s.LookAt(new Vector3(0, 1.1f, -5.6f), new Vector3(0, 0.5f, 0), 33);
        }

        // ---------- 12.7 皮肤 ----------
        static Texture2D s_Lut;
        static Texture2D Lut() { if (s_Lut == null) { s_Lut = SkinLutBaker.Generate(); s_Lut.hideFlags = HideFlags.DontSave; } return s_Lut; }

        [BookShot("ch12-skin-lut", W = 960, H = 300)]
        static void SkinLutShot(Shot s)
        {
            s.Background(Color.white);
            var m = s.Mat("Universal Render Pipeline/Unlit");
            m.SetTexture("_BaseMap", Lut());
            var q = s.Quad(m, Vector3.zero, 1);
            q.transform.localScale = new Vector3(3.2f, 1f, 1);
            s.Cam.orthographic = true; s.Cam.orthographicSize = 0.5f;
            s.Cam.transform.position = new Vector3(0, 0, -2); s.Cam.transform.rotation = Quaternion.identity;
            s.Sun.intensity = 0;
        }

        static Material SkinMat(Shot s, int model)
        {
            var m = s.Mat("Cookbook/Ch12/Skin");
            Kw(m, "_DIFFUSE_", new[] { "LAMBERT", "WRAP", "LUT" }, model);
            m.SetTexture("_SkinLUT", Lut());
            m.SetFloat("_CurvatureScale", 0.5f);
            m.SetFloat("_Smoothness", 0.55f);
            return m;
        }

        [BookShot("ch12-skin", W = 640, H = 420, Panels = 3)]
        static void SkinPanels(Shot s)
        {
            Studio(s, 0.25f);
            var amb = RenderSettings.ambientProbe; amb *= 0.35f; RenderSettings.ambientProbe = amb;   // 压暗环境光，看清明暗交界
            var m = SkinMat(s, s.Panel);
            s.Sphere(m, new Vector3(-0.55f, 0.6f, 0.3f), 1.2f);
            s.Sphere(m, new Vector3(0.62f, 0.4f, -0.1f), 0.8f);
            s.Sphere(m, new Vector3(0.35f, 0.18f, -0.75f), 0.36f);
            s.Sphere(m, new Vector3(1.0f, 0.12f, -0.75f), 0.24f);
            s.SunDir(20, 75, 1.8f);   // 侧光，让明暗交界线落在画面中间
            s.LookAt(new Vector3(0, 1.3f, -3.4f), new Vector3(0.15f, 0.45f, 0), 36);
        }

        // ---------- 12.8 薄片透射 ----------
        [BookShot("ch12-leaf", W = 640, H = 480, Panels = 3)]
        static void LeafPanels(Shot s)
        {
            s.Background(new Color(0.12f, 0.14f, 0.16f));
            var m = s.Mat("Cookbook/Ch12/Translucent");
            m.SetFloat("_Transmission", s.Panel == 0 ? 0 : 1);
            m.SetFloat("_UseThickness", s.Panel == 2 ? 1 : 0);
            var rnd = new System.Random(5);
            for (int k = 0; k < 5; k++)
            {
                var q = s.Quad(m, new Vector3(-1.1f + k * 0.55f, 0.7f + (k % 2) * 0.35f, k * 0.15f), 1);
                q.transform.localScale = new Vector3(0.75f, 1.25f, 1);
                q.transform.rotation = Quaternion.Euler(-10 + (float)rnd.NextDouble() * 20, (float)rnd.NextDouble() * 30 - 15, -25 + k * 12);
            }
            // 太阳在叶子背后、略高处，朝相机方向照射
            s.SunDir(18, 175, 2.2f);
            s.LookAt(new Vector3(0, 1.0f, -3.2f), new Vector3(0, 0.9f, 0), 40);
        }

        // ---------- 12.9 薄膜干涉 ----------
        static Material Film(Shot s, int mode, float thickness, float variation, float baseF0 = 0.3f)
        {
            var m = s.Mat("Cookbook/Ch12/ThinFilm");
            Kw(m, "_FILM_", new[] { "SPECTRAL", "RGB3", "BELCOUR" }, mode);
            m.SetFloat("_Thickness", thickness); m.SetFloat("_ThicknessVar", variation);
            m.SetTexture("_ThicknessTex", s.CoreTex("noise_fbm"));
            m.SetFloat("_BaseF0", baseF0);
            m.SetFloat("_FilmIOR", 1.6f);
            return m;
        }

        [BookShot("ch12-thinfilm-row", W = 960, H = 300)]
        static void ThinFilmRow(Shot s)
        {
            Studio(s, 0.12f);
            s.SphereRow(6, i => Film(s, 0, 150 + i * 100, 0), y: 0.5f, step: 1.05f, scale: 0.95f);
            s.SunDir(50, -30, 1.2f);
            s.LookAt(new Vector3(0, 1.2f, -5.0f), new Vector3(0, 0.45f, 0), 34);
        }

        [BookShot("ch12-thinfilm", W = 640, H = 480, Panels = 3)]
        static void ThinFilmPanels(Shot s)
        {
            Studio(s, 0.12f);
            var m = Film(s, s.Panel, 450, 250);
            m.SetTextureScale("_ThicknessTex", new Vector2(0.5f, 1));
            s.Knot(m, new Vector3(0, 0.95f, 0), 1.15f);
            s.SunDir(35, -30, 1.3f);
            s.LookAt(new Vector3(0, 1.7f, -3.6f), new Vector3(0, 0.9f, 0), 36);
        }

        // ---------- 12.10 材质展台 ----------
        [BookShot("ch12-gallery", W = 960, H = 440)]
        static void Gallery(Shot s)
        {
            Studio(s, 0.2f);
            s.Knot(CarPaint(s, 1, 1), new Vector3(-2.3f, 0.75f, 0.3f), 0.85f);
            var tor = s.Torus(Brushed(s, 0.85f, 0), new Vector3(-0.95f, 0.55f, 0.0f), 0.48f, 0.2f);
            tor.transform.rotation = Quaternion.Euler(-65, 0, 0);
            s.Sphere(Hair(s, 2), new Vector3(0.2f, 0.5f, 0.1f), 1.0f);
            var pillow = s.Sphere(Velvet(s, 2), new Vector3(1.35f, 0.3f, 0.1f), 1);
            pillow.transform.localScale = new Vector3(1.05f, 0.6f, 0.9f);
            s.Sphere(SkinMat(s, 2), new Vector3(2.35f, 0.42f, 0.0f), 0.84f);
            s.Sphere(Film(s, 0, 420, 200), new Vector3(0.75f, 0.28f, -0.85f), 0.56f);
            s.SunDir(35, -35, 1.5f);
            s.Point(new Vector3(-2.2f, 1.8f, -1.2f), new Color(1f, 0.92f, 0.85f), 0.8f, 5);
            s.LookAt(new Vector3(0, 1.8f, -5.2f), new Vector3(0, 0.45f, 0), 36);
        }
    }
}
