// 案例 25.2：生命周期探针——把 Feature 与 Pass 的每个回调按调用顺序打印出来。
// 它什么也不画，只用来观察 URP 14 在一帧里按什么顺序调用我们。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch25
{
    public class LifecycleProbeFeature : ScriptableRendererFeature
    {
        // 输出到哪里：默认 Debug.Log，书中配图脚本会把它换成写文件
        public static System.Action<string> Sink = s => Debug.Log(s);
        static int s_Frame;

        public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingOpaques;
        ProbePass m_Pass;

        static void Log(string s) => Sink?.Invoke($"[帧{s_Frame}] {s}");

        //#region probe
        public override void Create()
        {
            Log("Feature.Create");
            m_Pass = new ProbePass();
        }

        public override void OnCameraPreCull(ScriptableRenderer renderer, in CameraData cameraData)
        {
            s_Frame++;
            Log($"Feature.OnCameraPreCull  camera={cameraData.camera.name}");
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            Log("Feature.AddRenderPasses");
            m_Pass.renderPassEvent = passEvent;
            m_Pass.ConfigureInput(ScriptableRenderPassInput.Depth);   // 必须在这里声明输入
            renderer.EnqueuePass(m_Pass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            // 此时相机目标已分配，可以安全读取
            Log($"Feature.SetupRenderPasses  color={renderer.cameraColorTargetHandle.name}");
        }

        protected override void Dispose(bool disposing) => Log("Feature.Dispose");

        class ProbePass : ScriptableRenderPass
        {
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
                => Log("  Pass.OnCameraSetup");
            public override void Configure(CommandBuffer cmd, RenderTextureDescriptor desc)
                => Log($"  Pass.Configure  {desc.width}x{desc.height} msaa={desc.msaaSamples}");
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
                => Log($"  Pass.Execute  event={renderPassEvent}");
            public override void OnCameraCleanup(CommandBuffer cmd)
                => Log("  Pass.OnCameraCleanup");
            public override void OnFinishCameraStackRendering(CommandBuffer cmd)
                => Log("  Pass.OnFinishCameraStackRendering");
        }
        //#endregion
    }
}
