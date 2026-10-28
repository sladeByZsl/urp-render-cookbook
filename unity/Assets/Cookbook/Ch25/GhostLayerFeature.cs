// 案例 25.7：把某个 Layer 单独渲染到离屏 RT（颜色+自己的深度），再整体半透明合成回屏幕。
// 好处：整个角色作为“一张图”淡出，看不到它内部互相穿插的结构；还能和场景深度比较，正确被遮挡。
// 用法：把该 Layer 从 Renderer 的 Opaque Layer Mask 里去掉（否则它会在主 Pass 里再画一次）。
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch25
{
    public class GhostLayerFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            public LayerMask layerMask = 1 << 9;
            [Range(0, 1)] public float opacity = 0.45f;
            public Color tint = new Color(0.75f, 0.95f, 1.1f, 1f);
            [ColorUsage(true, true)] public Color rimColor = new Color(0.3f, 1.2f, 2.0f, 1f);
            [Range(0, 8)] public float rimWidth = 3f;
        }

        public Settings settings = new Settings();
        public Shader compositeShader;

        Material m_Material;
        LayerPass m_LayerPass;
        CompositePass m_CompositePass;

        public override void Create()
        {
            Dispose(true);
            if (compositeShader == null) compositeShader = Shader.Find("Cookbook/Ch25/GhostComposite");
            m_Material = CoreUtils.CreateEngineMaterial(compositeShader);
            m_LayerPass = new LayerPass { renderPassEvent = RenderPassEvent.AfterRenderingOpaques };
            m_CompositePass = new CompositePass(m_Material) { renderPassEvent = RenderPassEvent.AfterRenderingTransparents };
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var camType = renderingData.cameraData.cameraType;
            if (camType == CameraType.Preview || camType == CameraType.Reflection) return;

            m_LayerPass.layerMask = settings.layerMask;
            m_CompositePass.Setup(settings, m_LayerPass);
            // 合成时要和场景深度比较 → 声明需要 _CameraDepthTexture
            m_CompositePass.ConfigureInput(ScriptableRenderPassInput.Depth);
            renderer.EnqueuePass(m_LayerPass);
            renderer.EnqueuePass(m_CompositePass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_CompositePass.SetTarget(renderer.cameraColorTargetHandle, renderer.cameraDepthTargetHandle);
        }

        protected override void Dispose(bool disposing)
        {
            m_LayerPass?.Dispose();
            CoreUtils.Destroy(m_Material);
        }

        //#region layer-pass
        class LayerPass : ScriptableRenderPass
        {
            static readonly List<ShaderTagId> s_ShaderTags = new List<ShaderTagId>
            {
                new ShaderTagId("UniversalForward"),
                new ShaderTagId("UniversalForwardOnly"),
                new ShaderTagId("SRPDefaultUnlit"),
            };

            public LayerMask layerMask;
            public RTHandle color, depth;

            public LayerPass() { profilingSampler = new ProfilingSampler("Ch25 Ghost Layer"); }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;

                // 颜色：带 Alpha 的半精度浮点（HDR 光照结果 + 覆盖率）
                var colorDesc = desc;
                colorDesc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
                colorDesc.depthBufferBits = 0;
                RenderingUtils.ReAllocateIfNeeded(ref color, colorDesc, FilterMode.Bilinear,
                    TextureWrapMode.Clamp, name: "_Ch25GhostColor");

                // 深度：纯深度格式的 RT，之后还要在合成 Shader 里当纹理采样
                var depthDesc = desc;
                depthDesc.graphicsFormat = GraphicsFormat.None;
                depthDesc.depthStencilFormat = GraphicsFormat.D32_SFloat;
                depthDesc.depthBufferBits = 32;
                RenderingUtils.ReAllocateIfNeeded(ref depth, depthDesc, FilterMode.Point,
                    TextureWrapMode.Clamp, name: "_Ch25GhostDepth");

                ConfigureTarget(color, depth);
                ConfigureClear(ClearFlag.All, Color.clear);   // 颜色清成全透明，深度清成最远
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    // 不覆盖材质：用物体自己的 Lit 材质正常打光，只是画到了另一张 RT 上
                    var drawing = CreateDrawingSettings(s_ShaderTags, ref renderingData,
                        renderingData.cameraData.defaultOpaqueSortFlags);
                    var filtering = new FilteringSettings(RenderQueueRange.opaque, layerMask);
                    context.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose()
            {
                color?.Release(); color = null;
                depth?.Release(); depth = null;
            }
        }
        //#endregion

        //#region composite-pass
        class CompositePass : ScriptableRenderPass
        {
            static readonly int s_GhostDepth = Shader.PropertyToID("_GhostDepth");
            static readonly int s_Opacity = Shader.PropertyToID("_Opacity");
            static readonly int s_Tint = Shader.PropertyToID("_Tint");
            static readonly int s_RimColor = Shader.PropertyToID("_RimColor");
            static readonly int s_RimWidth = Shader.PropertyToID("_RimWidth");

            readonly Material m_Material;
            LayerPass m_Layer;
            RTHandle m_CameraColor, m_CameraDepth;

            public CompositePass(Material m)
            {
                m_Material = m;
                profilingSampler = new ProfilingSampler("Ch25 Ghost Composite");
            }

            public void Setup(Settings s, LayerPass layer)
            {
                m_Layer = layer;
                m_Material.SetFloat(s_Opacity, s.opacity);
                m_Material.SetColor(s_Tint, s.tint);
                m_Material.SetColor(s_RimColor, s.rimColor);
                m_Material.SetFloat(s_RimWidth, s.rimWidth);
            }

            public void SetTarget(RTHandle color, RTHandle depth) { m_CameraColor = color; m_CameraDepth = depth; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
                => ConfigureTarget(m_CameraColor, m_CameraDepth);

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    cmd.SetGlobalTexture(s_GhostDepth, m_Layer.depth);
                    Blitter.BlitTexture(cmd, m_Layer.color, new Vector4(1, 1, 0, 0), m_Material, 0);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
        //#endregion
    }
}
