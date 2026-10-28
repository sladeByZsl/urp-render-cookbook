// 第 30 章的全屏调试 Feature：把相机颜色拷贝一份，再用调试材质（像素校验等）画回去。
// 结构与第 28 章的 ScreenEffectFeature 相同，单独放一份让本章代码自成一体。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch30
{
    public class FullscreenDebugFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            public Material material;
            public int passIndex = 0;
            // 校验 HDR 场景颜色：放在后处理之前；想检查最终画面就改成 AfterRenderingPostProcessing
            public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            public ScriptableRenderPassInput requirements = ScriptableRenderPassInput.None;
        }
        public Settings settings = new Settings();

        FullscreenDebugPass m_Pass;

        public override void Create()
        {
            m_Pass = new FullscreenDebugPass(name);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var camType = renderingData.cameraData.cameraType;
            if (settings.material == null || camType == CameraType.Preview || camType == CameraType.Reflection)
                return;
            m_Pass.renderPassEvent = settings.renderPassEvent;
            m_Pass.ConfigureInput(settings.requirements);
            m_Pass.Setup(settings.material, settings.passIndex);
            renderer.EnqueuePass(m_Pass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            // cameraColorTargetHandle 只有在这里（以及之后）才是本帧有效的句柄
            m_Pass.SetTarget(renderer.cameraColorTargetHandle);
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
        }

        class FullscreenDebugPass : ScriptableRenderPass
        {
            Material m_Material;
            int m_PassIndex;
            RTHandle m_CameraColor;
            RTHandle m_Copy;

            public FullscreenDebugPass(string name)
            {
                profilingSampler = new ProfilingSampler(name);
            }

            public void Setup(Material material, int passIndex) { m_Material = material; m_PassIndex = passIndex; }
            public void SetTarget(RTHandle cameraColor) { m_CameraColor = cameraColor; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 临时 RT 与相机目标同尺寸、同格式，但不要 MSAA、不要深度
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;
                desc.depthBufferBits = 0;
                RenderingUtils.ReAllocateIfNeeded(ref m_Copy, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_FullscreenDebugCopy");
                ConfigureTarget(m_CameraColor);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    // 不能边读边写同一张 RT：先拷贝，再以拷贝为 _BlitTexture 画回去
                    Blitter.BlitCameraTexture(cmd, m_CameraColor, m_Copy);
                    Blitter.BlitCameraTexture(cmd, m_Copy, m_CameraColor, m_Material, m_PassIndex);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose() { m_Copy?.Release(); }
        }
    }
}
