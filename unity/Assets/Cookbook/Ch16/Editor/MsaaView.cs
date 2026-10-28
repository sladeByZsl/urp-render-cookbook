// 配图辅助：用一台辅助相机把场景以真正的 MSAA 渲染到 RenderTexture，
// 再让“摄影棚”主相机只拍一块显示这张 RT 的 Quad。
// 原因：摄影棚的抓图 RT 是单采样的，而 URP 在相机有 targetTexture 时以该 RT 的 antiAliasing 为准，
// Alpha to Coverage 这类依赖 MSAA 的效果必须这样才能拍出来。
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch16
{
    static class MsaaView
    {
        const int DisplayLayer = 31;

        /// downscale > 1 时以更低分辨率渲染、再用点采样放大，方便在书页上看清像素级的锯齿
        public static void Use(Shot s, int w, int h, int samples = 4, int downscale = 1)
        {
            var go = new GameObject("MSAA Camera");
            var cam = go.AddComponent<Camera>();
            cam.CopyFrom(s.Cam);                       // 复制机位、FOV、背景等
            var data = go.AddComponent<UniversalAdditionalCameraData>();
            data.renderPostProcessing = s.CamData.renderPostProcessing;
            cam.cullingMask = ~(1 << DisplayLayer);

            var rt = new RenderTexture(w / downscale, h / downscale, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB)
            { antiAliasing = samples, name = "MSAA View", filterMode = downscale > 1 ? FilterMode.Point : FilterMode.Bilinear };
            rt.Create();
            s.Temp.Add(rt);
            cam.targetTexture = rt;
            cam.aspect = (float)w / h;
            for (int i = 0; i < 3; i++) cam.Render();
            cam.enabled = false;

            // 主相机：正交、只看显示层上的一块 Quad
            var main = s.Cam;
            s.CamData.renderPostProcessing = false;
            main.transform.SetPositionAndRotation(new Vector3(0, -500, 0), Quaternion.identity);
            main.orthographic = true; main.orthographicSize = 0.5f;
            main.cullingMask = 1 << DisplayLayer;
            main.clearFlags = CameraClearFlags.SolidColor; main.backgroundColor = Color.black;

            var m = s.Mat("Universal Render Pipeline/Unlit");
            m.SetTexture("_BaseMap", rt);
            var q = s.Quad(m, new Vector3(0, -500, 1));
            q.transform.localScale = new Vector3((float)w / h, 1, 1);
            q.layer = DisplayLayer;
            q.GetComponent<MeshRenderer>().shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        }
    }
}
