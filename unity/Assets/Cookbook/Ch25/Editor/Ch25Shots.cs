// 第 25 章配图：每张图都在空场景里搭景，并给本张图专用的 Renderer 加上要演示的 Feature。
using System.IO;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Experimental.Rendering.Universal;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch25
{
    static class Ch25Shots
    {
        const int LayerA = 8;   // 演示用的“选中层”
        const int LayerB = 9;   // 演示用的“幽灵层”

        // 通用场景：棋盘地面 + 几个彩色物体
        static void Stage(Shot s, int markedLayer = -1)
        {
            s.Floor();
            var knot = s.Knot(s.Lit(new Color(0.95f, 0.45f, 0.12f), 0f, 0.6f), new Vector3(0, 0.95f, 0.4f), 1.0f);
            var red = s.Sphere(s.Lit(new Color(0.85f, 0.12f, 0.12f), 0f, 0.75f), new Vector3(-1.55f, 0.45f, -0.3f), 0.9f);
            var cube = s.Cube(s.Lit(new Color(0.15f, 0.35f, 0.9f), 0f, 0.4f), new Vector3(1.55f, 0.4f, -0.1f), 0.8f);
            cube.transform.rotation = Quaternion.Euler(0, 30, 0);
            s.Sphere(s.Lit(new Color(0.9f, 0.9f, 0.92f), 1f, 0.85f), new Vector3(0.7f, 0.3f, -1.0f), 0.6f);
            s.Capsule(s.Lit(new Color(0.2f, 0.75f, 0.35f), 0f, 0.5f), new Vector3(-0.6f, 0.5f, 1.8f), 1.0f);
            if (markedLayer >= 0) { knot.layer = markedLayer; red.layer = markedLayer; }
            s.LookAt(new Vector3(0, 1.75f, -5.3f), new Vector3(0, 0.6f, 0.2f), 38);
        }

        //#region shot-tint
        [BookShot("ch25-tint", W = 640, H = 400, Panels = 3)]
        static void Tint(Shot s)
        {
            Stage(s);
            if (s.Panel == 0) return;                       // 第 1 格：不加 Feature
            var f = s.Feature<TintFeature>();
            if (s.Panel == 1) { f.settings.invert = 1; f.settings.desaturate = 0; }
            else { f.settings.invert = 0; f.settings.desaturate = 1; f.settings.tint = new Color(1.25f, 0.95f, 0.65f); }
        }
        //#endregion

        // 案例 25.2：同一个“去色”Pass 放在三个不同事件上
        [BookShot("ch25-event", W = 640, H = 400, Panels = 3)]
        static void EventOrder(Shot s)
        {
            if (s.Panel == 0)
            {
                // 顺便把生命周期探针的输出写进文件，正文里引用的就是这份真实日志
                string path = Path.GetFullPath(Path.Combine(Application.dataPath, "../Logs/ch25_lifecycle.txt"));
                File.WriteAllText(path, "");
                LifecycleProbeFeature.Sink = line => File.AppendAllText(path, line + "\n");
                s.Feature<LifecycleProbeFeature>();
            }
            else LifecycleProbeFeature.Sink = null;

            Stage(s);
            var glass = s.Mat("Cookbook/Ch25/SimpleTransparent");
            glass.SetColor("_BaseColor", new Color(0.2f, 0.85f, 1f, 0.55f));
            s.Sphere(glass, new Vector3(-0.35f, 0.7f, -1.2f), 0.9f);
            var glass2 = s.Mat("Cookbook/Ch25/SimpleTransparent");
            glass2.SetColor("_BaseColor", new Color(1f, 0.25f, 0.7f, 0.55f));
            s.Cube(glass2, new Vector3(1.0f, 0.55f, -1.3f), 0.55f).transform.rotation = Quaternion.Euler(20, 40, 0);
            s.LookAt(new Vector3(0, 1.6f, -4.6f), new Vector3(0, 0.75f, 0), 40);

            var f = s.Feature<TintFeature>();
            f.settings.invert = 0; f.settings.desaturate = 1;
            f.settings.passEvent = s.Panel == 0 ? RenderPassEvent.AfterRenderingOpaques
                                 : s.Panel == 1 ? RenderPassEvent.AfterRenderingSkybox
                                 : RenderPassEvent.AfterRenderingTransparents;
        }

        //#region shot-fullscreen
        [BookShot("ch25-fullscreen", W = 640, H = 400, Panels = 3)]
        static void FullScreen(Shot s)
        {
            Stage(s);
            // 加一排远处的柱子，让深度雾有层次
            for (int i = 0; i < 6; i++)
                s.Cylinder(s.Lit(new Color(0.8f, 0.78f, 0.72f), 0, 0.3f), new Vector3(-5f + i * 2f, 1.5f, 4f + i * 2.5f), 1f)
                    .transform.localScale = new Vector3(0.6f, 1.5f, 0.6f);
            if (s.Panel == 0) return;

            var f = s.Feature<FullScreenPassRendererFeature>();
            if (s.Panel == 1)
            {
                f.passMaterial = s.Mat("Cookbook/Ch25/FullscreenNightVision");
                f.injectionPoint = FullScreenPassRendererFeature.InjectionPoint.AfterRenderingPostProcessing;
                f.fetchColorBuffer = true;                               // 需要读屏幕颜色
                f.requirements = ScriptableRenderPassInput.None;
            }
            else
            {
                f.passMaterial = s.Mat("Cookbook/Ch25/FullscreenDepthFog");
                f.injectionPoint = FullScreenPassRendererFeature.InjectionPoint.BeforeRenderingPostProcessing;
                f.fetchColorBuffer = true;
                f.requirements = ScriptableRenderPassInput.Depth;        // 需要 _CameraDepthTexture
            }
        }
        //#endregion

        //#region shot-renderobjects
        [BookShot("ch25-renderobjects", W = 640, H = 400, Panels = 2)]
        static void RenderObjectsShot(Shot s)
        {
            Stage(s, LayerA);          // 纽结和红球放到第 8 层
            if (s.Panel == 0) return;

            var f = s.Feature<RenderObjects>();
            f.settings.Event = RenderPassEvent.AfterRenderingOpaques;
            f.settings.filterSettings.RenderQueueType = RenderQueueType.Opaque;
            f.settings.filterSettings.LayerMask = 1 << LayerA;
            f.settings.overrideMode = RenderObjects.RenderObjectsSettings.OverrideMaterialMode.Material;
            f.settings.overrideMaterial = s.Mat("Cookbook/Ch25/RimOverlay");
            f.settings.overrideMaterialPassIndex = 0;
            // RenderObjects 只在 Create() 里把 settings 转成 Pass 参数。这里 Renderer 尚未创建，
            // 它创建时会调用每个 Feature 的 Create()；若 Renderer 已在运行，改完 settings 必须手动再调一次。
            f.Create();
        }
        //#endregion

        // 案例 25.5：遮罩 RT 的调试视图（透视 vs 只看可见部分）
        [BookShot("ch25-layer-mask", W = 640, H = 400, Panels = 3)]
        static void LayerMaskShot(Shot s)
        {
            Stage(s, LayerA);
            // 一块挡在红球前面的板子，用来观察“透视/不透视”的区别
            s.Cube(s.Lit(new Color(0.55f, 0.5f, 0.45f), 0, 0.3f), new Vector3(-1.2f, 0.45f, -1.25f), 1f)
                .transform.localScale = new Vector3(0.9f, 0.9f, 0.08f);
            if (s.Panel == 0) return;
            var f = s.Feature<LayerOutlineFeature>();
            f.settings.layerMask = 1 << LayerA;
            f.settings.mode = LayerOutlineFeature.Mode.DebugMask;
            f.settings.seeThrough = s.Panel == 1;
        }

        //#region shot-outline
        [BookShot("ch25-layer-outline", W = 640, H = 400, Panels = 3)]
        static void LayerOutlineShot(Shot s)
        {
            Stage(s, LayerA);
            s.Cube(s.Lit(new Color(0.55f, 0.5f, 0.45f), 0, 0.3f), new Vector3(-1.2f, 0.45f, -1.25f), 1f)
                .transform.localScale = new Vector3(0.9f, 0.9f, 0.08f);
            var f = s.Feature<LayerOutlineFeature>();
            f.settings.layerMask = 1 << LayerA;
            f.settings.width = 4;
            switch (s.Panel)
            {
                case 0: f.settings.seeThrough = true; break;
                case 1: f.settings.seeThrough = false; break;
                default:
                    f.settings.seeThrough = true;
                    f.settings.outlineColor = new Color(0.2f, 0.9f, 1f, 1f);
                    f.settings.fillColor = new Color(0.2f, 0.9f, 1f, 0.35f);   // 纯色填充 + 描边
                    f.settings.width = 6;
                    break;
            }
        }
        //#endregion

        // 案例 25.7：幽灵层
        static void GhostStage(Shot s, bool naive)
        {
            s.Floor();
            s.Cube(s.Lit(new Color(0.15f, 0.35f, 0.9f), 0f, 0.4f), new Vector3(1.6f, 0.4f, 0.4f), 0.8f);
            s.Sphere(s.Lit(new Color(0.85f, 0.12f, 0.12f), 0f, 0.75f), new Vector3(-1.7f, 0.45f, 0.6f), 0.9f);
            // 一根挡在角色前方的柱子：验证合成时的深度遮挡
            s.Cylinder(s.Lit(new Color(0.8f, 0.78f, 0.72f), 0, 0.3f), new Vector3(0.55f, 1f, -0.9f), 1f)
                .transform.localScale = new Vector3(0.3f, 1f, 0.3f);

            // 由几个基本体拼成的“小人”：身体、头、双臂、双腿互相穿插
            Material mat;
            if (naive)
            {
                mat = s.Mat("Cookbook/Ch25/SimpleTransparent");
                mat.SetColor("_BaseColor", new Color(0.6f, 0.9f, 1.0f, 0.45f));
            }
            else mat = s.Lit(new Color(0.75f, 0.92f, 1f), 0f, 0.6f);

            var root = new GameObject("Ghost").transform;
            void Part(PrimitiveType t, Vector3 p, Vector3 scl, Vector3 rot)
            {
                var go = s.Prim(t, mat, p);
                go.transform.localScale = scl;
                go.transform.rotation = Quaternion.Euler(rot);
                go.transform.SetParent(root, true);
                go.layer = LayerB;
                go.GetComponent<Renderer>().shadowCastingMode = ShadowCastingMode.Off;
            }
            Part(PrimitiveType.Capsule, new Vector3(0, 1.05f, 0), new Vector3(0.55f, 0.5f, 0.4f), Vector3.zero);       // 身体
            Part(PrimitiveType.Sphere, new Vector3(0, 1.75f, 0), Vector3.one * 0.48f, Vector3.zero);                  // 头
            Part(PrimitiveType.Capsule, new Vector3(-0.22f, 1.05f, -0.28f), new Vector3(0.2f, 0.42f, 0.2f), new Vector3(-55, 0, -40)); // 左臂（向前抱在胸前）
            Part(PrimitiveType.Capsule, new Vector3(0.22f, 1.05f, -0.28f), new Vector3(0.2f, 0.42f, 0.2f), new Vector3(-55, 0, 40));   // 右臂
            Part(PrimitiveType.Capsule, new Vector3(-0.15f, 0.42f, 0), new Vector3(0.22f, 0.42f, 0.22f), Vector3.zero);  // 左腿
            Part(PrimitiveType.Capsule, new Vector3(0.15f, 0.42f, 0), new Vector3(0.22f, 0.42f, 0.22f), Vector3.zero);   // 右腿
            s.LookAt(new Vector3(0, 1.5f, -4.0f), new Vector3(0, 0.95f, 0), 38);
        }

        //#region shot-ghost
        [BookShot("ch25-ghost", W = 640, H = 440, Panels = 3)]
        static void Ghost(Shot s)
        {
            GhostStage(s, naive: s.Panel == 0);
            if (s.Panel == 0) return;    // 第 1 格：逐物体半透明（对照组）

            // 幽灵层不参与主不透明 Pass，只由 Feature 单独绘制
            s.Renderer.opaqueLayerMask = ~(1 << LayerB);
            var f = s.Feature<GhostLayerFeature>();
            f.settings.layerMask = 1 << LayerB;
            if (s.Panel == 1) { f.settings.rimWidth = 0; f.settings.opacity = 0.45f; }
            else { f.settings.rimWidth = 3; f.settings.opacity = 0.3f; }
        }
        //#endregion
    }
}
