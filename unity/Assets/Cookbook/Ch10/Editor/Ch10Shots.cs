// 第 10 章配图：最小 Lit 对照、光照分量拆分、高光近似对比、白炉测试、Simple Lit vs Lit、金属度×粗糙度矩阵。
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch10
{
    static class Ch10Shots
    {
        static Vector4 V(float x) => new Vector4(x, x, x, 0);

        // 两张对照图共用的场景：砖块立方体 + 金属球 + 塑料球 + 一盏橙色点光
        static void Scene(Shot s, System.Func<Material> newMat, bool alsoFloor)
        {
            Material Make(Color c, float metal, float smooth, Texture2D albedo = null, Texture2D normal = null)
            {
                var m = newMat();
                m.SetColor("_BaseColor", c); m.SetFloat("_Metallic", metal); m.SetFloat("_Smoothness", smooth);
                if (albedo != null) m.SetTexture("_BaseMap", albedo);
                if (normal != null) { m.SetTexture("_BumpMap", normal); m.EnableKeyword("_NORMALMAP"); }
                return m;
            }

            if (alsoFloor)
            {
                var fm = Make(new Color(0.75f, 0.75f, 0.75f), 0, 0.15f, s.CoreTex("checker"));
                fm.SetTextureScale("_BaseMap", new Vector2(7.5f, 7.5f));
                s.Floor(fm);
            }
            else s.Floor();

            var brick = s.Cube(Make(Color.white, 0, 0.3f, s.CoreTex("bricks_albedo"), s.CoreTex("bricks_normal")), new Vector3(0, 0.5f, 0.9f), 1f);
            brick.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Sphere(Make(new Color(1f, 0.78f, 0.34f), 1f, 0.85f), new Vector3(-1.15f, 0.5f, -0.1f), 1f);
            s.Sphere(Make(new Color(0.75f, 0.12f, 0.1f), 0f, 0.65f), new Vector3(1.1f, 0.5f, -0.2f), 1f);
            s.Point(new Vector3(0.2f, 1.1f, -0.9f), new Color(1f, 0.55f, 0.25f), 2.5f, 4f);
            s.LookAt(new Vector3(0, 1.7f, -4.0f), new Vector3(0, 0.45f, 0.1f), 36);
        }

        [BookShot("ch10-minimal-vs-lit", W = 560, H = 380, Panels = 2)]
        static void MinimalVsLit(Shot s)
        {
            string shader = s.Panel == 0 ? "Universal Render Pipeline/Lit" : "Cookbook/Ch10/MinimalLit";
            Scene(s, () => s.Mat(shader), true);
        }

        [BookShot("ch10-breakdown", W = 400, H = 300, Panels = 5)]
        static void Breakdown(Shot s)
        {
            // 0 直接漫反射 / 1 直接高光 / 2 间接漫反射 / 3 间接高光 / 4 完整（URP 原函数）
            float comp = new[] { 1f, 2f, 3f, 4f, 0f }[s.Panel];
            Scene(s, () => { var m = s.Mat("Cookbook/Ch10/LitBreakdown"); m.SetFloat("_Component", comp); return m; }, true);
        }

        [BookShot("ch10-breakdown-sum", W = 400, H = 300, Panels = 2)]
        static void BreakdownSum(Shot s)
        {
            float comp = s.Panel == 0 ? 0f : 5f;   // URP 原函数 vs 四项相加
            Scene(s, () => { var m = s.Mat("Cookbook/Ch10/LitBreakdown"); m.SetFloat("_Component", comp); return m; }, true);
        }

        static void OrthoRows(Shot s, float size, float y = 0f)
        {
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = size;
            s.Cam.transform.position = new Vector3(0, y, -10);
            s.Cam.transform.rotation = Quaternion.identity;
        }

        static readonly float[] Smooth = { 0.9f, 0.7f, 0.5f, 0.3f, 0.1f };   // 对应感知粗糙度 0.1 … 0.9

        [BookShot("ch10-spec-compare", W = 960, H = 420)]
        static void SpecCompare(Shot s)
        {
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            for (int row = 0; row < 2; row++)
                s.SphereRow(5, i =>
                {
                    var m = s.Mat("Cookbook/Ch10/SpecCompare");
                    m.SetFloat("_Mode", row);            // 上：URP 近似；下：标准 GGX
                    m.SetFloat("_Smoothness", Smooth[i]);
                    m.SetVector("_F0", V(0.9f));
                    return m;
                }, row == 0 ? 0.62f : -0.62f, 0, 1.15f, 1f);
            OrthoRows(s, 1.4f);
            s.SunDir(35, 30, 1f);
            s.Sun.shadows = LightShadows.None;
        }

        [BookShot("ch10-spec-furnace", W = 960, H = 420)]
        static void SpecFurnace(Shot s)
        {
            var env = new Color(0.5f, 0.5f, 0.5f);
            s.Background(env);
            for (int row = 0; row < 2; row++)
                s.SphereRow(5, i =>
                {
                    var m = s.Mat("Cookbook/Ch10/SpecFurnace");
                    m.SetFloat("_Mode", row);
                    m.SetFloat("_Smoothness", Smooth[i]);
                    m.SetColor("_EnvColor", env);
                    return m;
                }, row == 0 ? 0.62f : -0.62f, 0, 1.15f, 1f);
            OrthoRows(s, 1.4f);
            s.Sun.intensity = 0;
        }

        [BookShot("ch10-simplelit-vs-lit", W = 960, H = 420)]
        static void SimpleLitVsLit(Shot s)
        {
            var baseCol = new Color(0.2f, 0.45f, 0.75f);
            s.Background(new Color(0.3f, 0.31f, 0.33f));   // 纯色背景只影响画面，反射仍来自天空盒
            for (int row = 0; row < 2; row++)
                s.SphereRow(5, i =>
                {
                    Material m;
                    if (row == 0)
                    {
                        m = s.Mat("Universal Render Pipeline/Simple Lit");
                        m.SetColor("_BaseColor", baseCol);
                        // Simple Lit 的光泽度存在 _SpecColor.a 里（材质面板会自动拷过去，脚本要自己写）
                        m.SetColor("_SpecColor", new Color(0.5f, 0.5f, 0.5f, Smooth[i]));
                        m.SetFloat("_Smoothness", Smooth[i]);
                        m.EnableKeyword("_SPECULAR_COLOR");
                    }
                    else m = s.Lit(baseCol, 0f, Smooth[i]);
                    return m;
                }, row == 0 ? 0.62f : -0.62f, 0, 1.15f, 1f);
            OrthoRows(s, 1.4f);
            s.SunDir(35, 30, 1.2f);
            s.Sun.shadows = LightShadows.None;
        }

        //#region matrix
        [BookShot("ch10-matrix", W = 900, H = 820)]
        static void Matrix(Shot s)
        {
            // 行：金属度 0 → 1（从上到下）；列：光滑度 0 → 1（从左到右）
            var baseCol = new Color(0.95f, 0.64f, 0.38f);
            s.Background(new Color(0.3f, 0.31f, 0.33f));
            for (int r = 0; r < 5; r++)
                for (int c = 0; c < 5; c++)
                    s.Sphere(s.Lit(baseCol, r / 4f, c / 4f), new Vector3((c - 2) * 1.12f, (2 - r) * 1.12f, 0), 1f);
            OrthoRows(s, 2.95f);
            s.SunDir(35, 30, 1.3f);
            s.Sun.shadows = LightShadows.None;
        }
        //#endregion
    }
}
