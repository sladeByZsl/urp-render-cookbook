// 第 21 章配图
using System.Collections.Generic;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch21
{
    static class Ch21Shots
    {
        static readonly Color Night = new Color(0.035f, 0.045f, 0.07f);

        static void Ortho(Shot s, float halfHeight, Vector3 center)
        {
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = halfHeight;
            s.Cam.transform.position = center + new Vector3(0, 0, -5);
            s.Cam.transform.rotation = Quaternion.identity;
        }

        static void NightMood(Shot s, float sun = 0.15f)
        {
            s.Background(Night);
            RenderSettings.ambientProbe = RenderSettings.ambientProbe * 0.25f;
            s.Sun.color = new Color(0.6f, 0.7f, 1f);
            s.SunDir(40, -30, sun);
        }

        static void Bloom(Shot s, float intensity = 1.2f, float threshold = 0.9f)
        {
            var prof = s.Post();
            var b = prof.Add<UnityEngine.Rendering.Universal.Bloom>();
            b.intensity.Override(intensity);
            b.threshold.Override(threshold);
            b.scatter.Override(0.7f);
            var tm = prof.Add<Tonemapping>();
            tm.mode.Override(TonemappingMode.ACES);
        }

        // ---------------------------------------------------------------- 21.1
        [BookShot("ch21-uvscroll", W = 640, H = 420, Panels = 3)]
        static void UVScroll(Shot s)
        {
            var m = s.Mat("Cookbook/Ch21/UVScroll");
            m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
            m.SetTexture("_RampTex", s.CoreTex("ramp_fire"));
            m.SetFloat("_SecondLayer", s.Panel >= 1 ? 1 : 0);
            m.SetFloat("_UseRamp", s.Panel == 2 ? 1 : 0);
            m.SetFloat("_Phase", 3.3f);
            var g = s.Grid(m, Vector3.zero, 4f, 4);
            // 两侧的“岩岸”
            var rock = s.Lit(new Color(0.18f, 0.16f, 0.15f), 0, 0.2f);
            s.Cube(rock, new Vector3(-2.6f, 0.2f, 0), 1).transform.localScale = new Vector3(1.6f, 0.8f, 6f);
            s.Cube(rock, new Vector3(2.6f, 0.2f, 0), 1).transform.localScale = new Vector3(1.6f, 0.8f, 6f);
            NightMood(s, 0.4f);
            s.LookAt(new Vector3(0, 3.4f, -3.4f), new Vector3(0, 0, 0.4f), 50);
        }

        // ---------------------------------------------------------------- 21.2
        static Material FlipbookMat(Shot s, float frame, bool blend)
        {
            var m = s.Mat("Cookbook/Ch21/Flipbook");
            m.SetTexture("_BaseMap", s.CoreTex("flipbook_smoke_4x4"));
            m.SetColor("_BaseColor", new Color(1.6f, 1.6f, 1.6f, 1.4f));
            m.SetFloat("_Frame", frame);
            m.SetFloat("_FPS", 0);            // 拍摄时 _Time 不为 0，关掉自动播放，只用 _Frame 指定帧号
            if (blend) m.EnableKeyword("_FLIPBOOK_BLEND"); else m.DisableKeyword("_FLIPBOOK_BLEND");
            return m;
        }

        [BookShot("ch21-flipbook-atlas", W = 960, H = 460)]
        static void FlipbookAtlas(Shot s)
        {
            var dbg = FlipbookMat(s, 6.35f, true);
            dbg.EnableKeyword("_DEBUG_ATLAS");
            s.Quad(dbg, new Vector3(-2.3f, 0, 0), 4f);
            s.Quad(FlipbookMat(s, 6.35f, true), new Vector3(2.3f, 0, 0), 4f);
            s.Background(new Color(0.12f, 0.16f, 0.2f));
            Ortho(s, 2.25f, Vector3.zero);
        }

        static Texture2D s_DotAtlas;
        /// 程序生成的 4×4 测试图集：一个亮点沿圆周运动，每帧转 22.5°，便于看清“换帧”与“混合”
        static Texture2D DotAtlas()
        {
            if (s_DotAtlas) return s_DotAtlas;
            const int cell = 128, size = cell * 4;
            var t = new Texture2D(size, size, TextureFormat.RGBA32, true) { name = "dot_atlas", hideFlags = HideFlags.DontSave, wrapMode = TextureWrapMode.Clamp };
            var px = new Color[size * size];
            for (int f = 0; f < 16; f++)
            {
                int col = f % 4, row = f / 4;
                float a = f / 16f * Mathf.PI * 2;
                var c = new Vector2(0.5f + Mathf.Cos(a) * 0.3f, 0.5f + Mathf.Sin(a) * 0.3f);
                for (int y = 0; y < cell; y++)
                    for (int x = 0; x < cell; x++)
                    {
                        var p = new Vector2((x + 0.5f) / cell, (y + 0.5f) / cell);
                        float d = (p - c).magnitude;
                        float dot = Mathf.Clamp01((0.1f - d) / 0.02f);
                        float ring = Mathf.Clamp01(1 - Mathf.Abs((p - new Vector2(0.5f, 0.5f)).magnitude - 0.3f) / 0.008f) * 0.35f;
                        float al = Mathf.Max(dot, ring);
                        px[((3 - row) * cell + y) * size + col * cell + x] = new Color(1, dot > 0 ? 0.85f : 1, dot > 0 ? 0.4f : 1, al);
                    }
            }
            t.SetPixels(px); t.Apply(true);
            return s_DotAtlas = t;
        }

        [BookShot("ch21-flipbook-blend", W = 960, H = 400)]
        static void FlipbookBlend(Shot s)
        {
            for (int row = 0; row < 2; row++)
                for (int i = 0; i < 5; i++)
                {
                    float frame = 2f + i * 0.25f;
                    var m = FlipbookMat(s, frame, row == 1);
                    m.SetTexture("_BaseMap", DotAtlas());
                    m.SetColor("_BaseColor", Color.white);
                    s.Quad(m, new Vector3(-4.4f + i * 2.2f, row == 0 ? 1.05f : -1.05f, 0), 2.0f);
                }
            s.Background(new Color(0.12f, 0.16f, 0.2f));
            Ortho(s, 2.1f, Vector3.zero);
        }

        // ---------------------------------------------------------------- 21.3
        static Texture2D s_RawFlow;
        /// 公共贴图 flow_swirl 按默认设置导入时是压缩格式，平滑的方向场会出现块状色阶。
        /// 这里直接读 PNG 生成一张不压缩的线性贴图（项目里应在导入设置里把 Compression 设为 None 或用 BC7）
        static Texture2D RawFlow()
        {
            if (s_RawFlow) return s_RawFlow;
            var t = new Texture2D(2, 2, TextureFormat.RGBA32, true, true) { name = "flow_swirl_raw", hideFlags = HideFlags.DontSave };
            t.LoadImage(System.IO.File.ReadAllBytes("Assets/Cookbook/_Core/Textures/flow_swirl.png"));
            t.wrapMode = TextureWrapMode.Repeat;
            t.filterMode = FilterMode.Bilinear;
            return s_RawFlow = t;
        }

        [BookShot("ch21-flowmap", W = 520, H = 520, Panels = 3)]
        static void Flowmap(Shot s)
        {
            var m = s.Mat("Cookbook/Ch21/Flowmap");
            m.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            m.SetTextureScale("_BaseMap", new Vector2(2, 2));
            m.SetTexture("_FlowMap", RawFlow());
            m.SetFloat("_Mode", s.Panel);
            m.SetFloat("_Speed", 1);
            m.SetFloat("_Phase", 0.92f);    // 单相位接近一个周期末尾，拉伸最严重的时刻
            m.SetFloat("_FlowStrength", 0.35f);
            s.Quad(m, Vector3.zero, 2f);
            s.Background(Color.white);
            Ortho(s, 1f, Vector3.zero);
        }

        [BookShot("ch21-flowmap-lava", W = 960, H = 460, Hdr = true)]
        static void FlowmapLava(Shot s)
        {
            var m = s.Mat("Cookbook/Ch21/Flowmap");
            m.SetTexture("_BaseMap", s.CoreTex("noise_fbm"));
            m.SetTextureScale("_BaseMap", new Vector2(1.5f, 1.5f));
            m.SetTexture("_FlowMap", RawFlow());
            m.SetTexture("_RampTex", s.CoreTex("ramp_fire"));
            m.SetFloat("_Mode", 2);
            m.SetFloat("_UseRamp", 1);
            m.SetFloat("_Intensity", 2f);
            m.SetFloat("_FlowStrength", 0.3f);
            m.SetFloat("_Phase", 0.3f);
            var pool = s.Quad(m, new Vector3(0, 0.02f, 0.5f), 4.2f);
            pool.transform.rotation = Quaternion.Euler(90, 0, 0);
            // 一圈石头围住熔岩池
            var rock = s.Lit(new Color(0.2f, 0.18f, 0.17f), 0, 0.15f);
            Random.InitState(5);
            for (int i = 0; i < 18; i++)
            {
                float a = i / 18f * Mathf.PI * 2;
                var c = s.Sphere(rock, new Vector3(Mathf.Cos(a) * 2.25f, 0.1f, 0.5f + Mathf.Sin(a) * 2.25f), 1);
                c.transform.localScale = new Vector3(Random.Range(0.6f, 0.9f), Random.Range(0.35f, 0.55f), Random.Range(0.5f, 0.8f));
                c.transform.rotation = Quaternion.Euler(0, a * Mathf.Rad2Deg + 20, 0);
            }
            var floor = s.Floor(s.Lit(new Color(0.12f, 0.11f, 0.1f), 0, 0.1f), 30, -0.01f);
            s.Point(new Vector3(0, 1.2f, 0.5f), new Color(1f, 0.45f, 0.15f), 4f, 7f);
            NightMood(s, 0.35f);
            Bloom(s, 1.0f, 1.0f);
            s.LookAt(new Vector3(0, 3.6f, -3.6f), new Vector3(0, 0, 0.5f), 48);
        }

        // ---------------------------------------------------------------- 21.4
        static Material PortalMat(Shot s)
        {
            var m = s.Mat("Cookbook/Ch21/Portal");
            m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
            m.SetFloat("_Phase", 1.7f);
            return m;
        }

        [BookShot("ch21-portal-polar", W = 480, H = 480, Panels = 4)]
        static void PortalPolar(Shot s)
        {
            var m = PortalMat(s);
            if (s.Panel == 0) m.SetFloat("_Debug", 1);
            if (s.Panel == 1) m.SetFloat("_Debug", 2);
            if (s.Panel == 2) m.SetFloat("_Debug", 4);
            // 往上挪 1 像素：让接缝落在 2×2 像素块内部（正好落在块边界上时求导看不到跳变，接缝会“消失”）
            s.Quad(m, new Vector3(0, 2f / 480f, 0), 2f);
            s.Background(s.Panel < 3 ? Color.black : new Color(0.02f, 0.02f, 0.04f));
            Ortho(s, 1f, Vector3.zero);
        }

        [BookShot("ch21-portal-seam", W = 320, H = 150, Panels = 2)]
        static void PortalSeam(Shot s)
        {
            var m = PortalMat(s);
            m.SetFloat("_Debug", 3);
            m.SetFloat("_FixSeam", s.Panel);
            // 低分辨率 + 只拍左侧接缝附近，放大到版面上能看清那道 2 像素的线
            s.Quad(m, new Vector3(0.45f, 0.5f / 150f * 0.35f * 2f, 0), 2f);
            s.Background(Color.black);
            Ortho(s, 0.35f, Vector3.zero);
        }

        [BookShot("ch21-portal", W = 960, H = 540, Hdr = true)]
        static void Portal(Shot s)
        {
            var m = PortalMat(s);
            var q = s.Quad(m, new Vector3(0, 1.45f, 0), 2.5f);
            var stone = s.Lit(new Color(0.35f, 0.33f, 0.32f), 0, 0.25f);
            stone.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            stone.SetTexture("_BumpMap", s.CoreTex("bricks_normal"));
            stone.EnableKeyword("_NORMALMAP");
            var ring = s.Torus(stone, new Vector3(0, 1.45f, 0), 1.32f, 0.16f);
            ring.transform.rotation = Quaternion.Euler(90, 0, 0);
            s.Cube(stone, new Vector3(-1.0f, 0.12f, 0), 1).transform.localScale = new Vector3(0.7f, 0.24f, 0.6f);
            s.Cube(stone, new Vector3(1.0f, 0.12f, 0), 1).transform.localScale = new Vector3(0.7f, 0.24f, 0.6f);
            s.Floor(s.Lit(new Color(0.25f, 0.25f, 0.27f), 0, 0.2f));
            s.Point(new Vector3(0, 1.45f, -0.7f), new Color(0.6f, 0.45f, 1f), 3f, 6f);
            NightMood(s, 0.3f);
            Bloom(s, 1.0f, 1.0f);
            s.LookAt(new Vector3(0.9f, 1.6f, -4.6f), new Vector3(0, 1.3f, 0), 42);
        }

        // ---------------------------------------------------------------- 21.5
        static Material ParticleMat(Shot s, string tex, Color tint, BlendMode src, BlendMode dst, bool premul = false)
        {
            var m = s.Mat("Cookbook/Ch21/Particle");
            m.SetTexture("_BaseMap", s.CoreTex(tex));
            m.SetColor("_BaseColor", tint);
            m.SetFloat("_SrcBlend", (float)src);
            m.SetFloat("_DstBlend", (float)dst);
            m.SetFloat("_Premultiply", premul ? 1 : 0);
            return m;
        }

        //#region quadParticles
        /// 用一组朝向相机的 Quad 摆出“一团粒子”，每个 Quad 带不同的顶点色（模拟粒子的 Start Color）
        static void FakeParticles(Shot s, Material m, Vector3 center, int count, Vector3 spread, float size, Color c0, Color c1, int seed)
        {
            var rnd = new System.Random(seed);
            for (int i = 0; i < count; i++)
            {
                var p = center + Vector3.Scale(new Vector3((float)rnd.NextDouble() - 0.5f, (float)rnd.NextDouble() - 0.5f, (float)rnd.NextDouble() - 0.5f), spread);
                var q = s.Quad(m, p, size * Mathf.Lerp(0.7f, 1.2f, (float)rnd.NextDouble()));
                q.transform.rotation = Quaternion.LookRotation(p - s.Cam.transform.position) * Quaternion.Euler(0, 0, (float)rnd.NextDouble() * 360);
                var mesh = Object.Instantiate(q.GetComponent<MeshFilter>().sharedMesh);
                var col = Color.Lerp(c0, c1, (float)rnd.NextDouble());
                mesh.colors = new[] { col, col, col, col };
                q.GetComponent<MeshFilter>().sharedMesh = mesh;
                s.Temp.Add(mesh);
            }
        }
        //#endregion

        [BookShot("ch21-blendmodes", W = 640, H = 420, Panels = 3)]
        static void BlendModes(Shot s)
        {
            s.LookAt(new Vector3(0, 1.2f, -4f), new Vector3(0, 1.1f, 0), 40);
            // 背景：一半亮（白墙）一半暗（砖墙）
            s.Cube(s.Lit(new Color(0.5f, 0.5f, 0.5f), 0, 0.2f), new Vector3(-1.5f, 1.5f, 1.2f), 1).transform.localScale = new Vector3(3f, 3f, 0.2f);
            var brick = s.Lit(Color.white, 0, 0.2f); brick.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            brick.SetColor("_BaseColor", new Color(0.35f, 0.35f, 0.35f));
            s.Cube(brick, new Vector3(1.5f, 1.5f, 1.2f), 1).transform.localScale = new Vector3(3f, 3f, 0.2f);
            s.Floor(s.Lit(new Color(0.3f, 0.3f, 0.3f), 0, 0.1f));
            Material m;
            if (s.Panel == 0) m = ParticleMat(s, "particle_soft", new Color(1, 1, 1, 1), BlendMode.SrcAlpha, BlendMode.OneMinusSrcAlpha);
            else if (s.Panel == 1) m = ParticleMat(s, "particle_soft", new Color(1, 1, 1, 1), BlendMode.SrcAlpha, BlendMode.One);
            else { m = ParticleMat(s, "particle_soft", new Color(1, 1, 1, 1), BlendMode.DstColor, BlendMode.Zero); m.SetFloat("_Modulate", 1); }
            FakeParticles(s, m, new Vector3(0, 1.2f, 0), 22, new Vector3(3.2f, 0.9f, 0.6f), 0.9f, new Color(1f, 0.5f, 0.12f, 0.9f), new Color(0.25f, 0.25f, 0.3f, 0.9f), 3);
            s.SunDir(40, -20, 1.2f);
        }

        // ---------------------------------------------------------------- 21.6
        [BookShot("ch21-soft-particles", W = 640, H = 420, Panels = 2)]
        static void SoftParticles(Shot s)
        {
            s.LookAt(new Vector3(0, 1.3f, -3.6f), new Vector3(0, 0.45f, 0.4f), 42);
            s.Floor(s.Lit(new Color(0.12f, 0.12f, 0.13f), 0, 0.2f));
            s.Cube(s.Lit(new Color(0.55f, 0.4f, 0.3f), 0, 0.3f), new Vector3(0.6f, 0.5f, 0.6f), 1f).transform.rotation = Quaternion.Euler(0, 30, 0);
            var m = ParticleMat(s, "particle_soft", new Color(0.85f, 0.88f, 0.95f, 1f), BlendMode.SrcAlpha, BlendMode.OneMinusSrcAlpha);
            if (s.Panel == 1) { m.EnableKeyword("_SOFTPARTICLES_ON"); m.SetFloat("_SoftDistance", 0.6f); }
            // 一团贴地的烟：大 Quad 与地面、箱子相交
            var rnd = new System.Random(4);
            for (int i = 0; i < 9; i++)
            {
                var p = new Vector3(-1.4f + i * 0.38f, 0.25f + (float)rnd.NextDouble() * 0.3f, 0.2f + (float)rnd.NextDouble() * 0.9f);
                var q = s.Quad(m, p, 1.6f);
                q.transform.rotation = Quaternion.LookRotation(p - s.Cam.transform.position);
                var mesh = Object.Instantiate(q.GetComponent<MeshFilter>().sharedMesh);
                var col = new Color(1, 1, 1, 0.95f);
                mesh.colors = new[] { col, col, col, col };
                q.GetComponent<MeshFilter>().sharedMesh = mesh; s.Temp.Add(mesh);
            }
        }

        // ---------------------------------------------------------------- 21.7
        //#region particleSystem
        /// 建一个用本章 Shader 的粒子系统：Texture Sheet Animation 4×4 + Custom Vertex Streams（UV2 + AnimBlend）
        static ParticleSystem MakeSystem(Shot s, Material m, Vector3 pos, float rate, Vector2 life, Vector2 speed, Vector2 size,
                                         Gradient colorOverLife, AnimationCurve sizeOverLife, float coneAngle, float radius, int seed)
        {
            var go = new GameObject("Particles");
            go.transform.position = pos;
            go.transform.rotation = Quaternion.Euler(-90, 0, 0);      // Cone 默认沿 +Z 发射，转到朝上
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            ps.randomSeed = (uint)seed; ps.useAutoRandomSeed = false;

            var main = ps.main;
            main.duration = 5; main.loop = true;
            main.startLifetime = new ParticleSystem.MinMaxCurve(life.x, life.y);
            main.startSpeed = new ParticleSystem.MinMaxCurve(speed.x, speed.y);
            main.startSize = new ParticleSystem.MinMaxCurve(size.x, size.y);
            main.startRotation = new ParticleSystem.MinMaxCurve(0, Mathf.PI * 2);
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.maxParticles = 500;

            var em = ps.emission; em.rateOverTime = rate;
            var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Cone; sh.angle = coneAngle; sh.radius = radius;
            var col = ps.colorOverLifetime; col.enabled = true; col.color = colorOverLife;
            var sz = ps.sizeOverLifetime; sz.enabled = true; sz.size = new ParticleSystem.MinMaxCurve(1, sizeOverLife);

            var tsa = ps.textureSheetAnimation;
            tsa.enabled = true; tsa.numTilesX = 4; tsa.numTilesY = 4;
            tsa.frameOverTime = new ParticleSystem.MinMaxCurve(1, AnimationCurve.Linear(0, 0, 1, 1));

            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = m;
            r.sortMode = ParticleSystemSortMode.Distance;
            // 与 Shader 里 Attributes 的顺序一一对应
            r.SetActiveVertexStreams(new List<ParticleSystemVertexStream>
            {
                ParticleSystemVertexStream.Position,
                ParticleSystemVertexStream.Color,
                ParticleSystemVertexStream.UV,
                ParticleSystemVertexStream.UV2,
                ParticleSystemVertexStream.AnimBlend,
            });
            return ps;
        }
        //#endregion

        static Gradient Grad(params (float t, Color c)[] keys)
        {
            var g = new Gradient();
            var ck = new GradientColorKey[keys.Length]; var ak = new GradientAlphaKey[keys.Length];
            for (int i = 0; i < keys.Length; i++) { ck[i] = new GradientColorKey(keys[i].c, keys[i].t); ak[i] = new GradientAlphaKey(keys[i].c.a, keys[i].t); }
            g.SetKeys(ck, ak);
            return g;
        }

        static (ParticleSystem fire, ParticleSystem smoke) Campfire(Shot s, Vector3 pos)
        {
            var fireMat = ParticleMat(s, "flipbook_smoke_4x4", Color.white, BlendMode.SrcAlpha, BlendMode.One);
            fireMat.SetVector("_BaseColor", new Vector4(3f, 2.6f, 2.2f, 1));   // _BaseColor 是 [HDR] 属性，原样上传，直接写线性 HDR 值（SetColor 和 SetVector 效果相同）
            fireMat.EnableKeyword("_FLIPBOOKBLENDING_ON");
            fireMat.EnableKeyword("_RAMP_ON");
            fireMat.SetTexture("_RampTex", s.CoreTex("ramp_fire"));
            fireMat.SetFloat("_RampScale", 2.2f);
            fireMat.EnableKeyword("_SOFTPARTICLES_ON");
            fireMat.SetFloat("_SoftDistance", 0.25f);
            var fire = MakeSystem(s, fireMat, pos, 70, new Vector2(0.6f, 1.0f), new Vector2(0.6f, 1.2f), new Vector2(0.7f, 1.1f),
                Grad((0, new Color(1, 1, 1, 0)), (0.15f, new Color(1, 1, 1, 1)), (1, new Color(1, 1, 1, 0))),
                new AnimationCurve(new Keyframe(0, 0.6f), new Keyframe(0.4f, 1f), new Keyframe(1, 0.3f)), 8, 0.25f, 11);

            var smokeMat = ParticleMat(s, "flipbook_smoke_4x4", new Color(0.35f, 0.35f, 0.38f, 1), BlendMode.SrcAlpha, BlendMode.OneMinusSrcAlpha);
            smokeMat.EnableKeyword("_FLIPBOOKBLENDING_ON");
            smokeMat.EnableKeyword("_SOFTPARTICLES_ON");
            smokeMat.EnableKeyword("_CAMERAFADE_ON");
            var smoke = MakeSystem(s, smokeMat, pos + Vector3.up * 0.8f, 18, new Vector2(2.5f, 3.5f), new Vector2(0.5f, 0.8f), new Vector2(1.0f, 1.6f),
                Grad((0, new Color(1, 1, 1, 0)), (0.2f, new Color(1, 1, 1, 0.9f)), (1, new Color(1, 1, 1, 0))),
                new AnimationCurve(new Keyframe(0, 0.5f), new Keyframe(1, 2.2f)), 12, 0.3f, 12);
            return (fire, smoke);
        }

        static void Logs(Shot s, Vector3 pos)
        {
            var wood = s.Lit(new Color(0.22f, 0.13f, 0.08f), 0, 0.15f);
            for (int i = 0; i < 5; i++)
            {
                var l = s.Cylinder(wood, pos + new Vector3(0, 0.12f, 0), 1);
                l.transform.localScale = new Vector3(0.16f, 0.5f, 0.16f);
                l.transform.rotation = Quaternion.Euler(0, i * 72, 0) * Quaternion.Euler(65, 0, 0);
                l.transform.position = pos + l.transform.rotation * new Vector3(0, -0.3f, 0) + Vector3.up * 0.2f;
            }
            var stone = s.Lit(new Color(0.3f, 0.29f, 0.28f), 0, 0.2f);
            for (int i = 0; i < 12; i++)
            {
                float a = i / 12f * Mathf.PI * 2;
                var c = s.Sphere(stone, pos + new Vector3(Mathf.Cos(a) * 0.75f, 0.05f, Mathf.Sin(a) * 0.75f), 0.3f);
                c.transform.localScale = new Vector3(0.32f, 0.2f, 0.28f);
            }
        }

        [BookShot("ch21-particle-system", W = 960, H = 540, Hdr = true)]
        static void ParticleSystemShot(Shot s)
        {
            s.Floor(s.Lit(new Color(0.3f, 0.28f, 0.26f), 0, 0.1f));
            var (fire, smoke) = Campfire(s, Vector3.zero);
            // 批处理拍摄时粒子系统不会自己跑：手动推进到第 4 秒
            fire.Simulate(4f, true, true);
            smoke.Simulate(4f, true, true);
            Logs(s, Vector3.zero);
            s.Point(new Vector3(0, 0.6f, 0), new Color(1f, 0.5f, 0.2f), 4f, 7f);
            NightMood(s, 0.35f);
            Bloom(s, 0.8f, 1.0f);
            s.LookAt(new Vector3(0, 1.3f, -3.4f), new Vector3(0, 1.2f, 0), 50);
        }

        // ---------------------------------------------------------------- 21.8
        static Material HeatMat(Shot s, float strength)
        {
            var m = s.Mat("Cookbook/Ch21/HeatDistortion");
            m.SetTexture("_NoiseTex", s.CoreTex("noise_fbm"));
            m.SetTexture("_MaskTex", s.CoreTex("particle_soft"));
            m.SetFloat("_Strength", strength);
            m.SetFloat("_Phase", 0.4f);
            return m;
        }

        [BookShot("ch21-heat", W = 640, H = 460, Panels = 3)]
        static void Heat(Shot s)
        {
            var wall = s.Lit(Color.white, 0, 0.2f);
            wall.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            wall.SetTextureScale("_BaseMap", new Vector2(3, 3));
            s.Cube(wall, new Vector3(0, 1.5f, 1.6f), 1).transform.localScale = new Vector3(5f, 3f, 0.2f);
            s.Floor();
            s.Cylinder(s.Lit(new Color(0.3f, 0.3f, 0.32f), 0.8f, 0.6f), new Vector3(0, 0.15f, 0), 1).transform.localScale = new Vector3(0.8f, 0.15f, 0.8f);
            if (s.Panel > 0)
            {
                var m = HeatMat(s, s.Panel == 1 ? 0.06f : 0.06f);
                if (s.Panel == 1) m.SetFloat("_ShowOffset", 1);
                var q = s.Quad(m, new Vector3(0, 1.25f, 0.2f), 2.0f);
                q.transform.localScale = new Vector3(1.6f, 2.2f, 1);
            }
            s.SunDir(40, -20, 1.2f);
            s.LookAt(new Vector3(0, 1.3f, -3.6f), new Vector3(0, 1.15f, 0), 42);
        }

        // ---------------------------------------------------------------- 21.9
        [BookShot("ch21-campfire", W = 960, H = 540, Hdr = true)]
        static void CampfireShot(Shot s)
        {
            var ground = s.Lit(Color.white, 0, 0.1f);
            ground.SetTexture("_BaseMap", s.CoreTex("noise_cells"));
            ground.SetColor("_BaseColor", new Color(0.3f, 0.26f, 0.2f));
            ground.SetTextureScale("_BaseMap", new Vector2(8, 8));
            s.Floor(ground);
            var (fire, smoke) = Campfire(s, Vector3.zero);
            fire.Simulate(4f, true, true);
            smoke.Simulate(4f, true, true);
            Logs(s, Vector3.zero);
            // 火焰上方的热扭曲
            var q = s.Quad(HeatMat(s, 0.03f), new Vector3(0, 1.5f, 0), 1);
            q.transform.localScale = new Vector3(1.4f, 1.8f, 1);
            // 背景：几块岩石和一棵“树干”，让扭曲有东西可看
            var rock = s.Lit(new Color(0.35f, 0.33f, 0.3f), 0, 0.2f);
            s.Sphere(rock, new Vector3(-1.8f, 0.4f, 2.4f), 1.4f);
            s.Sphere(rock, new Vector3(1.6f, 0.3f, 2.0f), 1.0f);
            s.Cylinder(s.Lit(new Color(0.18f, 0.12f, 0.08f), 0, 0.1f), new Vector3(0.3f, 1.5f, 3.2f), 1).transform.localScale = new Vector3(0.35f, 1.5f, 0.35f);
            // 传送门放远处当点缀
            var portal = s.Quad(PortalMat(s), new Vector3(3.2f, 1.3f, 4.5f), 2.2f);
            portal.transform.rotation = Quaternion.Euler(0, -20, 0);
            var fl = s.Point(new Vector3(0, 0.7f, 0), new Color(1f, 0.5f, 0.2f), 5f, 9f);
            fl.shadows = LightShadows.Soft;
            s.Point(new Vector3(3.2f, 1.3f, 4.0f), new Color(0.6f, 0.4f, 1f), 2.5f, 4f);
            NightMood(s, 0.35f);
            Bloom(s, 1.0f, 1.0f);
            s.LookAt(new Vector3(-0.6f, 1.4f, -3.3f), new Vector3(0.5f, 1.0f, 1.0f), 52);
        }
    }
}
