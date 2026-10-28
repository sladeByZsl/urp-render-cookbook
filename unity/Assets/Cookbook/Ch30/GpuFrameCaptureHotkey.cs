// 30.4 节：在 macOS / iOS 上用代码触发 Metal 帧捕获（UnityEngine.Apple.FrameCapture）。
// 按 F11（或调用 Capture()）抓取下一帧：能直接连 Xcode 时交给 Xcode，否则存成 .gputrace 文件，之后用 Xcode 打开。
// 写文件需要 Metal 捕获功能被允许（例如以环境变量 MTL_CAPTURE_ENABLED=1 启动，或在 Info.plist 中开启），以 Apple 文档为准。
using System.IO;
using UnityEngine;
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IOS
using UnityEngine.Apple;
#endif

namespace Cookbook.Ch30
{
    public class GpuFrameCaptureHotkey : MonoBehaviour
    {
        public KeyCode key = KeyCode.F11;

        void Update()
        {
            if (Input.GetKeyDown(key)) Capture();
        }

        //#region capture
        public void Capture()
        {
#if UNITY_EDITOR_OSX || UNITY_STANDALONE_OSX || UNITY_IOS
            if (FrameCapture.IsDestinationSupported(FrameCaptureDestination.DevTools))
            {
                FrameCapture.CaptureNextFrameToXcode();          // 由 Xcode 启动时：直接在 Xcode 里打开
                Debug.Log("[GpuCapture] next frame -> Xcode");
            }
            else if (FrameCapture.IsDestinationSupported(FrameCaptureDestination.GPUTraceDocument))
            {
                string path = Path.Combine(Application.persistentDataPath,
                    $"frame_{System.DateTime.Now:yyyyMMdd_HHmmss}.gputrace");
                FrameCapture.CaptureNextFrameToFile(path);       // 否则写成 .gputrace 文件
                Debug.Log("[GpuCapture] next frame -> " + path);
            }
            else
            {
                Debug.LogWarning("[GpuCapture] Metal frame capture is not enabled for this process.");
            }
#else
            Debug.LogWarning("[GpuCapture] Metal frame capture is only available on Apple platforms. Use RenderDoc / PIX / AGI instead.");
#endif
        }
        //#endregion
    }
}
