// 第 20 章配图
using System.Collections.Generic;
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch20
{
    static class Ch20Shots
    {
        static float Smooth(float a, float b, float x) { float t = Mathf.Clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); }

        /// 小块台地：中间一圈陡崖，用来看拉伸
        static float MesaHeight(float x, float z)
        {
            float r = Mathf.Sqrt(x * x + (z - 1.5f) * (z - 1.5f));
            float edge = r + (Heightfield.Fbm(x * 0.35f + 3, z * 0.35f + 1, 3) - 0.5f) * 2.2f;
            float mesa = 2.4f * Smooth(3.6f, 2.9f, edge);
            float bumps = (Heightfield.Fbm(x * 0.25f, z * 0.25f, 4) - 0.5f) * 0.8f;
            return mesa + bumps;
        }

        static GameObject Terrain(Shot s, Material m, float size, int n, System.Func<float, float, float> h)
        {
            var go = s.MeshObj(Heightfield.Build(size, n, h), m, Vector3.zero, 1, "Terrain");
            return go;
        }

        static Material AutoTerrainMat(Shot s)
        {
            var m = s.Mat("Cookbook/Ch20/AutoTerrain");
            m.SetTexture("_GrassTex", TerrainTextures.Grass);
            m.SetTexture("_SandTex", TerrainTextures.Sand);
            m.SetTexture("_RockTex", TerrainTextures.Rock);
            m.SetTexture("_RockNormal", TerrainTextures.RockNormal);
            m.SetTexture("_SnowTex", TerrainTextures.Snow);
            m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
            return m;
        }

        //#region keywordEnum
        // KeywordEnum 在材质创建时会按属性默认值打开第一个关键字（_UVMODE_MESHUV）。
        // 代码里切换时要“关掉全部、再打开一个”，并同步 float 属性，否则 Inspector 与实际变体不一致。
        static readonly string[] s_UVModes = { "_UVMODE_MESHUV", "_UVMODE_WORLDXZ", "_UVMODE_TRIPLANAR", "_UVMODE_WEIGHTS" };
        static void SetUVMode(Material m, int mode)
        {
            foreach (var k in s_UVModes) m.DisableKeyword(k);
            m.EnableKeyword(s_UVModes[mode]);
            m.SetFloat("_UVMode", mode);
        }
        //#endregion

        // ---------------------------------------------------------------- 20.1
        [BookShot("ch20-uv-stretch", W = 640, H = 420, Panels = 3)]
        static void UVStretch(Shot s)
        {
            var m = s.Mat("Cookbook/Ch20/UVCompare");
            m.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            m.SetTextureScale("_BaseMap", new Vector2(4, 4));
            m.SetFloat("_Tiling", 0.5f);
            m.SetFloat("_Sharpness", 6);
            SetUVMode(m, s.Panel);
            Terrain(s, m, 14, 160, MesaHeight);
            s.SunDir(42, -50, 1.4f);
            s.LookAt(new Vector3(-1.5f, 4.6f, -6.8f), new Vector3(0, 1.0f, 1.2f), 48);
        }

        // ---------------------------------------------------------------- 20.2
        [BookShot("ch20-triplanar-weights", W = 640, H = 420, Panels = 3)]
        static void TriplanarWeights(Shot s)
        {
            var m = s.Mat("Cookbook/Ch20/UVCompare");
            SetUVMode(m, 3);
            m.SetFloat("_Sharpness", new[] { 1f, 4f, 16f }[s.Panel]);
            s.MeshObj(Heightfield.Rock(1f, 128, 0.2f, 3f), m, new Vector3(0, 0.9f, 0), 1, "Rock");
            s.Floor(s.Lit(new Color(0.5f, 0.5f, 0.5f), 0, 0.1f));
            s.SunDir(40, -40, 1.0f);
            s.LookAt(new Vector3(1.6f, 2.4f, -3.6f), new Vector3(0, 0.8f, 0), 38);
        }

        [BookShot("ch20-triplanar-rock", W = 960, H = 460)]
        static void TriplanarRock(Shot s)
        {
            var m = s.Mat("Cookbook/Ch20/Triplanar");
            m.SetTexture("_BaseMap", TerrainTextures.Rock);
            m.SetTexture("_BumpMap", TerrainTextures.RockNormal);
            m.SetFloat("_Tiling", 0.35f);
            m.SetFloat("_Sharpness", 8);
            m.SetFloat("_Smoothness", 0.25f);
            var rock = s.MeshObj(Heightfield.Rock(1.4f, 160, 0.28f, 7f), m, new Vector3(-1.3f, 1.0f, 0.6f), 1, "Rock");
            rock.transform.rotation = Quaternion.Euler(0, 30, 0);
            var rock2 = s.MeshObj(Heightfield.Rock(0.8f, 128, 0.3f, 2f), m, new Vector3(1.6f, 0.55f, -0.2f), 1, "Rock2");
            rock2.transform.rotation = Quaternion.Euler(10, 70, 20);
            var cube = s.Cube(m, new Vector3(3.6f, 0.6f, 1.2f), 1.2f);
            cube.transform.rotation = Quaternion.Euler(0, 25, 0);
            var g = AutoTerrainMat(s);
            g.SetFloat("_RockSlope", 0.9f);
            g.SetFloat("_SandHeight", -10);
            Terrain(s, g, 30, 120, (x, z) => (Heightfield.Fbm(x * 0.1f, z * 0.1f, 3) - 0.5f) * 0.4f);
            s.SunDir(35, -55, 1.5f);
            s.LookAt(new Vector3(0.6f, 2.6f, -6.4f), new Vector3(0.8f, 0.7f, 0.4f), 42);
        }

        // ---------------------------------------------------------------- 20.3
        [BookShot("ch20-triplanar-normal", W = 480, H = 420, Panels = 4)]
        static void TriplanarNormal(Shot s)
        {
            var m = s.Mat("Cookbook/Ch20/Triplanar");
            m.SetTexture("_BaseMap", Texture2D.whiteTexture);     // 只看法线带来的明暗，颜色用纯灰
            m.SetTexture("_BumpMap", s.CoreTex("bricks_normal"));
            m.SetColor("_BaseColor", new Color(0.7f, 0.7f, 0.7f));
            m.SetFloat("_Smoothness", 0.2f);
            m.SetFloat("_Tiling", 0.9f);
            m.SetFloat("_Sharpness", 4);
            m.SetFloat("_BumpScale", 1.2f);
            m.SetFloat("_NormalMode", s.Panel);
            s.Sphere(m, new Vector3(0, 1.0f, 0), 1.9f);
            s.Floor(s.Lit(new Color(0.45f, 0.45f, 0.45f), 0, 0.1f));
            s.SunDir(20, -75, 2.2f);
            s.Background(new Color(0.16f, 0.18f, 0.2f));
            RenderSettings.ambientProbe = RenderSettings.ambientProbe * 0.35f;   // 压低环境光，让法线细节更明显
            s.LookAt(new Vector3(0, 1.6f, -4.2f), new Vector3(0, 0.95f, 0), 40);
        }

        // ---------------------------------------------------------------- 20.4
        [BookShot("ch20-auto-steps", W = 640, H = 420, Panels = 3)]
        static void AutoSteps(Shot s)
        {
            var m = AutoTerrainMat(s);
            if (s.Panel == 0) { m.SetFloat("_NoiseAmp", 0); m.SetFloat("_BlendDepth", 1f); m.SetFloat("_SlopeBand", 0.02f); }
            if (s.Panel == 1) { m.SetFloat("_NoiseAmp", 1.5f); m.SetFloat("_BlendDepth", 1f); }
            if (s.Panel == 2) { m.SetFloat("_NoiseAmp", 1.5f); m.SetFloat("_BlendDepth", 0.12f); }
            m.SetFloat("_SnowHeight", 2.3f);
            m.SetFloat("_SandHeight", -0.05f);
            m.SetFloat("_HeightBand", s.Panel == 0 ? 0.03f : 0.25f);
            Terrain(s, m, 14, 200, MesaHeight);
            s.SunDir(40, -50, 1.4f);
            s.LookAt(new Vector3(-1.6f, 3.4f, -4.6f), new Vector3(-0.4f, 1.0f, 0.6f), 50);
        }

        [BookShot("ch20-auto-terrain", W = 640, H = 400, Panels = 2)]
        static void AutoTerrain(Shot s)
        {
            var m = AutoTerrainMat(s);
            if (s.Panel == 0) m.EnableKeyword("_DEBUG_WEIGHTS");
            Terrain(s, m, 80, 320, Heightfield.DemoHeight);
            s.SunDir(32, -40, 1.5f);
            s.LookAt(new Vector3(-4f, 6.5f, -20f), new Vector3(2f, 3.5f, 10f), 50);
        }

        // ---------------------------------------------------------------- 20.5
        [BookShot("ch20-heightblend", W = 640, H = 420, Panels = 3)]
        static void HeightBlendShot(Shot s)
        {
            var m = s.Mat("Cookbook/Ch20/HeightBlend");
            m.SetTexture("_MapA", s.CoreTex("bricks_albedo"));
            m.SetTextureScale("_MapA", new Vector2(2, 2));
            m.SetTexture("_HeightA", s.CoreTex("bricks_height"));
            m.SetTexture("_NormalA", s.CoreTex("bricks_normal"));
            m.SetTexture("_MapB", TerrainTextures.Grass);
            m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
            m.SetFloat("_TilingB", 3);
            m.SetFloat("_MaskContrast", 2.2f);
            m.SetFloat("_UseHeight", s.Panel == 0 ? 0 : 1);
            m.SetFloat("_BlendDepth", s.Panel == 1 ? 0.25f : 0.05f);
            s.Grid(m, Vector3.zero, 4f, 8);
            s.SunDir(55, -30, 1.4f);
            s.Background(new Color(0.16f, 0.18f, 0.2f));
            s.LookAt(new Vector3(0, 3.3f, -2.1f), new Vector3(0, 0, 0.1f), 50);
        }

        // ---------------------------------------------------------------- 20.6
        //#region controlMap
        /// 程序化“画”一张 Control 图：R 草、G 土路、B 岩石（按坡度）、A 雪（按高度）
        static Texture2D BuildControl(float size, System.Func<float, float, float> h, int res = 256)
        {
            var t = new Texture2D(res, res, TextureFormat.RGBA32, false, true)
            { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear, hideFlags = HideFlags.DontSave };
            var px = new Color[res * res];
            for (int y = 0; y < res; y++)
                for (int x = 0; x < res; x++)
                {
                    float wx = (x / (res - 1f) - 0.5f) * size, wz = (y / (res - 1f) - 0.5f) * size;
                    float e = 0.3f;
                    float dx = (h(wx + e, wz) - h(wx - e, wz)) / (2 * e), dz = (h(wx, wz + e) - h(wx, wz - e)) / (2 * e);
                    float ny = 1f / Mathf.Sqrt(1 + dx * dx + dz * dz);
                    float rock = Smooth(0.82f, 0.74f, ny);
                    float snow = Smooth(6.5f, 8f, h(wx, wz)) * (1 - rock * 0.7f);
                    // 一条蜿蜒的小路：到正弦曲线的距离
                    float pathX = Mathf.Sin(wz * 0.18f) * 4f - 2f + Heightfield.Fbm(wz * 0.2f, 3f, 2) * 2f;
                    float path = Smooth(1.4f, 0.6f, Mathf.Abs(wx - pathX)) * Smooth(14f, 8f, wz);
                    float grass = 1;
                    var c = new Color(grass, 0, 0, 0);
                    c = Color.Lerp(c, new Color(0, 1, 0, 0), path);
                    c = Color.Lerp(c, new Color(0, 0, 1, 0), rock);
                    c = Color.Lerp(c, new Color(0, 0, 0, 1), snow);
                    px[y * res + x] = c;
                }
            t.SetPixels(px); t.Apply();
            return t;
        }
        //#endregion

        static Material SplatMat(Shot s, float size, System.Func<float, float, float> h)
        {
            var m = s.Mat("Cookbook/Ch20/Splatmap");
            var control = BuildControl(size, h);
            s.Temp.Add(control);
            m.SetTexture("_Control", control);
            m.SetTexture("_Splat0", TerrainTextures.Grass);
            m.SetTexture("_Splat1", TerrainTextures.Sand);
            m.SetTexture("_Splat2", TerrainTextures.Rock);
            m.SetTexture("_Normal2", TerrainTextures.RockNormal);
            m.SetTexture("_Splat3", TerrainTextures.Snow);
            return m;
        }

        [BookShot("ch20-splatmap", W = 640, H = 400, Panels = 2)]
        static void Splat(Shot s)
        {
            var m = SplatMat(s, 80, Heightfield.DemoHeight);
            if (s.Panel == 0) m.EnableKeyword("_DEBUG_CONTROL");
            Terrain(s, m, 80, 320, Heightfield.DemoHeight);
            s.SunDir(32, -40, 1.5f);
            s.LookAt(new Vector3(-4f, 6.5f, -20f), new Vector3(2f, 3.5f, 10f), 50);
        }

        [BookShot("ch20-splat-height", W = 640, H = 420, Panels = 2)]
        static void SplatHeight(Shot s)
        {
            var m = SplatMat(s, 80, Heightfield.DemoHeight);
            m.SetFloat("_HeightBased", s.Panel);
            m.SetFloat("_HeightTransition", 0.15f);
            Terrain(s, m, 80, 320, Heightfield.DemoHeight);
            s.SunDir(40, -40, 1.5f);
            // 对准土路与草地的交界
            float x = -2.6f, z = -6f;
            float y = Heightfield.DemoHeight(x, z);
            s.LookAt(new Vector3(x - 0.4f, y + 2.6f, z - 2.2f), new Vector3(x, y, z + 0.3f), 45);
        }

        // ---------------------------------------------------------------- 20.7 – 20.9
        static GrassRenderer Grass(Shot s, System.Func<float, float, float> h, Rect area, float spacing, System.Func<float, float, bool> accept = null, int seed = 5)
        {
            var mesh = GrassRenderer.BuildClump(9, 0.22f, seed);
            s.Temp.Add(mesh);
            var mat = s.Mat("Cookbook/Ch20/Grass");
            mat.enableInstancing = true;     // Graphics.RenderMeshInstanced 要求材质开启 GPU Instancing
            var rnd = new System.Random(seed);
            var mats = new List<Matrix4x4>();
            var vars = new List<float>();
            for (float z = area.yMin; z < area.yMax; z += spacing)
                for (float x = area.xMin; x < area.xMax; x += spacing)
                {
                    float px = x + ((float)rnd.NextDouble() - 0.5f) * spacing;
                    float pz = z + ((float)rnd.NextDouble() - 0.5f) * spacing;
                    if (accept != null && !accept(px, pz)) continue;
                    float py = h(px, pz);
                    float sc = Mathf.Lerp(0.75f, 1.35f, (float)rnd.NextDouble()) * Mathf.Lerp(0.8f, 1.2f, Heightfield.Fbm(px * 0.3f, pz * 0.3f, 2));
                    mats.Add(Matrix4x4.TRS(new Vector3(px, py, pz), Quaternion.Euler(0, (float)rnd.NextDouble() * 360, 0), Vector3.one * sc));
                    vars.Add((float)rnd.NextDouble());
                }
            var go = new GameObject("Grass");
            var gr = go.AddComponent<GrassRenderer>();
            gr.mesh = mesh;
            gr.material = mat;
            gr.SetInstances(mats, vars);
            return gr;
        }

        static float Meadow(float x, float z) => (Heightfield.Fbm(x * 0.08f + 2, z * 0.08f + 5, 4) - 0.5f) * 1.6f;

        static Material MeadowGround(Shot s)
        {
            var g = AutoTerrainMat(s);
            g.SetFloat("_RockSlope", 0.9f);
            g.SetFloat("_SandHeight", -10f);
            return g;
        }

        [BookShot("ch20-grass-field", W = 960, H = 500)]
        static void GrassField(Shot s)
        {
            Terrain(s, MeadowGround(s), 60, 200, Meadow);
            var gr = Grass(s, Meadow, new Rect(-14, -8, 28, 34), 0.24f);
            gr.material.SetFloat("_FadeStart", 22);
            gr.material.SetFloat("_FadeEnd", 30);
            gr.material.SetFloat("_WindPhase", 1.2f);
            var rock = s.Mat("Cookbook/Ch20/Triplanar");
            rock.SetTexture("_BaseMap", TerrainTextures.Rock);
            rock.SetTexture("_BumpMap", TerrainTextures.RockNormal);
            rock.SetFloat("_Tiling", 0.4f);
            s.MeshObj(Heightfield.Rock(1.1f, 128, 0.3f, 4f), rock, new Vector3(2.4f, Meadow(2.4f, 2f) + 0.2f, 2f), 1, "Rock");
            s.SunDir(22, -150, 1.6f);   // 逆光，看透射
            s.LookAt(new Vector3(0, Meadow(0, -6) + 1.5f, -6), new Vector3(1.0f, Meadow(1, 4) + 0.3f, 4), 50);
        }

        [BookShot("ch20-grass-interact", W = 640, H = 420, Panels = 2)]
        static void GrassInteract(Shot s)
        {
            System.Func<float, float, float> flat = (x, z) => (Heightfield.Fbm(x * 0.1f, z * 0.1f, 3) - 0.5f) * 0.3f;
            Terrain(s, MeadowGround(s), 30, 100, flat);
            var gr = Grass(s, flat, new Rect(-6, -4, 12, 12), 0.16f);
            var ballMat = s.Lit(new Color(0.85f, 0.3f, 0.15f), 0, 0.6f);
            var b1 = s.Sphere(ballMat, new Vector3(-0.9f, flat(-0.9f, 0.8f) + 0.45f, 0.8f), 0.9f);
            var b2 = s.Sphere(s.Lit(new Color(0.2f, 0.45f, 0.85f), 0, 0.6f), new Vector3(1.2f, flat(1.2f, 2.2f) + 0.35f, 2.2f), 0.7f);
            if (s.Panel == 1)
            {
                // 两个球 + 红球身后一串看不见的点：模拟球滚过后留下的“压痕带”
                var list = new List<Transform> { b1.transform, b2.transform };
                for (int i = 1; i <= 5; i++)
                {
                    var t = new GameObject("Trail" + i).transform;
                    t.position = b1.transform.position + new Vector3(-0.35f * i, 0, -0.5f * i);
                    t.localScale = Vector3.one * (0.9f - i * 0.08f);
                    list.Add(t);
                }
                gr.interactors = list.ToArray();
                gr.interactorRadius = 1.1f;     // 半径 = 1.1 × 物体缩放
            }
            s.SunDir(45, -40, 1.4f);
            s.LookAt(new Vector3(0.6f, 3.0f, -3.4f), new Vector3(-0.3f, 0.0f, 0.9f), 50);
        }

        [BookShot("ch20-grass-fade", W = 640, H = 400, Panels = 2)]
        static void GrassFade(Shot s)
        {
            Terrain(s, MeadowGround(s), 80, 200, Meadow);
            var gr = Grass(s, Meadow, new Rect(-16, -6, 32, 40), 0.3f);
            if (s.Panel == 0) { gr.material.SetFloat("_FadeStart", 14f); gr.material.SetFloat("_FadeEnd", 14.01f); }
            else { gr.material.SetFloat("_FadeStart", 9f); gr.material.SetFloat("_FadeEnd", 15f); }
            s.SunDir(40, -40, 1.4f);
            s.LookAt(new Vector3(0, Meadow(0, -6) + 3.0f, -6), new Vector3(0, Meadow(0, 10), 10), 55);
        }

        [BookShot("ch20-final", W = 960, H = 520)]
        static void Final(Shot s)
        {
            var m = AutoTerrainMat(s);
            Terrain(s, m, 80, 320, Heightfield.DemoHeight);
            // 只在平缓、低于雪线的地方长草
            System.Func<float, float, bool> accept = (x, z) =>
            {
                float e = 0.3f, h = Heightfield.DemoHeight(x, z);
                float dx = (Heightfield.DemoHeight(x + e, z) - Heightfield.DemoHeight(x - e, z)) / (2 * e);
                float dz = (Heightfield.DemoHeight(x, z + e) - Heightfield.DemoHeight(x, z - e)) / (2 * e);
                return dx * dx + dz * dz < 0.12f && h < 4f && h > -0.3f;
            };
            var gr = Grass(s, Heightfield.DemoHeight, new Rect(-16, -14, 30, 30), 0.26f, accept);
            gr.material.SetFloat("_FadeStart", 20);
            gr.material.SetFloat("_FadeEnd", 28);
            gr.material.SetFloat("_WindPhase", 2f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.012f;
            RenderSettings.fogColor = new Color(0.55f, 0.62f, 0.72f);
            s.SunDir(28, -35, 1.6f);
            s.LookAt(new Vector3(-6f, Heightfield.DemoHeight(-6, -16) + 2.2f, -16f), new Vector3(2f, 3.2f, 12f), 55);
        }
    }
}
