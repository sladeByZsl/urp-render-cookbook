// 第 2 章配图：渲染路径、Pass 顺序、场景纹理、相机栈、LightMode、URP Asset 设置
using System.Reflection;
using Cookbook.Core;
using UnityEditor;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch02
{
    static class Ch02Shots
    {
        // ---------- 小工具 ----------
        static Material TransparentLit(Shot s, Color c, float smoothness = 0.9f)
        {
            // URP Lit 切成透明模式需要同时改属性、关键字、渲染队列（材质 Inspector 平时替你做了这些）
            var m = s.Lit(c, 0, smoothness);
            m.SetFloat("_Surface", 1);
            m.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_SrcBlendAlpha", (float)BlendMode.One);
            m.SetFloat("_DstBlendAlpha", (float)BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_ZWrite", 0);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.SetOverrideTag("RenderType", "Transparent");
            m.renderQueue = (int)RenderQueue.Transparent;
            return m;
        }

        // c 按线性空间的值给出。_EmissionColor 是 [HDR] 属性，线性工程里 Unity 原样上传、不做 sRGB 换算（用 SetColor 也一样）
        static Material Emissive(Shot s, Color c, float intensity)
        {
            var m = s.Lit(c * 0.2f, 0, 0.5f);
            m.EnableKeyword("_EMISSION");
            m.SetVector("_EmissionColor", (Vector4)(c * intensity));
            m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
            return m;
        }

        // 把环境光、环境反射压暗，让点光源成为主角
        static void DimEnvironment(float k)
        {
            var sh = RenderSettings.ambientProbe;
            sh *= k;
            RenderSettings.ambientProbe = sh;
            RenderSettings.reflectionIntensity = k;
        }

        static Color Hue(int i, int n) => Color.HSVToRGB((i * 0.618f) % 1f, 0.75f, 1f);

        // 24 盏彩色点光源 + 一组小球，铺在一块地面上
        static void ManyLightsScene(Shot s, bool tiledFloor)
        {
            var floorMat = s.Lit(new Color(0.8f, 0.8f, 0.8f), 0, 0.35f);
            if (tiledFloor)
            {
                // 把地面拆成 12×12 块，每块是独立的 Renderer
                const int n = 12; const float size = 16f; float cell = size / n;
                for (int x = 0; x < n; x++)
                    for (int z = 0; z < n; z++)
                    {
                        var p = s.Prim(PrimitiveType.Plane, floorMat, new Vector3(-size / 2 + cell * (x + 0.5f), 0, -size / 2 + 2.5f + cell * (z + 0.5f)));
                        p.transform.localScale = new Vector3(cell / 10f, 1, cell / 10f);
                    }
            }
            else
            {
                var p = s.Prim(PrimitiveType.Plane, floorMat, new Vector3(0, 0, 2.5f));
                p.transform.localScale = new Vector3(1.6f, 1, 1.6f);   // 一整块 16m × 16m 的地面，一个 Renderer
            }

            var ball = s.Lit(new Color(0.85f, 0.85f, 0.85f), 0, 0.6f);
            for (int x = 0; x < 5; x++)
                for (int z = 0; z < 3; z++)
                    s.Sphere(ball, new Vector3(-4.4f + x * 2.2f, 0.45f, 0.2f + z * 2.6f), 0.9f);

            int k = 0;
            for (int x = 0; x < 6; x++)
                for (int z = 0; z < 4; z++, k++)
                    s.Point(new Vector3(-5.5f + x * 2.2f, 0.35f, -1.1f + z * 2.6f), Hue(k, 24), 2.2f, 2.4f);

            s.SunDir(50, -30, 0.08f);
            DimEnvironment(0.12f);
            s.Background(new Color(0.03f, 0.035f, 0.045f));
            s.LookAt(new Vector3(0, 6.2f, -7.2f), new Vector3(0, 0, 2.4f), 45);
        }

        // ---------- 案例 2.3：三种渲染路径 ----------
        //#region paths
        [BookShot("ch02-paths", W = 640, H = 420, Panels = 3)]
        static void Paths(Shot s)
        {
            RenderingMode[] modes = { RenderingMode.Forward, RenderingMode.ForwardPlus, RenderingMode.Deferred };
            s.Renderer.renderingMode = modes[s.Panel];     // 相当于在 Universal Renderer Data 上切换 Rendering Path
            s.Asset.maxAdditionalLightsCount = 4;          // URP Asset 默认的“每物体附加光上限”
            ManyLightsScene(s, false);                     // 24 盏彩色点光 + 15 个球 + 一整块地面
        }
        //#endregion

        // ---------- 案例 2.4：Forward 的每物体光源上限 ----------
        [BookShot("ch02-perobject", W = 640, H = 420, Panels = 3)]
        static void PerObject(Shot s)
        {
            s.Renderer.renderingMode = RenderingMode.Forward;
            s.Asset.maxAdditionalLightsCount = s.Panel == 1 ? 8 : 4;
            ManyLightsScene(s, s.Panel == 2);
        }

        // ---------- 案例 2.1：一帧的成长过程 ----------
        [BookShot("ch02-frame-steps", W = 480, H = 320, Panels = 4, Hdr = true)]
        static void FrameSteps(Shot s)
        {
            RenderPassEvent[] events = { RenderPassEvent.AfterRenderingOpaques, RenderPassEvent.AfterRenderingSkybox, RenderPassEvent.AfterRenderingTransparents };
            if (s.Panel < 3)
            {
                var f = s.Feature<FrameSnapshotFeature>();
                f.captureEvent = events[s.Panel];
            }
            s.Floor();
            s.Cube(s.Lit(new Color(0.75f, 0.3f, 0.2f)), new Vector3(-1.5f, 0.5f, 0.6f)).transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Knot(s.Lit(new Color(0.9f, 0.9f, 0.92f), 1f, 0.75f), new Vector3(0.1f, 0.85f, 0.9f), 0.8f);
            s.Sphere(Emissive(s, new Color(1f, 0.3f, 0.05f), 4f), new Vector3(1.55f, 0.35f, 0.2f), 0.7f);
            s.Sphere(TransparentLit(s, new Color(0.3f, 0.7f, 1f, 0.35f)), new Vector3(-0.5f, 0.45f, -0.6f), 0.9f);
            s.Cube(TransparentLit(s, new Color(0.4f, 1f, 0.5f, 0.3f)), new Vector3(1.0f, 0.4f, -0.9f), 0.8f).transform.rotation = Quaternion.Euler(0, -20, 0);

            var prof = s.Post();
            var bloom = prof.Add<Bloom>(); bloom.intensity.Override(1.2f); bloom.threshold.Override(1f); bloom.scatter.Override(0.7f);
            var tm = prof.Add<Tonemapping>(); tm.mode.Override(TonemappingMode.ACES);
            var vig = prof.Add<Vignette>(); vig.intensity.Override(0.35f);
            s.LookAt(new Vector3(0.2f, 1.6f, -4.4f), new Vector3(0, 0.45f, 0.3f), 40);
        }

        // ---------- 案例 2.2：Depth Texture / Opaque Texture ----------
        [BookShot("ch02-scene-textures", W = 640, H = 420, Panels = 3)]
        static void SceneTextures(Shot s)
        {
            s.Renderer.copyDepthMode = CopyDepthMode.AfterOpaques;   // 透明物体要读当前帧的深度
            if (s.Panel == 1) s.Asset.supportsCameraDepthTexture = false;
            if (s.Panel == 2)
            {
                s.Asset.supportsCameraOpaqueTexture = false;
                // 关掉以后这一帧不会写 _CameraOpaqueTexture，Shader 读到什么取决于之前谁设置过它。
                // 为了让配图结果确定，这里显式放一张灰色占位图。
                Shader.SetGlobalTexture("_CameraOpaqueTexture", Texture2D.grayTexture);
            }

            s.Floor(null, 60f, -0.6f);                                 // 水底，水面在 y = 0.25，水深约 0.85 米
            var sand = s.Lit(new Color(0.85f, 0.75f, 0.55f), 0, 0.2f);
            var beach = s.Cube(sand, new Vector3(-3.6f, -0.3f, 2f));      // 一个斜坡当岸：左高右低，与水面相交出一条岸线
            beach.transform.localScale = new Vector3(6f, 1f, 12f);
            beach.transform.rotation = Quaternion.Euler(0, 0, -12);
            var rock = s.Lit(new Color(0.55f, 0.5f, 0.48f), 0, 0.3f);
            s.Sphere(rock, new Vector3(0.9f, 0.1f, 0.8f), 1.1f);
            s.Sphere(rock, new Vector3(2.4f, -0.1f, 2.6f), 1.4f);
            var post = s.Cylinder(s.Lit(new Color(0.6f, 0.35f, 0.2f)), new Vector3(1.9f, 0.3f, -0.4f));
            post.transform.localScale = new Vector3(0.22f, 1.0f, 0.22f);
            var tiles = s.Lit(Color.white, 0, 0.1f);
            tiles.SetTexture("_BaseMap", s.CoreTex("uv_grid"));
            var sub = s.Cube(tiles, new Vector3(-0.3f, -0.35f, 1.0f), 1f);  // 沉在水下的方块，用来看折射和深浅
            sub.transform.localScale = new Vector3(1.6f, 0.5f, 1.2f);
            sub.transform.rotation = Quaternion.Euler(0, 20, 0);

            var water = s.Mat("Cookbook/Ch02/SceneTextures");
            water.SetFloat("_DepthFade", 1.6f);
            s.MeshObj(Meshes.Grid(16f, 8), water, new Vector3(0, 0.25f, 3f), 1f, "Water");
            s.LookAt(new Vector3(0.3f, 2.8f, -3.6f), new Vector3(0.1f, 0f, 1.6f), 52);
        }

        // ---------- 案例 2.5：LightMode 与 Pass ----------
        [BookShot("ch02-lightmode", W = 640, H = 420, Panels = 3)]
        static void LightMode(Shot s)
        {
            LogSrpBatcherCompatibility();

            var m = s.Mat("Cookbook/Ch02/LightModeDemo");
            // 面板 0：关掉没有 LightMode 的那个 Pass（它的 LightMode 被视为 SRPDefaultUnlit）
            m.SetShaderPassEnabled("SRPDefaultUnlit", s.Panel >= 1);
            if (s.Panel == 2)
            {
                // URP 自带的 RenderObjects：在不透明物体之后，点名绘制 LightMode = CookbookXRay 的 Pass
                var f = s.Feature<RenderObjects>();
                f.settings.Event = RenderPassEvent.AfterRenderingOpaques;
                f.settings.filterSettings.RenderQueueType = RenderQueueType.Opaque;
                f.settings.filterSettings.LayerMask = ~0;
                f.settings.filterSettings.PassNames = new[] { "CookbookXRay" };
                f.settings.overrideMode = RenderObjects.RenderObjectsSettings.OverrideMaterialMode.None;
            }
            s.Floor();
            s.Knot(m, new Vector3(0.3f, 0.95f, 0.9f), 0.85f).transform.rotation = Quaternion.Euler(10, 30, 0);
            s.Capsule(m, new Vector3(-1.6f, 0.75f, 1.2f), 0.75f);
            var wall = s.Cube(s.Lit(new Color(0.55f, 0.6f, 0.65f)), new Vector3(-0.4f, 0.7f, -0.2f));
            wall.transform.localScale = new Vector3(2.0f, 1.4f, 0.15f);
            s.LookAt(new Vector3(0.1f, 1.7f, -4.4f), new Vector3(-0.2f, 0.7f, 0.6f), 42);
        }

        // 在日志里打印本章两个演示 Shader 的 SRP Batcher 兼容性（用的是 Shader Inspector 背后的内部接口）
        static void LogSrpBatcherCompatibility()
        {
            var t = typeof(ShaderUtil);
            var getCode = t.GetMethod("GetSRPBatcherCompatibilityCode", BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public);
            var getReason = t.GetMethod("GetSRPBatcherCompatibilityIssueReason", BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public);
            if (getCode == null || getReason == null) { Debug.Log("[Ch02] SRP Batcher API not found"); return; }
            foreach (var name in new[] { "Cookbook/Ch02/SrpBatcherCompatible", "Cookbook/Ch02/SrpBatcherBroken", "Cookbook/Ch02/LightModeDemo" })
            {
                var sh = Shader.Find(name);
                int code = (int)getCode.Invoke(null, new object[] { sh, 0 });
                string reason = (string)getReason.Invoke(null, new object[] { sh, 0, code });
                Debug.Log($"[Ch02] SRPBatcher {name}: code={code} reason={reason}");
            }
        }

        // ---------- 案例 2.7：相机栈 ----------
        [BookShot("ch02-camera-stack", W = 640, H = 420, Panels = 3)]
        static void CameraStack(Shot s)
        {
            const int overlayLayer = 20;
            s.Floor();
            s.Cube(s.Lit(new Color(0.75f, 0.3f, 0.2f)), new Vector3(-1.5f, 0.5f, 1.5f)).transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Sphere(s.Lit(new Color(0.3f, 0.5f, 0.85f), 0, 0.7f), new Vector3(1.2f, 0.6f, 2.0f), 1.2f);
            // 一根离相机很近的柱子：没有清深度时，它会挡住叠加相机里的物体
            var pillar = s.Cube(s.Lit(new Color(0.85f, 0.8f, 0.7f)), new Vector3(0.75f, 1.0f, -3.0f));
            pillar.transform.localScale = new Vector3(0.25f, 2.0f, 0.25f);
            s.LookAt(new Vector3(0.2f, 1.4f, -4.2f), new Vector3(0, 0.75f, 0.6f), 45);

            //#region stack
            s.Cam.cullingMask = ~(1 << overlayLayer);          // Base 相机不画“手持物”层
            if (s.Panel == 0) return;

            // 叠加相机：只画手持物这一层，挂到 Base 相机的 Stack 里
            var go = new GameObject("Overlay Camera");
            go.transform.SetPositionAndRotation(s.Cam.transform.position, s.Cam.transform.rotation);
            var cam = go.AddComponent<Camera>();
            cam.fieldOfView = s.Cam.fieldOfView;
            cam.nearClipPlane = 0.05f;
            cam.aspect = 640f / 420f;
            cam.cullingMask = 1 << overlayLayer;
            var data = go.AddComponent<UniversalAdditionalCameraData>();
            data.renderType = CameraRenderType.Overlay;
            // clearDepth 在 URP 14 里只有 getter，Inspector 上的 Clear Depth 勾选框对应序列化字段 m_ClearDepth
            var so = new SerializedObject(data);
            so.FindProperty("m_ClearDepth").boolValue = s.Panel == 2;   // 面板 1 不清深度，面板 2 清深度
            so.ApplyModifiedPropertiesWithoutUndo();
            s.CamData.cameraStack.Add(cam);

            var item = s.Knot(s.Lit(new Color(1f, 0.6f, 0.15f), 1f, 0.8f), Vector3.zero, 0.3f);
            item.layer = overlayLayer;
            item.transform.SetParent(s.Cam.transform, false);
            item.transform.localPosition = new Vector3(0.36f, -0.2f, 1.25f);
            item.transform.localRotation = Quaternion.Euler(20, 40, 0);
            //#endregion
        }

        // ---------- 案例 2.8：MSAA 与 Render Scale ----------
        [BookShot("ch02-aa-scale", W = 400, H = 300, Panels = 3)]
        static void AaScale(Shot s)
        {
            s.Asset.msaaSampleCount = s.Panel == 0 ? 1 : 4;
            s.Asset.renderScale = s.Panel == 2 ? 0.5f : 1f;
            var dark = s.Lit(new Color(0.12f, 0.12f, 0.14f), 0, 0.4f);
            for (int i = 0; i < 9; i++)
            {
                var c = s.Cylinder(dark, new Vector3(-2.0f + i * 0.5f, 0.9f, 0.4f + i * 0.15f));
                c.transform.localScale = new Vector3(0.04f, 0.9f, 0.04f);
                c.transform.rotation = Quaternion.Euler(0, 0, 8 + i * 3);
            }
            var bar = s.Cube(dark, new Vector3(0, 1.55f, 1.0f));
            bar.transform.localScale = new Vector3(5f, 0.05f, 0.05f);
            bar.transform.rotation = Quaternion.Euler(0, 15, 6);
            s.Cube(s.Lit(new Color(0.85f, 0.3f, 0.2f)), new Vector3(0.6f, 0.5f, 2.2f)).transform.rotation = Quaternion.Euler(0, 40, 0);
            s.Floor();
            s.LookAt(new Vector3(-0.6f, 1.5f, -2.4f), new Vector3(0, 1.0f, 1.0f), 45);
        }

        // ---------- 案例 2.8：HDR ----------
        // 拍成两张图：相机渲染到 RT 时，URP 14 的中间缓冲格式跟随目标 RT（见正文 2.7 节“深入”），
        // 所以 HDR 关闭的那张用 8 位目标，HDR 开启的那张用浮点目标（Hdr = true）。
        [BookShot("ch02-hdr-off", W = 640, H = 400)]
        static void HdrOff(Shot s) { s.Asset.supportsHDR = false; s.Cam.allowHDR = false; HdrScene(s); }

        [BookShot("ch02-hdr-on", W = 640, H = 400, Hdr = true)]
        static void HdrOn(Shot s) { s.Asset.supportsHDR = true; s.Cam.allowHDR = true; HdrScene(s); }

        static void HdrScene(Shot s)
        {
            var prof = s.Post();
            var bloom = prof.Add<Bloom>(); bloom.intensity.Override(1.5f); bloom.threshold.Override(1f); bloom.scatter.Override(0.75f);
            var tm = prof.Add<Tonemapping>(); tm.mode.Override(TonemappingMode.ACES);

            s.Floor(s.Lit(new Color(0.25f, 0.26f, 0.28f), 0, 0.6f));
            s.Sphere(Emissive(s, new Color(1f, 0.3f, 0.04f), 4f), new Vector3(-1.4f, 0.45f, 0.4f), 0.9f);
            s.Sphere(Emissive(s, new Color(0.05f, 0.35f, 1f), 4f), new Vector3(0.0f, 0.45f, 0.9f), 0.9f);
            s.Sphere(Emissive(s, new Color(1f, 0.08f, 0.5f), 3f), new Vector3(1.4f, 0.45f, 0.4f), 0.9f);
            s.Knot(s.Lit(new Color(0.9f, 0.85f, 0.7f), 1f, 0.85f), new Vector3(-0.3f, 0.5f, -0.9f), 0.42f);
            s.Cube(s.Lit(new Color(0.95f, 0.95f, 0.95f), 0, 0.3f), new Vector3(1.0f, 0.3f, -0.8f), 0.6f).transform.rotation = Quaternion.Euler(0, 25, 0);
            s.Point(new Vector3(0.6f, 0.9f, -1.2f), new Color(1f, 0.85f, 0.6f), 6f, 4f);   // 一盏很亮的点光，让白色方块的受光面超过 1
            s.SunDir(40, -40, 0.25f);
            DimEnvironment(0.15f);
            s.Background(new Color(0.02f, 0.025f, 0.04f));
            s.LookAt(new Vector3(0.1f, 1.5f, -4.2f), new Vector3(0, 0.4f, 0.1f), 38);
        }
    }
}
