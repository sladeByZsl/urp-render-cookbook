// 第 28 章配图
using Cookbook.Core;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch28
{
    static class Shots
    {
        // 一个小“庭院”：地面 + 各种几何体，屏幕空间效果都在它上面演示
        static void Courtyard(Shot s)
        {
            s.Floor();
            s.Cube(s.Lit(new Color(0.8f, 0.35f, 0.25f)), new Vector3(-1.6f, 0.5f, 1.0f));
            s.Cube(s.Lit(new Color(0.85f, 0.8f, 0.7f)), new Vector3(-1.6f, 1.25f, 1.0f), 0.5f);
            s.Sphere(s.Lit(new Color(0.25f, 0.5f, 0.85f), 0, 0.7f), new Vector3(0.1f, 0.6f, 0.4f), 1.2f);
            s.Cylinder(s.Lit(new Color(0.9f, 0.75f, 0.3f)), new Vector3(1.7f, 0.75f, 1.4f), 0.8f);
            s.Knot(s.Lit(new Color(0.4f, 0.75f, 0.45f), 0, 0.6f), new Vector3(1.0f, 0.55f, -0.6f), 0.35f);
            var wall = s.Cube(s.Lit(new Color(0.7f, 0.7f, 0.72f)), new Vector3(0, 1.0f, 3.2f));
            wall.transform.localScale = new Vector3(7f, 2f, 0.3f);
        }

        static ScreenEffectFeature Effect(Shot s, string shader, int pass = 0, ScriptableRenderPassInput req = ScriptableRenderPassInput.Depth)
        {
            var f = s.Feature<ScreenEffectFeature>();
            f.settings.material = s.Mat(shader);
            f.settings.passIndex = pass;
            f.settings.requirements = req;
            return f;
        }

        [BookShot("ch28-reconstruct", W = 640, H = 420, Panels = 3)]
        static void Reconstruct(Shot s)
        {
            Courtyard(s);
            s.LookAt(new Vector3(0.5f, 2.6f, -4.6f), new Vector3(0, 0.5f, 1f), 42);
            if (s.Panel > 0) Effect(s, "Cookbook/Ch28/ReconstructWorldPos", s.Panel - 1);
        }

        [BookShot("ch28-scan", W = 640, H = 420, Panels = 3)]
        static void Scan(Shot s)
        {
            Courtyard(s);
            s.SunDir(50, -30, 0.9f);
            s.LookAt(new Vector3(0, 4.2f, -6.5f), new Vector3(0, 0, 1.2f), 45);
            var f = Effect(s, "Cookbook/Ch28/RadarScan");
            var m = f.settings.material;
            m.SetVector("_ScanCenter", new Vector4(-0.3f, 0, -0.8f, 0));
            m.SetFloat("_MaxRadius", 12f);
            m.SetFloat("_TrailWidth", 3f);
            m.SetFloat("_Progress", new[] { 0.12f, 0.26f, 0.42f }[s.Panel]);
        }

        // 往远处延伸的柱廊，用来看雾随距离和高度的变化
        static void Colonnade(Shot s)
        {
            s.Floor(null, 200f);
            var pillar = s.Lit(new Color(0.82f, 0.78f, 0.7f));
            var block = s.Lit(new Color(0.75f, 0.4f, 0.3f));
            for (int i = 0; i < 14; i++)
            {
                float z = 2 + i * 5f;
                foreach (float x in new[] { -4f, 4f })
                {
                    var c = s.Cylinder(pillar, new Vector3(x, 3f, z));
                    c.transform.localScale = new Vector3(0.9f, 3f, 0.9f);
                }
                var b = s.Cube(block, new Vector3((i % 3 - 1) * 1.6f, 0.4f + (i % 2) * 0.4f, z + 2.5f));
                b.transform.localScale = new Vector3(1.2f, 0.8f + (i % 2) * 0.8f, 1.2f);
            }
            // 远处一座高塔：高度雾里塔身下半截被吞、上半截露出
            var tower = s.Cube(s.Lit(new Color(0.55f, 0.6f, 0.7f)), new Vector3(9f, 9f, 55f));
            tower.transform.localScale = new Vector3(5f, 18f, 5f);
        }

        [BookShot("ch28-fog", W = 640, H = 420, Panels = 3)]
        static void Fog(Shot s)
        {
            Colonnade(s);
            s.SunDir(14, 160, 1.3f);
            s.LookAt(new Vector3(0, 1.7f, -4f), new Vector3(0.6f, 2.6f, 20f), 50);
            var m = Effect(s, "Cookbook/Ch28/HeightFog").settings.material;
            m.SetFloat("_DistanceDensity", s.Panel == 1 ? 0f : 0.03f);
            m.SetFloat("_HeightDensity", s.Panel == 0 ? 0f : 0.35f);
            m.SetFloat("_HeightFalloff", 0.9f);
            m.SetFloat("_SunScatterPower", s.Panel == 2 ? 16f : 1e4f);
            m.SetColor("_SunScatterColor", new Color(0.7f, 0.6f, 0.45f));
        }

        // URP 自带 SSAO 是 internal 类，只能用反射创建，并用 SerializedObject 改它的设置
        static void AddUrpSsao(Shot s, float intensity, float radius)
        {
            var t = typeof(UniversalRendererData).Assembly.GetType("UnityEngine.Rendering.Universal.ScreenSpaceAmbientOcclusion");
            var f = (ScriptableRendererFeature)ScriptableObject.CreateInstance(t);
            f.name = "SSAO";
            s.Temp.Add(f);
            var so = new SerializedObject(f);
            so.FindProperty("m_Settings.Intensity").floatValue = intensity;
            so.FindProperty("m_Settings.Radius").floatValue = radius;
            so.ApplyModifiedPropertiesWithoutUndo();
            s.Renderer.rendererFeatures.Add(f);
            s.Renderer.SetDirty();
        }

        // AO 演示场景：墙角、堆叠的方块、贴地的球——到处都是缝隙
        static void Corner(Shot s)
        {
            s.Floor(s.Lit(new Color(0.78f, 0.78f, 0.78f), 0, 0.2f));
            var white = s.Lit(new Color(0.85f, 0.85f, 0.85f), 0, 0.2f);
            var w1 = s.Cube(white, new Vector3(0, 1.5f, 2.2f)); w1.transform.localScale = new Vector3(8, 3, 0.2f);
            var w2 = s.Cube(white, new Vector3(-2.6f, 1.5f, 0)); w2.transform.localScale = new Vector3(0.2f, 3, 6);
            s.Cube(s.Lit(new Color(0.8f, 0.45f, 0.35f), 0, 0.2f), new Vector3(-1.9f, 0.5f, 1.5f));
            var c2 = s.Cube(s.Lit(new Color(0.85f, 0.75f, 0.5f), 0, 0.2f), new Vector3(-1.75f, 1.3f, 1.55f), 0.6f);
            c2.transform.rotation = Quaternion.Euler(0, 25, 0);
            s.Sphere(s.Lit(new Color(0.4f, 0.55f, 0.8f), 0, 0.3f), new Vector3(-0.2f, 0.5f, 1.2f), 1f);
            s.Sphere(s.Lit(new Color(0.6f, 0.75f, 0.5f), 0, 0.3f), new Vector3(0.75f, 0.3f, 0.7f), 0.6f);
            s.Knot(s.Lit(new Color(0.85f, 0.85f, 0.85f), 0, 0.3f), new Vector3(1.8f, 0.45f, 1.3f), 0.3f);
            s.SunDir(55, 30, 0.25f);   // 主光压低，让环境光（被 AO 影响的那部分）占主导
            s.LookAt(new Vector3(1.4f, 2.3f, -3.4f), new Vector3(-0.3f, 0.6f, 1.2f), 45);
        }

        [BookShot("ch28-ssao-urp", W = 640, H = 420, Panels = 3)]
        static void SsaoUrp(Shot s)
        {
            Corner(s);
            if (s.Panel == 1) AddUrpSsao(s, 3f, 0.035f);   // 默认参数
            if (s.Panel == 2) AddUrpSsao(s, 2f, 0.15f);    // 加大半径
        }

        [BookShot("ch28-myssao", W = 640, H = 420, Panels = 3)]
        static void MySsao(Shot s)
        {
            Corner(s);
            var f = s.Feature<SimpleSSAOFeature>();
            f.settings.material = s.Mat("Cookbook/Ch28/SimpleSSAO");
            f.settings.mode = s.Panel == 2 ? SimpleSSAOFeature.Mode.IntoLighting : SimpleSSAOFeature.Mode.ShowAO;
            f.settings.blur = s.Panel != 0;
            f.settings.directLightingStrength = 0.4f;
            f.settings.material.SetFloat("_Intensity", 2.2f);
        }

        // 一排高柱 + 横梁，太阳从柱廊后方低角度照过来，镜头迎着光
        static void Gate(Shot s)
        {
            s.Floor(s.Lit(new Color(0.55f, 0.52f, 0.48f), 0, 0.1f));
            var stone = s.Lit(new Color(0.6f, 0.58f, 0.55f), 0, 0.1f);
            for (int i = -5; i <= 5; i++)
            {
                var p = s.Cube(stone, new Vector3(i * 1.3f, 2.5f, 5f));
                p.transform.localScale = new Vector3(0.55f, 5f, 0.55f);
            }
            var roof = s.Cube(stone, new Vector3(0, 5.2f, 6.5f));
            roof.transform.localScale = new Vector3(15f, 0.4f, 3.5f);
            for (int i = 0; i < 6; i++)
            {
                var beam = s.Cube(stone, new Vector3(0, 5.0f, 5.2f + i * 0.6f));
                beam.transform.localScale = new Vector3(15f, 0.25f, 0.2f);
            }
            s.Sphere(s.Lit(new Color(0.7f, 0.3f, 0.25f)), new Vector3(-1.2f, 0.6f, 1.0f), 1.2f);
            s.Cube(s.Lit(new Color(0.3f, 0.45f, 0.7f)), new Vector3(1.6f, 0.5f, 0.6f));
            s.SunDir(22, 192, 2.2f);
            s.Background(new Color(0.42f, 0.5f, 0.62f));
            s.LookAt(new Vector3(0.4f, 1.5f, -6.5f), new Vector3(0, 2.6f, 5f), 55);
        }

        [BookShot("ch28-vollight", W = 640, H = 420, Panels = 3, Hdr = true)]
        static void VolLight(Shot s)
        {
            Gate(s);
            if (s.Panel == 0) return;
            var f = s.Feature<VolumetricLightFeature>();
            var m = s.Mat("Cookbook/Ch28/VolumetricLight");
            m.SetFloat("_Density", 0.05f);
            m.SetFloat("_Anisotropy", 0.4f);
            m.SetFloat("_Intensity", 0.3f);
            f.settings.material = m;
            f.settings.blur = s.Panel == 2;
            f.settings.output = s.Panel == 1 ? VolumetricLightFeature.Output.ScatterOnly : VolumetricLightFeature.Output.Composite;
        }

        [BookShot("ch28-ssr", W = 800, H = 450, Panels = 2)]
        static void Ssr(Shot s)
        {
            s.Floor(s.Lit(new Color(0.12f, 0.12f, 0.13f), 0, 0.85f));
            s.Sphere(s.Lit(new Color(0.9f, 0.3f, 0.2f), 0, 0.6f), new Vector3(-1.4f, 0.6f, 2.0f), 1.2f);
            s.Cube(s.Lit(new Color(0.25f, 0.55f, 0.9f), 0, 0.5f), new Vector3(0.6f, 0.75f, 2.8f), 1.5f);
            s.Cylinder(s.Lit(new Color(0.95f, 0.8f, 0.3f), 0, 0.5f), new Vector3(2.2f, 1f, 1.6f), 1f);
            s.Knot(s.Lit(new Color(0.4f, 0.85f, 0.5f), 0, 0.6f), new Vector3(-0.2f, 0.55f, 0.6f), 0.4f);
            s.SunDir(35, -40, 1.3f);
            s.LookAt(new Vector3(0, 1.0f, -3.6f), new Vector3(0.2f, 0.5f, 2f), 45);
            if (s.Panel == 1)
                Effect(s, "Cookbook/Ch28/SimpleSSR", 0, ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }
    }
}
