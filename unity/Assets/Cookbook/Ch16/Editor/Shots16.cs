// 第 16 章配图
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;   // RenderObjects 在这个命名空间
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch16
{
    static class Shots16
    {
        // ---------------- 程序化贴图 ----------------
        static Texture2D MakeTex(int w, int h, System.Func<float, float, Color> f, bool mip = true, string name = "Tex")
        {
            var t = new Texture2D(w, h, TextureFormat.RGBA32, mip, false)
            { name = name, wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4, hideFlags = HideFlags.DontSave };
            var px = new Color[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    px[y * w + x] = f((x + 0.5f) / w, (y + 0.5f) / h);
            t.SetPixels(px); t.Apply(mip);
            return t;
        }

        // 白色圆盘，边缘有一点柔和过渡
        static Texture2D Disc() => MakeTex(128, 128, (u, v) =>
        {
            float r = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f;
            return new Color(1, 1, 1, Mathf.Clamp01((1f - r) / 0.12f));
        }, false, "Disc");

        // 预乘版圆盘：rgb = alpha
        static Texture2D DiscPremul() => MakeTex(128, 128, (u, v) =>
        {
            float r = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f;
            float a = Mathf.Clamp01((1f - r) / 0.12f) ;
            return new Color(a, a, a, a);
        }, false, "DiscPremul");

        // 预乘版“圆盘 + 外圈辉光”：辉光部分 rgb > 0 但 alpha = 0，混合时纯叠加
        static Texture2D DiscGlowPremul() => MakeTex(128, 128, (u, v) =>
        {
            float r = Mathf.Sqrt((u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f)) * 2f;
            float a = Mathf.Clamp01((1f - r * 1.6f) / 0.08f);            // 实心部分小一圈
            float glow = Mathf.Pow(Mathf.Clamp01(1f - r), 1.3f);
            float c = Mathf.Max(a, glow);
            return new Color(c, c, c, a);
        }, false, "DiscGlowPremul");

        // 背景板：上部是黑→白渐变，下部是色相条
        static Texture2D Backdrop() => MakeTex(256, 128, (u, v) =>
        {
            if (v > 0.38f) { float g = Mathf.Pow(u, 2.2f); return new Color(g, g, g, 1); }
            var c = Color.HSVToRGB(u, 0.75f, 0.9f); return c;
        }, false, "Backdrop");

        // 铁丝网：两组对角细线
        static Texture2D Fence() => MakeTex(256, 256, (u, v) =>
        {
            float a = Mathf.Abs(Mathf.Repeat(u * 4 + v * 4, 1f) - 0.5f);
            float b = Mathf.Abs(Mathf.Repeat(u * 4 - v * 4, 1f) - 0.5f);
            float d = Mathf.Min(0.5f - a, 0.5f - b);             // 到最近细线的距离（以格子为单位）
            float alpha = Mathf.Clamp01((0.06f - d) / 0.02f + 0.5f);
            float shade = 0.55f + 0.35f * Mathf.Clamp01(1f - d / 0.06f);
            return new Color(shade, shade * 0.97f, shade * 0.92f, alpha);
        }, true, "Fence");

        // ---------------- Blend ----------------
        struct BlendCfg { public string name; public BlendMode src, dst; public BlendOp op; public string output; }

        static void BlendScene(Shot s, BlendCfg c, Texture2D disc)
        {
            s.Background(Color.black);
            s.Cam.orthographic = true; s.Cam.orthographicSize = 1.3f;
            s.Cam.transform.SetPositionAndRotation(new Vector3(0, 0, -5), Quaternion.identity);
            var bg = s.Mat("Universal Render Pipeline/Unlit");
            bg.SetTexture("_BaseMap", Backdrop());
            var q = s.Quad(bg, new Vector3(0, 0, 1));
            q.transform.localScale = new Vector3(4.2f, 2.7f, 1);

            Color[] cols = { new Color(1f, 0.25f, 0.2f, 0.7f), new Color(0.25f, 1f, 0.3f, 0.7f), new Color(0.25f, 0.4f, 1f, 0.7f) };
            Vector3[] pos = { new Vector3(-0.38f, 0.32f, 0), new Vector3(0.38f, 0.32f, -0.01f), new Vector3(0, -0.3f, -0.02f) };
            for (int i = 0; i < 3; i++)
            {
                var m = s.Mat("Cookbook/Ch16/BlendModes");
                m.SetTexture("_BaseMap", disc);
                m.SetColor("_BaseColor", cols[i]);
                m.SetFloat("_SrcBlend", (float)c.src); m.SetFloat("_DstBlend", (float)c.dst); m.SetFloat("_BlendOp", (float)c.op);
                foreach (var k in new[] { "_OUTPUT_STRAIGHT", "_OUTPUT_PREMULTIPLY", "_OUTPUT_MULTIPLYREADY" }) m.DisableKeyword(k);
                m.EnableKeyword(c.output);
                s.Quad(m, pos[i], 1.25f);
            }
        }

        [BookShot("ch16-blend-a", W = 640, H = 420, Panels = 3)]
        static void BlendA(Shot s)
        {
            var cfg = new[] {
                new BlendCfg { src = BlendMode.SrcAlpha, dst = BlendMode.OneMinusSrcAlpha, op = BlendOp.Add, output = "_OUTPUT_STRAIGHT" },
                new BlendCfg { src = BlendMode.One, dst = BlendMode.OneMinusSrcAlpha, op = BlendOp.Add, output = "_OUTPUT_PREMULTIPLY" },
                new BlendCfg { src = BlendMode.SrcAlpha, dst = BlendMode.One, op = BlendOp.Add, output = "_OUTPUT_STRAIGHT" } };
            BlendScene(s, cfg[s.Panel], s.Panel == 1 ? DiscGlowPremul() : Disc());
        }

        [BookShot("ch16-blend-b", W = 640, H = 420, Panels = 3)]
        static void BlendB(Shot s)
        {
            var cfg = new[] {
                new BlendCfg { src = BlendMode.OneMinusDstColor, dst = BlendMode.One, op = BlendOp.Add, output = "_OUTPUT_PREMULTIPLY" },
                new BlendCfg { src = BlendMode.DstColor, dst = BlendMode.Zero, op = BlendOp.Add, output = "_OUTPUT_MULTIPLYREADY" },
                new BlendCfg { src = BlendMode.One, dst = BlendMode.One, op = BlendOp.Max, output = "_OUTPUT_PREMULTIPLY" } };
            BlendScene(s, cfg[s.Panel], s.Panel == 1 ? Disc() : DiscPremul());
        }

        // ---------------- ZTest / ZWrite / Cull ----------------
        [BookShot("ch16-zstates", W = 480, H = 400, Panels = 4)]
        static void ZStates(Shot s)
        {
            s.Floor();
            var wall = s.Cube(s.Lit(new Color(0.55f, 0.6f, 0.68f), 0, 0.2f), new Vector3(-0.35f, 0.75f, -0.6f));
            wall.transform.localScale = new Vector3(1.3f, 1.5f, 0.12f);
            var m = s.Mat("Cookbook/Ch16/RenderStates");
            m.renderQueue = 2010;   // 在墙之后绘制，ZTest Always/Greater 才有意义
            CompareFunction[] zt = { CompareFunction.LessEqual, CompareFunction.Always, CompareFunction.Greater, CompareFunction.LessEqual };
            m.SetFloat("_ZTest", (float)zt[s.Panel]);
            m.SetFloat("_Cull", s.Panel == 3 ? (float)CullMode.Front : (float)CullMode.Back);
            s.Knot(m, new Vector3(0.1f, 0.95f, 0.5f), 1.0f);
            s.LookAt(new Vector3(0, 1.6f, -4.4f), new Vector3(0, 0.8f, 0), 36);
            s.SunDir(45, -30, 1.2f);
        }

        // ---------------- 排序 ----------------
        [BookShot("ch16-sorting", W = 640, H = 480, Panels = 3)]
        static void Sorting(Shot s)
        {
            s.Floor();
            s.Cube(s.Lit(new Color(0.9f, 0.75f, 0.3f), 0, 0.4f), new Vector3(1.0f, 0.6f, 2.6f), 1.2f).transform.rotation = Quaternion.Euler(0, 30, 0);
            Material m;
            if (s.Panel < 2)
            {
                m = s.Mat("Cookbook/Ch16/TransparentLit");
                m.SetFloat("_ZWrite", s.Panel);
            }
            else m = s.Mat("Cookbook/Ch16/TransparentPrepass");
            m.SetColor("_BaseColor", new Color(0.2f, 0.6f, 1f, 0.55f));
            s.Knot(m, new Vector3(-0.2f, 1.0f, 0), 1.1f);
            s.LookAt(new Vector3(0, 1.6f, -3.6f), new Vector3(0, 0.95f, 0.3f), 40);
            s.SunDir(50, -30, 1.2f);
        }

        // ---------------- Alpha Clip / A2C ----------------
        [BookShot("ch16-cutout", W = 640, H = 420, Panels = 3)]
        static void Cutout(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch16/Cutout");
            m.SetTexture("_BaseMap", Fence());
            m.SetTextureScale("_BaseMap", new Vector2(6, 2));
            m.SetFloat("_AlphaToMask", s.Panel >= 1 ? 1 : 0);
            m.SetFloat("_Sharpen", s.Panel == 2 ? 1 : 0);
            m.SetFloat("_MipScale", s.Panel == 2 ? 1 : 0);
            var q = s.Quad(m, new Vector3(0.6f, 1.0f, 3f));
            q.transform.localScale = new Vector3(12f, 2f, 1f);
            q.transform.rotation = Quaternion.Euler(0, 62, 0);
            s.Sphere(s.Lit(new Color(0.85f, 0.3f, 0.25f), 0, 0.5f), new Vector3(1.6f, 0.45f, 3.4f), 0.9f);
            s.LookAt(new Vector3(-0.6f, 1.2f, -1.6f), new Vector3(0.9f, 0.9f, 2.5f), 40);
            s.SunDir(40, -60, 1.3f);
            MsaaView.Use(s, 640, 420, 4, 3);    // 以 1/3 分辨率渲染后放大，锯齿看得更清楚
        }

        // ---------------- 抖动透明 ----------------
        [BookShot("ch16-dither", W = 960, H = 400)]
        static void Dither(Shot s)
        {
            s.Floor();
            float[] fade = { 1f, 0.75f, 0.5f, 0.25f };
            for (int i = 0; i < 4; i++)
            {
                var m = s.Mat("Cookbook/Ch16/DitherFade");
                m.SetFloat("_Fade", fade[i]);
                s.Capsule(m, new Vector3(-1.95f + i * 1.3f, 1.0f, 0), 1f);
            }
            s.LookAt(new Vector3(0, 1.5f, -4.6f), new Vector3(0, 0.8f, 0.4f), 34);
            s.SunDir(40, -20, 1.3f);
        }

        // ---------------- 双面 ----------------
        // 开口的半球“碗”：只有一层面，法线朝外
        static Mesh Bowl(int rings = 16, int segs = 48)
        {
            var v = new System.Collections.Generic.List<Vector3>();
            var n = new System.Collections.Generic.List<Vector3>();
            var idx = new System.Collections.Generic.List<int>();
            for (int r = 0; r <= rings; r++)
            {
                float phi = Mathf.PI * 0.5f * r / rings;            // 0 = 底部，π/2 = 碗口
                for (int sg = 0; sg <= segs; sg++)
                {
                    float th = Mathf.PI * 2f * sg / segs;
                    var d = new Vector3(Mathf.Sin(phi) * Mathf.Cos(th), -Mathf.Cos(phi), Mathf.Sin(phi) * Mathf.Sin(th));
                    v.Add(d * 0.5f); n.Add(d);
                }
            }
            for (int r = 0; r < rings; r++)
                for (int sg = 0; sg < segs; sg++)
                {
                    int a = r * (segs + 1) + sg, b = a + segs + 1;
                    idx.AddRange(new[] { a, b, a + 1, b, b + 1, a + 1 });
                }
            var m = new Mesh { name = "Bowl" };
            m.SetVertices(v); m.SetNormals(n); m.SetTriangles(idx, 0); m.RecalculateBounds();
            return m;
        }

        [BookShot("ch16-twosided", W = 640, H = 480, Panels = 3)]
        static void TwoSided(Shot s)
        {
            s.Floor();
            var m = s.Mat("Cookbook/Ch16/TwoSided");
            m.SetFloat("_Cull", s.Panel == 0 ? (float)CullMode.Back : (float)CullMode.Off);
            m.SetFloat("_FlipBackNormal", s.Panel == 2 ? 1 : 0);
            if (s.Panel == 1) m.SetColor("_BackColor", m.GetColor("_BaseColor"));   // 中图只看光照对不对，背面不换色
            var bowl = s.MeshObj(Bowl(), m, new Vector3(-0.55f, 0.75f, 0.2f), 1.6f, "Bowl");
            bowl.transform.rotation = Quaternion.Euler(-25, 0, 10);
            var sheet = s.MeshObj(Meshes.Grid(1.2f, 24), m, new Vector3(1.2f, 0.75f, 0.3f), 1f, "Sheet");
            sheet.transform.rotation = Quaternion.Euler(65, -35, 0);   // 法线背向相机：我们看到的是它的背面
            s.LookAt(new Vector3(0, 2.2f, -4.0f), new Vector3(0.3f, 0.6f, 0.2f), 36);
            s.SunDir(50, -40, 1.3f);
        }

        // ---------------- X 光（模板） ----------------
        [BookShot("ch16-xray", W = 640, H = 480, Panels = 2)]
        static void XRay(Shot s)
        {
            s.Floor();
            var wall = s.Cube(s.Lit(new Color(0.6f, 0.62f, 0.66f), 0, 0.2f), new Vector3(-0.55f, 0.9f, -0.5f));
            wall.transform.localScale = new Vector3(1.3f, 1.8f, 0.15f);

            //#region xray-setup
            // 角色：第一个材质正常着色并写模板 1；第二个材质是 X 光剪影（Transparent 队列，ZTest Greater）
            var body = s.Mat("Cookbook/Ch16/StencilLit");
            body.SetColor("_BaseColor", new Color(0.9f, 0.45f, 0.2f));
            body.SetFloat("_StencilRef", 1);
            body.SetFloat("_StencilComp", (float)CompareFunction.Always);
            body.SetFloat("_StencilPass", (float)StencilOp.Replace);
            var xray = s.Mat("Cookbook/Ch16/XRaySilhouette");
            // 左图：不做模板测试（Always）；右图：只在模板 ≠ 1（不是角色自身可见部分）处绘制
            xray.SetFloat("_StencilComp", s.Panel == 0 ? (float)CompareFunction.Always : (float)CompareFunction.NotEqual);
            var knot = s.Knot(body, new Vector3(0.05f, 1.0f, 0.6f), 1.15f);
            knot.GetComponent<MeshRenderer>().sharedMaterials = new[] { body, xray };   // 多出的材质会把网格再画一遍
            //#endregion

            s.LookAt(new Vector3(0, 1.6f, -4.4f), new Vector3(0, 0.9f, 0), 36);
            s.SunDir(45, -30, 1.2f);
        }

        // ---------------- 传送门（模板） ----------------
        [BookShot("ch16-portal", W = 640, H = 480, Panels = 2)]
        static void Portal(Shot s)
        {
            Material Inner(Color c, bool unlit = false)
            {
                var m = s.Mat("Cookbook/Ch16/StencilLit");
                m.SetColor("_BaseColor", c);
                m.SetFloat("_StencilRef", 1);
                m.SetFloat("_StencilComp", (float)CompareFunction.Equal);    // 只在门内可见
                m.SetFloat("_Unlit", unlit ? 1 : 0);
                return m;
            }
            // 外面的地面：模板 ≠ 1 才画，否则会挡住门里的世界
            var outerFloor = s.Mat("Cookbook/Ch16/StencilLit");
            outerFloor.SetTexture("_BaseMap", s.CoreTex("checker"));
            outerFloor.SetTextureScale("_BaseMap", new Vector2(7.5f, 7.5f));
            outerFloor.SetColor("_BaseColor", new Color(0.75f, 0.75f, 0.75f));
            outerFloor.SetFloat("_StencilComp", (float)CompareFunction.NotEqual);
            s.Floor(outerFloor);

            // 门框 + 遮罩
            var frame = s.Lit(new Color(0.35f, 0.3f, 0.28f), 0, 0.3f);
            void Box(Vector3 p, Vector3 sc) { var c = s.Cube(frame, p); c.transform.localScale = sc; }
            Box(new Vector3(-0.85f, 1.1f, 0), new Vector3(0.2f, 2.2f, 0.3f));
            Box(new Vector3(0.85f, 1.1f, 0), new Vector3(0.2f, 2.2f, 0.3f));
            Box(new Vector3(0, 2.3f, 0), new Vector3(1.9f, 0.2f, 0.3f));
            var mask = s.Quad(s.Mat("Cookbook/Ch16/StencilMask"), new Vector3(0, 1.1f, 0));
            mask.transform.localScale = new Vector3(1.5f, 2.2f, 1);

            // 门里的世界：紫色天幕、发光的地面和几个物体，全部 Stencil Equal 1，且不投射阴影
            var sky = s.Sphere(Inner(new Color(0.25f, 0.12f, 0.4f), true), new Vector3(0, 0, 6), 22f);
            sky.GetComponent<MeshRenderer>().sharedMaterial.SetFloat("_Cull", (float)CullMode.Front);
            var floorIn = s.Quad(Inner(new Color(0.2f, 0.5f, 0.45f)), new Vector3(0, 0.005f, 6), 20f);
            floorIn.transform.rotation = Quaternion.Euler(90, 0, 0);
            var objs = new[] {
                s.Sphere(Inner(new Color(1f, 0.6f, 0.2f)), new Vector3(-0.6f, 0.6f, 2.5f), 1.2f),
                s.Knot(Inner(new Color(0.4f, 0.8f, 1f)), new Vector3(0.9f, 1.1f, 4f), 1.2f),
                s.Cube(Inner(new Color(0.95f, 0.85f, 0.3f)), new Vector3(-1.6f, 0.5f, 5f), 1.0f),
                s.Cylinder(Inner(new Color(0.9f, 0.4f, 0.6f)), new Vector3(2.4f, 1f, 6.5f), 0.8f) };
            foreach (var go in new[] { sky, floorIn }) go.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
            foreach (var go in objs) go.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;

            // 门外的陪衬
            s.Sphere(s.Lit(new Color(0.3f, 0.5f, 0.85f), 0, 0.5f), new Vector3(-2.0f, 0.45f, -0.6f), 0.9f);
            s.Cube(s.Lit(new Color(0.85f, 0.35f, 0.3f), 0, 0.3f), new Vector3(1.9f, 0.35f, -0.9f), 0.7f).transform.rotation = Quaternion.Euler(0, 25, 0);

            if (s.Panel == 0) s.LookAt(new Vector3(0, 1.6f, -5.2f), new Vector3(0, 1.0f, 0), 40);
            else s.LookAt(new Vector3(-2.4f, 1.8f, -4.4f), new Vector3(0.2f, 1.0f, 0.5f), 40);
            s.SunDir(45, -30, 1.2f);
        }

        // ---------------- RenderObjects：被遮挡部分显示轮廓色 ----------------
        const int CharacterLayer = 8;

        static void Character(Shot s, Material m)
        {
            var root = new GameObject("Character");
            root.transform.position = new Vector3(0.2f, 0, 0.8f);
            GameObject Part(GameObject go, Vector3 p, Vector3 sc, Vector3 rot)
            {
                go.transform.SetParent(root.transform, false);
                go.transform.localPosition = p; go.transform.localScale = sc; go.transform.localEulerAngles = rot;
                go.layer = CharacterLayer;
                return go;
            }
            Part(s.Capsule(m, Vector3.zero), new Vector3(0, 1.0f, 0), new Vector3(0.55f, 0.5f, 0.4f), Vector3.zero);       // 躯干
            Part(s.Sphere(m, Vector3.zero), new Vector3(0, 1.75f, 0), Vector3.one * 0.42f, Vector3.zero);                   // 头
            Part(s.Capsule(m, Vector3.zero), new Vector3(-0.42f, 1.05f, -0.2f), new Vector3(0.16f, 0.38f, 0.16f), new Vector3(-50, 0, -15)); // 手臂（伸向前方）
            Part(s.Capsule(m, Vector3.zero), new Vector3(0.12f, 1.1f, -0.32f), new Vector3(0.16f, 0.4f, 0.16f), new Vector3(-75, 0, 55));  // 横在胸前
            Part(s.Capsule(m, Vector3.zero), new Vector3(-0.15f, 0.35f, 0), new Vector3(0.2f, 0.4f, 0.2f), Vector3.zero);    // 腿
            Part(s.Capsule(m, Vector3.zero), new Vector3(0.15f, 0.35f, 0), new Vector3(0.2f, 0.4f, 0.2f), Vector3.zero);
        }

        [BookShot("ch16-renderobjects", W = 640, H = 480, Panels = 3)]
        static void RenderObjectsShot(Shot s)
        {
            s.Floor();
            var wall = s.Cube(s.Lit(new Color(0.6f, 0.62f, 0.66f), 0, 0.2f), new Vector3(-0.45f, 1.0f, -0.2f));
            wall.transform.localScale = new Vector3(1.2f, 2.0f, 0.15f);
            Character(s, s.Lit(new Color(0.9f, 0.5f, 0.25f), 0, 0.4f));
            s.LookAt(new Vector3(0.3f, 1.7f, -4.0f), new Vector3(0, 1.0f, 0.3f), 38);
            s.SunDir(45, -30, 1.2f);
            if (s.Panel == 0) return;

            var silhouette = s.Mat("Cookbook/Ch16/XRaySilhouette");

            //#region ro-setup
            // 1) 默认的不透明 Pass 不再画角色层，交给下面两个 Feature
            s.Renderer.opaqueLayerMask = ~(1 << CharacterLayer);

            // 2) 第一个 Feature：正常画角色，同时把模板写成 1（标记“角色可见的像素”）
            var visible = s.Feature<RenderObjects>();
            visible.settings.passTag = "Character Visible";
            visible.settings.Event = RenderPassEvent.AfterRenderingOpaques;
            visible.settings.filterSettings.RenderQueueType = RenderQueueType.Opaque;
            visible.settings.filterSettings.LayerMask = 1 << CharacterLayer;
            visible.settings.overrideMode = RenderObjects.RenderObjectsSettings.OverrideMaterialMode.None;
            visible.settings.stencilSettings.overrideStencilState = s.Panel == 2;
            visible.settings.stencilSettings.stencilReference = 1;
            visible.settings.stencilSettings.stencilCompareFunction = CompareFunction.Always;
            visible.settings.stencilSettings.passOperation = StencilOp.Replace;

            // 3) 第二个 Feature：用剪影材质再画一遍，深度测试改成 Greater、不写深度，
            //    并且只在模板 ≠ 1 的地方画（排除角色自己挡住自己的情况）
            var occluded = s.Feature<RenderObjects>();
            occluded.settings.passTag = "Character Occluded";
            occluded.settings.Event = RenderPassEvent.AfterRenderingOpaques;
            occluded.settings.filterSettings.RenderQueueType = RenderQueueType.Opaque;
            occluded.settings.filterSettings.LayerMask = 1 << CharacterLayer;
            occluded.settings.overrideMode = RenderObjects.RenderObjectsSettings.OverrideMaterialMode.Material;
            occluded.settings.overrideMaterial = silhouette;
            occluded.settings.overrideMaterialPassIndex = 0;
            occluded.settings.overrideDepthState = true;
            occluded.settings.depthCompareFunction = CompareFunction.Greater;
            occluded.settings.enableWrite = false;
            occluded.settings.stencilSettings.overrideStencilState = s.Panel == 2;
            occluded.settings.stencilSettings.stencilReference = 1;
            occluded.settings.stencilSettings.stencilCompareFunction = CompareFunction.NotEqual;
            occluded.settings.stencilSettings.passOperation = StencilOp.Keep;

            // 4) Feature 在 OnEnable 时就用默认设置 Create 过一次，改完设置要再 Create 一次
            visible.Create();
            occluded.Create();
            //#endregion
            if (s.Panel == 1) silhouette.SetFloat("_StencilComp", (float)CompareFunction.Always);
        }
    }
}
