// 第 2 章 案例 2.1：帧快照 Renderer Feature
// 在 captureEvent 这个时间点，把相机颜色缓冲“拍”一张快照；
// 在后处理之后，再把快照贴回相机颜色缓冲。于是屏幕上看到的，就是这一帧在 captureEvent 时刻的“半成品”。
// 用它可以一格一格地看 URP 一帧是怎么画出来的（与 Frame Debugger 互相印证）。
// Renderer Feature 的完整写法在第 25 章详细讲，这里先当工具用。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch02
{
    public class FrameSnapshotFeature : ScriptableRendererFeature
    {
        [Tooltip("在哪个时间点拍快照")]
        public RenderPassEvent captureEvent = RenderPassEvent.AfterRenderingOpaques;

        [Tooltip("在画不透明物体之前把颜色缓冲清成黑色。天空盒模式下 URP 通常只清深度，颜色缓冲里会残留上一帧的内容")]
        public bool clearColorBeforeOpaques = true;

        ClearColorPass m_Clear;
        CapturePass m_Capture;
        RestorePass m_Restore;
        RTHandle m_Snapshot;

        //#region feature
        public override void Create()
        {
            m_Clear = new ClearColorPass { renderPassEvent = RenderPassEvent.BeforeRenderingOpaques };
            m_Capture = new CapturePass();
            m_Restore = new RestorePass();
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            // 只处理游戏相机，Scene 视图、预览窗口保持原样
            if (renderingData.cameraData.cameraType != CameraType.Game)
                return;
            m_Capture.renderPassEvent = captureEvent;
            // 贴回去的时机：后处理之后、FinalBlit 之前
            m_Restore.renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
            if (clearColorBeforeOpaques)
                renderer.EnqueuePass(m_Clear);
            renderer.EnqueuePass(m_Capture);
            renderer.EnqueuePass(m_Restore);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            if (renderingData.cameraData.cameraType != CameraType.Game)
                return;
            // 快照的格式与相机颜色缓冲一致（HDR 时是浮点格式），但不需要深度、不需要 MSAA
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;
            RenderingUtils.ReAllocateIfNeeded(ref m_Snapshot, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_FrameSnapshot");
            m_Capture.Setup(m_Snapshot);
            m_Restore.Setup(m_Snapshot);
        }

        protected override void Dispose(bool disposing)
        {
            m_Snapshot?.Release();
        }
        //#endregion

        //#region passes
        class ClearColorPass : ScriptableRenderPass
        {
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                // 没有调用 ConfigureTarget，执行到这里时 URP 已经绑定了相机颜色/深度缓冲
                var cmd = CommandBufferPool.Get();
                cmd.ClearRenderTarget(RTClearFlags.Color, Color.black, 1f, 0);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        class CapturePass : ScriptableRenderPass
        {
            RTHandle m_Destination;
            public CapturePass() { profilingSampler = new ProfilingSampler("Cookbook Snapshot Capture"); }

            public void Setup(RTHandle destination) { m_Destination = destination; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 告诉 URP 这个 Pass 的输出目标，URP 才知道之后的 Pass 需要重新绑定相机目标
                ConfigureTarget(m_Destination);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                // 相机颜色缓冲在 Execute 里现取：后处理开启时 URP 用两个缓冲交替（swap buffer），
                // 在 SetupRenderPasses 里缓存的句柄不一定是此刻正在画的那一个
                var source = renderingData.cameraData.renderer.cameraColorTargetHandle;
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    // 开了 MSAA 时，相机颜色缓冲是多重采样纹理，“解析”（resolve）之前直接采样它，
                    // 读到的可能是上一次解析留下的旧内容。这里显式解析到快照里，读到的才是此刻的画面。
                    if (source.rt != null && source.rt.antiAliasing > 1)
                        cmd.ResolveAntiAliasedSurface(source.rt, m_Destination.rt);
                    else
                        Blitter.BlitCameraTexture(cmd, source, m_Destination);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        class RestorePass : ScriptableRenderPass
        {
            RTHandle m_Snapshot;
            public RestorePass() { profilingSampler = new ProfilingSampler("Cookbook Snapshot Restore"); }
            public void Setup(RTHandle snapshot) { m_Snapshot = snapshot; }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                // 后处理会在两个颜色缓冲之间来回切换（swap buffer），所以在 Execute 里现取“当前”的相机颜色缓冲
                var target = renderingData.cameraData.renderer.cameraColorTargetHandle;
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                    Blitter.BlitCameraTexture(cmd, m_Snapshot, target);
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
        //#endregion
    }
}
