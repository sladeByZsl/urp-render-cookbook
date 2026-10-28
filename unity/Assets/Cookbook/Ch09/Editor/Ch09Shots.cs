// 第 9 章配图：BRDF 各项的粗糙度扫描、NDF/G 对比、菲涅尔、白炉测试、Gamma vs 线性、HDR 与色调映射、两种工作流。
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch09
{
    static class Ch09Shots
    {
        static readonly float[] Rough = { 0.1f, 0.3f, 0.5f, 0.7f, 0.9f };

        // 线性颜色 → 交给 SetColor/Background 的 sRGB 值（Unity 在线性空间下会把 Color 属性当 sRGB 再转回线性）
        static Color Lin(float r, float g, float b) => new Color(r, g, b).gamma;
        static Vector4 V(float x) => new Vector4(x, x, x, 0);

        // 一排 5 个球，用正交相机正面拍，避免透视把两端的球拉变形
        static void Row(Shot s, System.Func<int, Material> mat)
        {
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.SphereRow(5, mat, 0f, 0f, 1.15f, 1f);
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = 0.74f;
            s.Cam.transform.position = new Vector3(0, 0, -10);
            s.Cam.transform.rotation = Quaternion.identity;
            s.SunDir(35, 30, 1.0f);           // 光从左上前方来
            s.Sun.shadows = LightShadows.None;
        }

        static Material Terms(Shot s, float mode, float rough)
        {
            var m = s.Mat("Cookbook/Ch09/BRDFTerms");
            m.SetFloat("_Mode", mode);
            m.SetFloat("_Roughness", rough);
            return m;
        }

        [BookShot("ch09-terms-d", W = 960, H = 220)]
        static void TermsD(Shot s)
        {
            Row(s, i => { var m = Terms(s, 0, Rough[i]); m.SetFloat("_Display", 1); m.SetFloat("_Exposure", 1f); return m; });
        }

        [BookShot("ch09-terms-g", W = 960, H = 220)]
        static void TermsG(Shot s)
        {
            Row(s, i => { var m = Terms(s, 1, Rough[i]); m.SetFloat("_GModel", 1); return m; });
        }

        [BookShot("ch09-terms-f", W = 960, H = 220)]
        static void TermsF(Shot s)
        {
            // 这一排扫的是 F0：水、塑料/玻璃、钻石、金、银（金属取常见资料中的近似线性值，仅作示意）
            Vector4[] f0 =
            {
                V(0.02f), V(0.04f), V(0.17f),
                new Vector4(1.00f, 0.71f, 0.29f, 0), new Vector4(0.95f, 0.93f, 0.88f, 0)
            };
            Row(s, i => { var m = Terms(s, 2, 0.5f); m.SetVector("_F0", f0[i]); return m; });
        }

        [BookShot("ch09-terms-spec", W = 960, H = 220)]
        static void TermsSpec(Shot s)
        {
            Row(s, i =>
            {
                var m = Terms(s, 4, Rough[i]);
                m.SetVector("_F0", V(0.9f));
                m.SetFloat("_Display", 1); m.SetFloat("_Exposure", 1f);
                return m;
            });
        }

        [BookShot("ch09-terms-full", W = 960, H = 220)]
        static void TermsFull(Shot s)
        {
            Row(s, i =>
            {
                var m = Terms(s, 6, Rough[i]);
                m.SetColor("_Albedo", new Color(0.45f, 0.1f, 0.07f));
                m.SetVector("_F0", V(0.04f));
                return m;
            });
            s.Sun.intensity = 2.2f;
        }

        // 单球特写的公共布景
        static void Single(Shot s, Material m, float pitch, float yaw)
        {
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.Sphere(m, Vector3.zero, 2f);
            s.LookAt(new Vector3(0, 0, -6.2f), Vector3.zero, 24);
            s.SunDir(pitch, yaw, 1f);
            s.Sun.shadows = LightShadows.None;
        }

        //#region ndfshot
        [BookShot("ch09-ndf-compare", W = 420, H = 360, Panels = 3)]
        static void NdfCompare(Shot s)
        {
            var m = Terms(s, 0, 0.45f);
            m.SetFloat("_NDF", s.Panel);           // GGX / Beckmann / Blinn-Phong
            m.SetFloat("_Display", 1); m.SetFloat("_Exposure", 0.6f);
            Single(s, m, 30, 25);
        }
        //#endregion

        [BookShot("ch09-g-compare", W = 420, H = 360, Panels = 3)]
        static void GCompare(Shot s)
        {
            var m = Terms(s, 1, 1.0f);
            m.SetFloat("_GModel", new[] { 0f, 1f, 3f }[s.Panel]);   // 分离 / 高度相关 / 差值×10
            Single(s, m, 10, 70);
        }

        //#region fresnelshot
        [BookShot("ch09-fresnel-angle", W = 420, H = 300, Panels = 3)]
        static void FresnelAngle(Shot s)
        {
            // 一块光滑的电介质地板，相机仰角从高到低；灯放在相机的镜面方向上，让高光正好落在画面中央。
            // 高光中心处 v·h = sin(仰角)：70° → 0.94，35° → 0.57，12° → 0.21
            float e = new[] { 70f, 35f, 12f }[s.Panel];
            var m = Terms(s, 4, 0.35f);
            m.SetVector("_F0", V(0.04f));
            m.SetFloat("_Display", 1); m.SetFloat("_Exposure", 1.0f);
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.Grid(m, Vector3.zero, 40f, 8);
            float r = e * Mathf.Deg2Rad;
            s.LookAt(new Vector3(0, 6 * Mathf.Sin(r), -6 * Mathf.Cos(r)), Vector3.zero, 40);
            s.SunDir(e, 180, 1f);
            s.Sun.shadows = LightShadows.None;
        }
        //#endregion

        [BookShot("ch09-diffuse", W = 420, H = 360, Panels = 3)]
        static void Diffuse(Shot s)
        {
            var m = Terms(s, 5, s.Panel == 2 ? 1f : 0.02f);
            m.SetFloat("_DiffuseModel", s.Panel == 0 ? 0 : 1);
            m.SetColor("_Albedo", new Color(0.85f, 0.85f, 0.85f));
            Single(s, m, 0, 0);   // 灯放在相机正后方：l = v，最能看出 Disney 漫反射在掠射角的差别
        }

        [BookShot("ch09-furnace", W = 360, H = 360, Panels = 4)]
        static void Furnace(Shot s)
        {
            var env = new Color(0.5f, 0.5f, 0.5f);
            var m = s.Mat("Cookbook/Ch09/WhiteFurnace");
            m.SetFloat("_Model", s.Panel == 0 ? 0 : 1);
            m.SetFloat("_Roughness", new[] { 1f, 0.2f, 0.6f, 1f }[s.Panel]);
            m.SetFloat("_Albedo", 1f);
            m.SetColor("_EnvColor", env);
            m.SetFloat("_SampleCount", 1024);
            s.Background(env);                     // 背景亮度 = 环境亮度
            s.Sphere(m, Vector3.zero, 2f);
            s.LookAt(new Vector3(0, 0, -6.4f), Vector3.zero, 24);
            s.Sun.intensity = 0;
        }

        [BookShot("ch09-gamma", W = 480, H = 400, Panels = 2)]
        static void Gamma(Shot s)
        {
            var m = s.Mat("Cookbook/Ch09/GammaVsLinear");
            m.SetFloat("_GammaSpace", s.Panel == 0 ? 0 : 1);
            m.SetColor("_BaseColor", new Color(0.8f, 0.8f, 0.8f));
            m.SetColor("_Light2Color", new Color(0.25f, 0.5f, 1f));
            m.SetVector("_Light2Dir", new Vector4(1f, 0.25f, -0.35f, 0));
            s.Background(new Color(0.08f, 0.08f, 0.09f));
            s.Sphere(m, Vector3.zero, 2f);
            s.LookAt(new Vector3(0, 0, -6.2f), Vector3.zero, 26);
            s.SunDir(15, 70, 1f);
            s.Sun.color = new Color(1f, 0.6f, 0.25f);
            s.Sun.shadows = LightShadows.None;
        }

        //#region hdr
        [BookShot("ch09-hdr", W = 420, H = 320, Panels = 3)]
        static void Hdr(Shot s)
        {
            s.Floor();
            s.Sphere(s.Lit(new Color(0.9f, 0.9f, 0.9f), 1f, 0.92f), new Vector3(-0.85f, 0.55f, 0.3f), 1.1f);
            s.Sphere(s.Lit(new Color(0.8f, 0.25f, 0.15f), 0f, 0.8f), new Vector3(0.85f, 0.55f, 0.3f), 1.1f);
            var glow = s.Lit(Color.black, 0, 0.5f);
            glow.EnableKeyword("_EMISSION");
            glow.SetColor("_EmissionColor", new Color(1f, 0.4f, 0.1f) * 5f);
            s.Cube(glow, new Vector3(0, 0.25f, -0.6f), 0.5f);
            s.SunDir(35, -40, 4.5f);
            if (s.Panel > 0)
            {
                var t = s.Post().Add<Tonemapping>();
                t.mode.Override(s.Panel == 1 ? TonemappingMode.Neutral : TonemappingMode.ACES);
            }
        }
        //#endregion

        //#region workflow
        [BookShot("ch09-workflow", W = 420, H = 320, Panels = 3)]
        static void Workflow(Shot s)
        {
            s.Floor();
            Material m;
            if (s.Panel == 0)
            {
                m = s.Lit(new Color(1f, 0.78f, 0.34f), 1f, 0.75f);          // 金属度工作流：金属 = 1，底色即 F0
            }
            else
            {
                m = s.Lit(Color.black, 0f, 0.75f);
                m.SetFloat("_WorkflowMode", 0);
                m.EnableKeyword("_SPECULAR_SETUP");                        // 脚本建的材质不会跑 ShaderGUI，关键字要自己开
                if (s.Panel == 1)
                    m.SetColor("_SpecColor", new Color(1f, 0.78f, 0.34f)); // 镜面工作流：漫反射黑、镜面色 = 同样的金色
                else
                {
                    m.SetColor("_BaseColor", new Color(0.7f, 0.08f, 0.06f));
                    m.SetColor("_SpecColor", new Color(0.25f, 0.45f, 0.75f)); // 红色漫反射 + 蓝色高光：金属度工作流表达不了
                }
            }
            s.Sphere(m, new Vector3(0, 0.75f, 0), 1.5f);
            s.LookAt(new Vector3(0, 1.35f, -4.0f), new Vector3(0, 0.7f, 0), 32);
        }
        //#endregion
    }
}
