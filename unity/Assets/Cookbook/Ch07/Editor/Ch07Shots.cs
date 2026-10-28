// 第 7 章配图：法线贴图与视差映射。
using Cookbook.Core;
using UnityEngine;

namespace Cookbook.Ch07
{
    static class Shots
    {
        // 一面砖墙：Quad 默认朝 -Z（正对默认相机），tiling 跟随尺寸保证砖块不被拉伸
        static GameObject Wall(Shot s, Material m, float w = 4.4f, float h = 2.6f, float z = 0.8f)
        {
            var go = s.Quad(m, new Vector3(0, h * 0.5f, z));
            go.transform.localScale = new Vector3(w, h, 1);
            return go;
        }

        static Material Bricks(Shot s, string shader, float w = 4.4f, float h = 2.6f)
        {
            var m = s.Mat(shader);
            m.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            m.SetTextureScale("_BaseMap", new Vector2(w / 1.4f, h / 1.4f));
            if (m.HasProperty("_BumpMap")) m.SetTexture("_BumpMap", s.CoreTex("bricks_normal"));
            if (m.HasProperty("_ParallaxMap")) m.SetTexture("_ParallaxMap", s.CoreTex("bricks_height"));
            if (m.HasProperty("_HeightMap")) m.SetTexture("_HeightMap", s.CoreTex("bricks_height"));
            return m;
        }

        // ---------------- 7.2 TBN 可视化 ----------------
        [BookShot("ch07-tbn", W = 480, H = 420, Panels = 4)]
        static void TBN(Shot s)
        {
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            var m = s.Mat("Cookbook/Ch07/TBNDebug");
            m.SetFloat("_Mode", s.Panel);
            m.SetTexture("_BumpMap", s.CoreTex("dots_normal"));
            m.SetVector("_Tiling", new Vector4(1, 1, 0, 0));
            m.SetFloat("_BumpScale", 1.2f);
            var k = s.Knot(m, new Vector3(0, 0.0f, 0), 1.25f);
            k.transform.rotation = Quaternion.Euler(-60, 0, 0);
            s.LookAt(new Vector3(0, 0.0f, -4.4f), new Vector3(0, 0.0f, 0), 30);
        }

        // ---------------- 7.3 法线贴图基础 ----------------
        static void NormalMapScene(Shot s, Material wall, Material ball)
        {
            s.Floor();
            Wall(s, wall);
            s.Sphere(ball, new Vector3(0.75f, 0.5f, -0.3f), 1.0f);
            // 光从左上方斜射到墙面：砖块上沿迎光、下沿背光，凹凸最容易看出来
            s.SunDir(48, 28, 1.5f);
            s.LookAt(new Vector3(-0.35f, 1.3f, -2.7f), new Vector3(0.1f, 0.95f, 0.4f), 36);
        }

        [BookShot("ch07-normalmap", W = 640, H = 480, Panels = 3)]
        static void NormalMapBasic(Shot s)
        {
            Material Make(float w, float h)
            {
                var m = Bricks(s, "Cookbook/Ch07/NormalMap", w * 0.6f, h * 0.6f);
                if (s.Panel == 0) m.DisableKeyword("_NORMALMAP"); else m.EnableKeyword("_NORMALMAP");
                m.SetFloat("_UseNormalMap", s.Panel == 0 ? 0 : 1);
                m.SetFloat("_BumpScale", s.Panel == 2 ? 2.5f : 1f);
                return m;
            }
            NormalMapScene(s, Make(4.4f, 2.6f), Make(2.8f, 1.4f));
        }

        [BookShot("ch07-normal-mistakes", W = 640, H = 480, Panels = 3)]
        static void NormalMistakes(Shot s)
        {
            Material Make(float w, float h)
            {
                var m = Bricks(s, "Cookbook/Ch07/NormalMistakes", w * 0.6f, h * 0.6f);
                m.SetFloat("_BumpScale", 1.5f);
                m.SetFloat("_Mistake", s.Panel);   // 0 正确 / 1 手写 rgb*2-1 / 2 Y 翻转
                return m;
            }
            NormalMapScene(s, Make(4.4f, 2.6f), Make(2.8f, 1.4f));
        }

        // ---------------- 7.4 细节法线混合 ----------------
        static readonly int[] DetailModes = { 0, 1, 2, 3 };

        static void DetailScene(Shot s, bool showNormal)
        {
            var m = s.Mat("Cookbook/Ch07/DetailNormal");
            m.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            if (showNormal)
            {
                // 看切线空间结果时，基础法线换成大圆包（坡面多），细节混合方法之间的差别才明显
                m.SetTextureScale("_BaseMap", new Vector2(0.25f, 0.25f));
                m.SetTexture("_BumpMap", s.CoreTex("dots_normal"));
                m.SetFloat("_BumpScale", 1.0f);
            }
            else
            {
                m.SetTextureScale("_BaseMap", new Vector2(1.2f, 1.2f));
                m.SetTexture("_BumpMap", s.CoreTex("bricks_normal"));
                m.SetFloat("_BumpScale", 1.6f);
            }
            m.SetTexture("_DetailNormalMap", s.CoreTex("dots_normal"));
            m.SetTextureScale("_DetailNormalMap", showNormal ? new Vector2(2.0f, 2.0f) : new Vector2(4.8f, 4.8f));
            m.SetFloat("_DetailNormalScale", 1.3f);
            m.SetFloat("_BlendMode", DetailModes[s.Panel]);
            m.SetFloat("_ShowNormal", showNormal ? 1 : 0);
            var q = s.Quad(m, new Vector3(0, 1.0f, 0));
            q.transform.localScale = new Vector3(1.4f, 1.4f, 1);
            s.SunDir(35, 62, 1.5f);
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.LookAt(new Vector3(0, 1.0f, -2.05f), new Vector3(0, 1.0f, 0), 30);
        }

        [BookShot("ch07-detail-blend", W = 480, H = 480, Panels = 4)]
        static void DetailBlend(Shot s) => DetailScene(s, false);

        [BookShot("ch07-detail-blend-ts", W = 480, H = 480, Panels = 4)]
        static void DetailBlendTS(Shot s) => DetailScene(s, true);

        // ---------------- 7.5 从高度图求法线 ----------------
        [BookShot("ch07-height2normal", W = 640, H = 480, Panels = 3)]
        static void HeightToNormal(Shot s)
        {
            var m = Bricks(s, "Cookbook/Ch07/HeightToNormal", 4.4f, 2.6f);
            m.SetFloat("_Mode", s.Panel);
            m.SetFloat("_HeightStrength", 6f);
            Wall(s, m);
            s.SunDir(28, 58, 1.5f);
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.LookAt(new Vector3(-0.3f, 1.2f, -0.55f), new Vector3(0.05f, 1.05f, 0.8f), 34);
        }

        // ---------------- 7.6 没有切线的网格 ----------------
        [BookShot("ch07-derivative-tbn", W = 640, H = 480, Panels = 3)]
        static void DerivativeTBN(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch07/DerivativeTBN");
            // 用圆点凸包做法线：光照方向一错，凸包会立刻变成“凹坑”或侧着亮，最容易看出 TBN 对不对
            m.SetColor("_BaseColor", new Color(0.62f, 0.66f, 0.7f));
            m.SetTexture("_BumpMap", s.CoreTex("dots_normal"));
            m.SetTextureScale("_BaseMap", new Vector2(1f, 2f));
            m.SetFloat("_BumpScale", 1.3f);
            bool derivative = s.Panel == 1;
            if (derivative) m.EnableKeyword("_DERIVATIVE_TBN"); else m.DisableKeyword("_DERIVATIVE_TBN");
            m.SetFloat("_UseDerivative", derivative ? 1 : 0);

            // 前两格：把球体网格复制一份并删掉切线；第三格：原始网格（有 MikkTSpace 切线）作参照
            // 圆环的 U 方向沿着环走，各处切线方向都不同，缺切线时最容易露馅
            var mesh = Meshes.Torus(0.75f, 0.32f);
            if (s.Panel < 2) mesh.tangents = new Vector4[0];
            var go = s.MeshObj(mesh, m, new Vector3(0, 0.75f, 0), 1f, "Torus");
            go.transform.rotation = Quaternion.Euler(-55, 0, 0);
            s.SunDir(40, 30, 1.5f);
            s.LookAt(new Vector3(0, 1.4f, -3.3f), new Vector3(0, 0.72f, 0), 35);
        }

        // ---------------- 7.7~7.9 视差 ----------------
        static Material ParallaxMat(Shot s, string mode, float scale = 0.06f, float minL = 8, float maxL = 32, bool shadow = true)
        {
            var m = Bricks(s, "Cookbook/Ch07/Parallax", 4.4f, 2.6f);
            foreach (var k in new[] { "_MODE_NONE", "_MODE_SIMPLE", "_MODE_STEEP", "_MODE_POM" }) m.DisableKeyword(k);
            m.EnableKeyword("_MODE_" + mode);
            m.SetFloat("_Mode", System.Array.IndexOf(new[] { "NONE", "SIMPLE", "STEEP", "POM" }, mode));
            m.SetFloat("_Parallax", scale);
            m.SetFloat("_MinLayers", minL);
            m.SetFloat("_MaxLayers", maxL);
            if (shadow) m.EnableKeyword("_PARALLAX_SHADOW"); else m.DisableKeyword("_PARALLAX_SHADOW");
            m.SetFloat("_SelfShadow", shadow ? 1 : 0);
            m.SetFloat("_BumpScale", 1.0f);
            return m;
        }

        static void ParallaxScene(Shot s, Material m, bool close = false)
        {
            s.Floor();
            Wall(s, m);
            s.SunDir(24, 62, 1.6f);
            if (close) s.LookAt(new Vector3(-1.05f, 1.15f, -0.45f), new Vector3(0.25f, 1.0f, 0.8f), 30);
            else s.LookAt(new Vector3(-1.4f, 1.2f, -0.8f), new Vector3(0.3f, 1.0f, 0.8f), 34);
        }

        [BookShot("ch07-parallax", W = 480, H = 480, Panels = 4)]
        static void ParallaxCompare(Shot s)
        {
            string[] modes = { "NONE", "SIMPLE", "STEEP", "POM" };
            ParallaxScene(s, ParallaxMat(s, modes[s.Panel], shadow: s.Panel == 3));
        }

        [BookShot("ch07-pom-layers", W = 640, H = 480, Panels = 3)]
        static void PomLayers(Shot s)
        {
            Material m = s.Panel == 0 ? ParallaxMat(s, "STEEP", 0.06f, 8, 8, false)
                       : s.Panel == 1 ? ParallaxMat(s, "POM", 0.06f, 8, 8, false)
                       : ParallaxMat(s, "POM", 0.06f, 16, 48, false);
            ParallaxScene(s, m, true);
        }

        [BookShot("ch07-pom-shadow", W = 640, H = 480, Panels = 2)]
        static void PomShadow(Shot s)
        {
            var m = ParallaxMat(s, "POM", 0.06f, 16, 48, s.Panel == 1);
            m.SetFloat("_ShadowSoftness", 30f);
            ParallaxScene(s, m, true);
            // 更低、更偏的光，正面一点的机位：能看清砖缝“底面”上的投影
            s.SunDir(16, 72, 1.8f);
            s.LookAt(new Vector3(-0.35f, 1.25f, -0.55f), new Vector3(0.2f, 1.1f, 0.8f), 32);
        }

        [BookShot("ch07-parallax-scale", W = 640, H = 480, Panels = 3)]
        static void ParallaxScale(Shot s)
        {
            float[] scales = { 0.02f, 0.06f, 0.12f };
            ParallaxScene(s, ParallaxMat(s, "POM", scales[s.Panel], 16, 48, true));
        }
    }
}
