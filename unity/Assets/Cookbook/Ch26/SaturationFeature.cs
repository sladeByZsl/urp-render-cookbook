// 案例 26.1：读取 Volume 的后处理 Feature（不依赖任何基类，完整写一遍）。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    public class SaturationFeature : ScriptableRendererFeature
    {
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Shader shader;

        Material m_Material;
        SaturationPass m_Pass;

        public override void Create()
        {
            Dispose(true);
            if (shader == null) shader = Shader.Find("Cookbook/Ch26/Saturation");
            if (shader == null) return;
            m_Material = CoreUtils.CreateEngineMaterial(shader);
            m_Pass = new SaturationPass(m_Material);
        }

        //#region add-passes
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (m_Pass == null) return;
            ref var cameraData = ref renderingData.cameraData;
            if (cameraData.cameraType == CameraType.Preview || cameraData.cameraType == CameraType.Reflection) return;
            // 和 URP 自带后处理保持一致：相机没勾 Post Processing 就不做
            if (!cameraData.postProcessEnabled) return;

            // VolumeManager 已经在渲染这个相机之前，按相机位置/层把所有 Volume 混合进 stack
            var volume = VolumeManager.instance.stack.GetComponent<SaturationVolume>();
            if (volume == null || !volume.IsActive()) return;   // 没效果就不入队

            m_Pass.renderPassEvent = passEvent;
            m_Pass.Setup(volume);
            renderer.EnqueuePass(m_Pass);
        }
        //#endregion

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_Pass?.SetTarget(renderer.cameraColorTargetHandle, renderer.cameraDepthTargetHandle);
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
            m_Pass = null;
            CoreUtils.Destroy(m_Material);
            m_Material = null;
        }

        //#region pass
        class SaturationPass : ScriptableRenderPass
        {
            static readonly int s_Saturation = Shader.PropertyToID("_Saturation");
            static readonly int s_Contrast = Shader.PropertyToID("_Contrast");

            readonly Material m_Material;
            RTHandle m_Color, m_Depth, m_Temp;

            public SaturationPass(Material m)
            {
                m_Material = m;
                profilingSampler = new ProfilingSampler("Ch26 Saturation");
            }

            public void Setup(SaturationVolume v)
            {
                // .value 是混合后的最终值（多个 Volume 按权重插值的结果）
                m_Material.SetFloat(s_Saturation, v.saturation.value);
                m_Material.SetFloat(s_Contrast, v.contrast.value);
            }

            public void SetTarget(RTHandle color, RTHandle depth) { m_Color = color; m_Depth = depth; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;
                desc.depthBufferBits = 0;
                RenderingUtils.ReAllocateIfNeeded(ref m_Temp, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_Ch26SaturationTemp");
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    Blitter.BlitCameraTexture(cmd, m_Color, m_Temp, m_Material, 0);
                    Blitter.BlitCameraTexture(cmd, m_Temp, m_Color);
                    CoreUtils.SetRenderTarget(cmd, m_Color, m_Depth);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose()
            {
                m_Temp?.Release();
                m_Temp = null;
            }
        }
        //#endregion
    }
}
