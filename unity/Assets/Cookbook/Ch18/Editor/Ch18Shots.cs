// 第 18 章配图：溶解、菲涅尔、全息、护盾、隐身、冰冻、扫描线。
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch18
{
    static class Shots
    {
        // ---------- 公用小工具 ----------
        static void Glow(Shot s, float intensity = 1.2f, float threshold = 1f)
        {
            // 后处理加成：Bloom 让 HDR 发光“溢出”，Tonemapping 把 HDR 压回显示范围
            var p = s.Post();
            var b = p.Add<Bloom>();
            b.intensity.Override(intensity);
            b.threshold.Override(threshold);
            b.scatter.Override(0.65f);
            var t = p.Add<Tonemapping>();
            t.mode.Override(TonemappingMode.Neutral);
        }

        static Material DarkFloorMat(Shot s, float v = 0.32f)
        {
            var m = s.Lit(new Color(v, v, v * 1.05f), 0, 0.2f);
            m.SetTexture("_BaseMap", s.CoreTex("checker"));
            m.SetTextureScale("_BaseMap", new Vector2(7.5f, 7.5f));
            return m;
        }

        static Material Dissolve(Shot s, float progress)
        {
            var m = s.Mat("Cookbook/Ch18/Dissolve");
            m.SetTexture("_BaseMap", s.CoreTex("paintedmetal_albedo"));
            m.SetColor("_BaseColor", new Color(0.55f, 0.75f, 0.95f));
            m.SetFloat("_Smoothness", 0.55f);
            m.SetTexture("_NoiseMap", s.CoreTex("noise_fbm"));
            m.SetVector("_NoiseMap_ST", new Vector4(0.6f, 1.6f, 0, 0));
            m.SetTexture("_EdgeRamp", s.CoreTex("ramp_fire"));
            m.SetFloat("_Progress", progress);
            m.SetFloat("_EdgeWidth", 0.08f);
            m.SetColor("_EdgeColor", new Color(5f, 3f, 2f));
            m.SetFloat("_UseRamp", 1);
            m.SetFloat("_Cull", (float)CullMode.Off);
            SetMode(m, 0);
            return m;
        }

        static void SetMode(Material m, int mode)
        {
            m.SetFloat("_Mode", mode);
            m.DisableKeyword("_MODE_NOISE"); m.DisableKeyword("_MODE_DIRECTION"); m.DisableKeyword("_MODE_SPHERE");
            m.EnableKeyword(mode == 0 ? "_MODE_NOISE" : mode == 1 ? "_MODE_DIRECTION" : "_MODE_SPHERE");
        }

        static void KnotStage(Shot s)
        {
            s.Floor(DarkFloorMat(s, 0.55f));
            s.LookAt(new Vector3(0, 1.9f, -3.9f), new Vector3(0, 0.72f, 0), 36);
            s.SunDir(48, -35, 1.4f);
        }

        // ---------- 18.1 溶解进度 ----------
        [BookShot("ch18-dissolve-progress", W = 480, H = 420, Panels = 4)]
        static void DissolveProgress(Shot s)
        {
            KnotStage(s);
            var m = Dissolve(s, new[] { 0.15f, 0.4f, 0.6f, 0.8f }[s.Panel]);
            m.SetFloat("_UseRamp", 0);
            m.SetFloat("_EdgeWidth", 0.0f);
            s.Knot(m, new Vector3(0, 0.75f, 0), 1.0f);
        }

        // ---------- 18.2 边缘 ----------
        [BookShot("ch18-dissolve-edge", Hdr = true, W = 640, H = 480, Panels = 3)]
        static void DissolveEdge(Shot s)
        {
            KnotStage(s);
            var m = Dissolve(s, 0.45f);
            if (s.Panel == 0) { m.SetFloat("_EdgeWidth", 0.0f); }
            if (s.Panel == 1) { m.SetFloat("_EdgeWidth", 0.04f); m.SetFloat("_UseRamp", 0); m.SetColor("_EdgeColor", new Color(0.4f, 2.5f, 4f)); }
            if (s.Panel == 2) { m.SetFloat("_EdgeWidth", 0.1f); Glow(s, 1.0f, 1.1f); }
            s.Knot(m, new Vector3(0, 0.75f, 0), 1.0f);
        }

        // ---------- 18.3 方向 / 球形 ----------
        [BookShot("ch18-dissolve-modes", Hdr = true, W = 640, H = 480, Panels = 3)]
        static void DissolveModes(Shot s)
        {
            KnotStage(s);
            var m = Dissolve(s, 0.45f);
            SetMode(m, s.Panel);
            m.SetFloat("_EdgeWidth", 0.07f);
            m.SetFloat("_NoiseStrength", 0.22f);
            m.SetVector("_DissolveDir", new Vector4(0, -1, 0, 0));          // 从上往下
            m.SetVector("_DirRange", new Vector4(-0.5f, 0.5f, 0, 0));
            m.SetVector("_SphereCenter", new Vector4(-0.75f, 1.1f, -0.2f, 1.9f));
            Glow(s, 0.9f, 1.1f);
            s.Knot(m, new Vector3(0, 0.75f, 0), 1.0f);
        }

        // ---------- 18.4 菲涅尔 ----------
        [BookShot("ch18-fresnel-power", W = 960, H = 400)]
        static void FresnelPower(Shot s)
        {
            s.Floor(DarkFloorMat(s, 0.3f));
            s.Background(new Color(0.05f, 0.06f, 0.08f));
            float[] pw = { 1, 2, 4, 8 };
            s.SphereRow(4, i =>
            {
                var m = s.Mat("Cookbook/Ch18/FresnelRim");
                m.SetFloat("_RimPower", pw[i]);
                return m;
            }, y: 0.55f, step: 1.25f, scale: 1.0f);
            s.LookAt(new Vector3(0, 1.3f, -5.4f), new Vector3(0, 0.5f, 0), 32);
        }

        [BookShot("ch18-fresnel-mask", W = 640, H = 480, Panels = 2)]
        static void FresnelMask(Shot s)
        {
            KnotStage(s);
            var m = s.Mat("Cookbook/Ch18/FresnelRim");
            m.SetColor("_BaseColor", new Color(0.6f, 0.38f, 0.3f));
            m.SetColor("_RimColor", new Color(0.4f, 1.2f, 2.2f));
            m.SetFloat("_RimPower", 3);
            m.SetFloat("_RimLightMask", s.Panel);
            s.SunDir(12, -90, 1.8f);   // 光从右侧低角度打来，左侧是背光面
            s.Background(new Color(0.05f, 0.06f, 0.08f));
            s.Knot(m, new Vector3(0, 0.75f, 0), 1.0f);
        }
            // ---------- 18.5 全息 ----------
        static Material Holo(Shot s)
        {
            var m = s.Mat("Cookbook/Ch18/Hologram");
            m.SetFloat("_Phase", 1.37f);
            return m;
        }

        static void HoloStage(Shot s)
        {
            s.Background(new Color(0.02f, 0.025f, 0.035f));
            s.Floor(DarkFloorMat(s, 0.12f));
            s.SunDir(55, -30, 0.4f);
            // 投影台：一个扁圆柱
            var baseMat = s.Lit(new Color(0.12f, 0.13f, 0.15f), 0.8f, 0.6f);
            var b = s.Cylinder(baseMat, new Vector3(0, 0.05f, 0), 1);
            b.transform.localScale = new Vector3(1.5f, 0.05f, 1.5f);
            s.Point(new Vector3(0, 0.6f, -0.4f), new Color(0.3f, 0.7f, 1f), 1.5f, 3f);
        }

        [BookShot("ch18-hologram", Hdr = true, W = 960, H = 600)]
        static void Hologram(Shot s)
        {
            HoloStage(s);
            var m = Holo(s);
            m.SetFloat("_GlitchChance", 0);
            m.SetFloat("_ScanDensity", 34);
            m.SetFloat("_Phase", 0.44f);        // 这一刻扫描亮带正好经过物体中部
            var k = s.Knot(m, new Vector3(0, 0.95f, 0), 0.72f);
            k.transform.rotation = Quaternion.Euler(70, 0, 0);
            // 投影台上的光圈：细圆环，同样用全息材质
            s.Torus(Holo(s), new Vector3(0, 0.12f, 0), 0.62f, 0.03f);
            s.LookAt(new Vector3(0, 1.35f, -3.6f), new Vector3(0, 0.75f, 0), 38);
            Glow(s, 1.1f, 0.9f);
        }

        [BookShot("ch18-hologram-steps", Hdr = true, W = 480, H = 480, Panels = 4)]
        static void HologramSteps(Shot s)
        {
            HoloStage(s);
            var m = Holo(s);
            var tg = new[] { new Vector4(0, 0, 0, 0), new Vector4(1, 0, 0, 0), new Vector4(1, 1, 1, 0), new Vector4(1, 1, 1, 1) }[s.Panel];
            m.SetVector("_Toggles", tg);
            m.SetFloat("_GlitchChance", 1);     // 拍图时强制本拍触发故障
            m.SetFloat("_GlitchAmount", 0.07f);
            m.SetFloat("_ChromaShift", 0.33f);
            m.SetFloat("_ScanDensity", 26);
            var k = s.Knot(m, new Vector3(0, 0.95f, 0), 0.72f);
            k.transform.rotation = Quaternion.Euler(70, 0, 0);
            s.LookAt(new Vector3(0, 1.25f, -3.3f), new Vector3(0, 0.85f, 0), 36);
            Glow(s, 0.8f, 1.0f);
        }

        // ---------- 18.6/18.7 护盾 ----------
        static Material ShieldMat(Shot s)
        {
            var m = s.Mat("Cookbook/Ch18/Shield");
            m.SetFloat("_Phase", 0.8f);
            return m;
        }

        static GameObject ShieldStage(Shot s, Material shield)
        {
            s.Background(new Color(0.03f, 0.04f, 0.06f));
            s.Floor(DarkFloorMat(s, 0.35f));
            s.SunDir(40, -40, 0.9f);
            // 罩子里的“角色”和道具
            s.Capsule(s.Lit(new Color(0.8f, 0.55f, 0.3f), 0, 0.4f), new Vector3(0, 0.9f, 0.2f), 0.9f);
            s.Cube(s.Lit(new Color(0.5f, 0.5f, 0.55f), 0.2f, 0.4f), new Vector3(-1.9f, 0.5f, 0.4f), 1.0f);       // 一半在罩子外
            s.Cylinder(s.Lit(new Color(0.35f, 0.4f, 0.45f), 0, 0.3f), new Vector3(1.55f, 1.0f, -0.6f), 0.5f)
             .transform.localScale = new Vector3(0.5f, 1.4f, 0.5f);                                               // 柱子穿过罩子
            var go = s.Sphere(shield, new Vector3(0, 0, 0), 4.4f);    // 半径 2.2，下半球埋在地面以下
            s.LookAt(new Vector3(0, 2.3f, -6.2f), new Vector3(0, 0.9f, 0), 40);
            return go;
        }

        static Vector3 OnShield(Vector3 dir) => dir.normalized * 2.2f;

        [BookShot("ch18-shield", Hdr = true, W = 960, H = 600)]
        static void ShieldHero(Shot s)
        {
            var m = ShieldMat(s);
            m.SetVector("_HitPos", OnShield(new Vector3(-0.5f, 0.55f, -1f)));
            m.SetFloat("_HitProgress", 0.28f);
            ShieldStage(s, m);
            Glow(s, 1.0f, 0.9f);
        }

        [BookShot("ch18-shield-intersect", W = 640, H = 440, Panels = 3)]
        static void ShieldIntersect(Shot s)
        {
            var m = ShieldMat(s);
            m.SetFloat("_HexStrength", 0.25f);
            m.SetFloat("_IntersectStrength", s.Panel == 0 ? 0 : 3);
            m.SetFloat("_IntersectWidth", s.Panel == 2 ? 0.6f : 0.12f);
            ShieldStage(s, m);
        }

        [BookShot("ch18-shield-hit", Hdr = true, W = 480, H = 400, Panels = 4)]
        static void ShieldHit(Shot s)
        {
            var m = ShieldMat(s);
            m.SetVector("_HitPos", OnShield(new Vector3(0.2f, 0.6f, -1f)));
            m.SetFloat("_HitProgress", new[] { 0.06f, 0.25f, 0.5f, 0.78f }[s.Panel]);
            m.SetFloat("_HexStrength", 0.35f);
            ShieldStage(s, m);
            s.LookAt(new Vector3(0, 2.0f, -5.4f), new Vector3(0, 1.0f, 0), 40);
            Glow(s, 0.8f, 1.0f);
        }

        // ---------- 18.8 扭曲隐身 ----------
        [BookShot("ch18-cloak", W = 640, H = 480, Panels = 3)]
        static void Cloak(Shot s)
        {
            s.Floor();
            var wall = s.Quad(s.Lit(Color.white, 0, 0.2f), new Vector3(0, 1.5f, 1.6f), 1);
            wall.transform.localScale = new Vector3(6, 3, 1);
            var wm = wall.GetComponent<MeshRenderer>().sharedMaterial;
            wm.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            wm.SetTextureScale("_BaseMap", new Vector2(3, 1.5f));

            var m = s.Mat("Cookbook/Ch18/Cloak");
            m.SetTexture("_NoiseMap", s.CoreTex("noise_fbm"));
            m.SetFloat("_Phase", 0.5f);
            m.SetColor("_BaseColor", new Color(0.3f, 0.45f, 0.65f));
            if (s.Panel == 0) m.SetFloat("_Reveal", 1);
            if (s.Panel == 1) { m.SetColor("_RimColor", Color.black); m.SetFloat("_NoiseDistortion", 0); }
            if (s.Panel == 2) { m.SetFloat("_NoiseDistortion", 0.02f); }
            var k = s.Knot(m, new Vector3(0, 1.0f, 0.2f), 1.0f);
            k.transform.rotation = Quaternion.Euler(80, 0, 0);
            s.Sphere(m, new Vector3(1.35f, 0.4f, -0.3f), 0.8f);
            s.LookAt(new Vector3(0, 1.3f, -3.6f), new Vector3(0.2f, 0.9f, 0), 40);
        }

        // ---------- 18.9 冰冻 ----------
        static Material FrozenMat(Shot s, string tex, Color c, float freeze)
        {
            var m = s.Mat("Cookbook/Ch18/Frozen");
            m.SetTexture("_BaseMap", s.CoreTex(tex));
            m.SetColor("_BaseColor", c);
            m.SetTexture("_IceNoise", s.CoreTex("noise_fbm"));
            m.SetTexture("_CrackMap", s.CoreTex("noise_cells"));
            m.SetFloat("_Freeze", freeze);
            m.SetColor("_IceColor", new Color(0.62f, 0.82f, 0.95f));
            m.SetColor("_IceDeepColor", new Color(0.12f, 0.3f, 0.55f));
            return m;
        }

        [BookShot("ch18-frozen", W = 480, H = 420, Panels = 4)]
        static void Frozen(Shot s)
        {
            float f = new[] { 0f, 0.35f, 0.62f, 0.9f }[s.Panel];
            s.Floor(DarkFloorMat(s, 0.5f));
            s.Knot(FrozenMat(s, "paintedmetal_albedo", new Color(1f, 0.55f, 0.45f), f), new Vector3(0.1f, 0.62f, 0.3f), 0.8f);
            s.Sphere(FrozenMat(s, "bricks_albedo", Color.white, f), new Vector3(-0.95f, 0.45f, -0.35f), 0.9f);
            var c = s.Capsule(FrozenMat(s, "uv_grid", new Color(0.7f, 0.85f, 0.6f), f), new Vector3(1.0f, 0.55f, -0.5f), 0.55f);
            s.LookAt(new Vector3(0, 2.2f, -4.3f), new Vector3(0, 0.4f, 0), 38);
            s.SunDir(42, -40, 1.4f);
        }

        // ---------- 18.10 扫描线 ----------
        [BookShot("ch18-scan", Hdr = true, W = 640, H = 480, Panels = 3)]
        static void Scan(Shot s)
        {
            float h = new[] { 0.35f, 0.95f, 1.6f }[s.Panel];
            Material M(Color c) { var m = s.Mat("Cookbook/Ch18/ScanLine"); m.SetColor("_BaseColor", c); m.SetFloat("_ScanHeight", h); return m; }
            s.Floor(DarkFloorMat(s, 0.4f));
            s.Background(new Color(0.06f, 0.07f, 0.09f));
            s.Capsule(M(new Color(0.8f, 0.5f, 0.3f)), new Vector3(-0.9f, 0.9f, 0.2f), 0.9f);
            s.Sphere(M(new Color(0.4f, 0.6f, 0.85f)), new Vector3(0.1f, 0.45f, -0.4f), 0.9f);
            var k = s.Knot(M(new Color(0.75f, 0.75f, 0.7f)), new Vector3(1.0f, 1.0f, 0.4f), 0.8f);
            k.transform.rotation = Quaternion.Euler(80, 20, 0);
            s.LookAt(new Vector3(0, 1.6f, -3.8f), new Vector3(0, 0.85f, 0), 40);
            Glow(s, 0.7f, 1.0f);
        }
    }
}
