// 第 28 章通用的“全屏效果” Renderer Feature（URP 14 的 RTHandle + Blitter 写法）。
// 做的事很简单：把相机颜色拷贝到一张临时 RT，再用指定材质画回相机颜色。
// 本章的世界坐标重建、扫描线、雾、SSR 都靠它跑，算法全部写在各自的 Shader 里。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch28
{
    public class ScreenEffectFeature : ScriptableRendererFeature
    {
        //#region settings
        [System.Serializable]
        public class Settings
        {
            public Material material;
            public int passIndex = 0;
            // 屏幕空间效果大多放在不透明物体之后、后处理之前
            public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            // 需要哪些屏幕纹理：Depth 会保证 _CameraDepthTexture 可用，Normal 会触发 DepthNormals 预通道
            public ScriptableRenderPassInput requirements = ScriptableRenderPassInput.Depth;
        }
        public Settings settings = new Settings();
        //#endregion

        ScreenEffectPass m_Pass;

        public override void Create()
        {
            m_Pass = new ScreenEffectPass(name);
        }

        //#region add
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
        //#endregion

        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
        }

        //#region pass
        class ScreenEffectPass : ScriptableRenderPass
        {
            Material m_Material;
            int m_PassIndex;
            RTHandle m_CameraColor;
            RTHandle m_Copy;

            public ScreenEffectPass(string name)
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
                RenderingUtils.ReAllocateIfNeeded(ref m_Copy, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_ScreenEffectCopy");
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
        //#endregion
    }
}
