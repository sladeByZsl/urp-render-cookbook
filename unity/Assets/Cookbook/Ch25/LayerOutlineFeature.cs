// 案例 25.5 / 25.6：只给某个 Layer 的物体画遮罩，再根据遮罩画描边。
// 两个 Pass：MaskPass 用 DrawRenderers 把选中层画进一张 R8 遮罩；CompositePass 读遮罩、膨胀、叠到屏幕上。
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch25
{
    public class LayerOutlineFeature : ScriptableRendererFeature
    {
        public enum Mode { Outline, DebugMask }

        [System.Serializable]
        public class Settings
        {
            public LayerMask layerMask = 1 << 8;
            [Tooltip("勾选：被其他物体挡住的部分也描（透视描边）；不勾：只描看得见的部分")]
            public bool seeThrough = true;
            public Color outlineColor = new Color(1f, 0.55f, 0.1f, 1f);
            public Color fillColor = new Color(1f, 0.55f, 0.1f, 0f);
            [Range(1, 16)] public float width = 4f;
            public Mode mode = Mode.Outline;
            public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingTransparents;
        }

        public Settings settings = new Settings();
        public Shader maskShader;
        public Shader outlineShader;

        Material m_MaskMaterial, m_OutlineMaterial;
        MaskPass m_MaskPass;
        CompositePass m_CompositePass;

        public override void Create()
        {
            Dispose(true);
            if (maskShader == null) maskShader = Shader.Find("Cookbook/Ch25/LayerMaskSolid");
            if (outlineShader == null) outlineShader = Shader.Find("Cookbook/Ch25/LayerOutline");
            m_MaskMaterial = CoreUtils.CreateEngineMaterial(maskShader);
            m_OutlineMaterial = CoreUtils.CreateEngineMaterial(outlineShader);
            m_MaskPass = new MaskPass(m_MaskMaterial);
            m_CompositePass = new CompositePass(m_OutlineMaterial);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var camType = renderingData.cameraData.cameraType;
            if (camType == CameraType.Preview || camType == CameraType.Reflection) return;

            // 两个 Pass 同一个事件：入队顺序就是执行顺序（URP 用稳定排序）
            m_MaskPass.renderPassEvent = settings.passEvent;
            m_CompositePass.renderPassEvent = settings.passEvent;
            m_MaskPass.Setup(settings);
            m_CompositePass.Setup(settings, m_MaskPass);
            renderer.EnqueuePass(m_MaskPass);
            renderer.EnqueuePass(m_CompositePass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_MaskPass.cameraDepth = renderer.cameraDepthTargetHandle;
            m_CompositePass.SetTarget(renderer.cameraColorTargetHandle, renderer.cameraDepthTargetHandle);
        }

        protected override void Dispose(bool disposing)
        {
            m_MaskPass?.Dispose();
            CoreUtils.Destroy(m_MaskMaterial);
            CoreUtils.Destroy(m_OutlineMaterial);
        }

        //#region mask-pass
        class MaskPass : ScriptableRenderPass
        {
            // 只画原材质里有这些 LightMode 的物体（URP 前向渲染用到的三个标签）
            static readonly List<ShaderTagId> s_ShaderTags = new List<ShaderTagId>
            {
                new ShaderTagId("UniversalForward"),
                new ShaderTagId("UniversalForwardOnly"),
                new ShaderTagId("SRPDefaultUnlit"),
            };

            readonly Material m_Material;
            FilteringSettings m_Filtering;
            RenderStateBlock m_StateBlock;
            public RTHandle mask;           // 遮罩 RT（自己分配）
            public RTHandle cameraDepth;    // 借用相机深度做遮挡测试

            public MaskPass(Material material)
            {
                m_Material = material;
                profilingSampler = new ProfilingSampler("Ch25 Layer Mask");
                m_Filtering = new FilteringSettings(RenderQueueRange.all);
            }

            public void Setup(Settings s)
            {
                m_Filtering.layerMask = s.layerMask;
                // 用 RenderStateBlock 覆盖材质里的深度状态：透视模式 ZTest Always，否则 LEqual
                m_StateBlock = new RenderStateBlock(RenderStateMask.Depth)
                {
                    depthState = new DepthState(false, s.seeThrough ? CompareFunction.Always : CompareFunction.LessEqual)
                };
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 遮罩与相机同尺寸、同 MSAA（要和相机深度一起绑定，两者采样数必须一致），单通道 8 位即可
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.graphicsFormat = GraphicsFormat.R8_UNorm;
                desc.depthBufferBits = 0;
                RenderingUtils.ReAllocateIfNeeded(ref mask, desc, FilterMode.Bilinear,
                    TextureWrapMode.Clamp, name: "_Ch25LayerMask");

                // 告诉 URP：这个 Pass 画到 mask 上，深度用相机深度；开始前只清颜色（深度绝不能清）
                ConfigureTarget(mask, cameraDepth);
                ConfigureClear(ClearFlag.Color, Color.clear);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    // 先把命令缓冲里已有的命令提交，再调用 context 级别的 DrawRenderers
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();

                    var drawing = CreateDrawingSettings(s_ShaderTags, ref renderingData, SortingCriteria.CommonOpaque);
                    drawing.overrideMaterial = m_Material;          // 所有物体都换成纯白材质
                    drawing.overrideMaterialPassIndex = 0;
                    context.DrawRenderers(renderingData.cullResults, ref drawing, ref m_Filtering, ref m_StateBlock);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose()
            {
                mask?.Release();
                mask = null;
            }
        }
        //#endregion

        //#region composite-pass
        class CompositePass : ScriptableRenderPass
        {
            static readonly int s_OutlineColor = Shader.PropertyToID("_OutlineColor");
            static readonly int s_FillColor = Shader.PropertyToID("_FillColor");
            static readonly int s_OutlineWidth = Shader.PropertyToID("_OutlineWidth");

            readonly Material m_Material;
            MaskPass m_MaskPass;
            RTHandle m_CameraColor, m_CameraDepth;
            int m_ShaderPass;

            public CompositePass(Material material)
            {
                m_Material = material;
                profilingSampler = new ProfilingSampler("Ch25 Outline Composite");
            }

            public void Setup(Settings s, MaskPass maskPass)
            {
                m_MaskPass = maskPass;
                m_ShaderPass = s.mode == Mode.Outline ? 0 : 1;
                m_Material.SetColor(s_OutlineColor, s.outlineColor);
                m_Material.SetColor(s_FillColor, s.fillColor);
                m_Material.SetFloat(s_OutlineWidth, s.width);
            }

            public void SetTarget(RTHandle color, RTHandle depth)
            {
                m_CameraColor = color;
                m_CameraDepth = depth;
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 画回相机颜色。显式 ConfigureTarget，URP 会在 MaskPass 之后重新绑定相机目标
                ConfigureTarget(m_CameraColor, m_CameraDepth);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    // 不切换目标，直接在当前目标（相机颜色）上画一个全屏三角形，靠混合叠加上去
                    Blitter.BlitTexture(cmd, m_MaskPass.mask, new Vector4(1, 1, 0, 0), m_Material, m_ShaderPass);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }
        //#endregion
    }
}
