// 案例 29.5：Overdraw 可视化 Renderer Feature。
// 用 overrideMaterial 把可见物体全部重画一遍到一张 R16 浮点 RT（每层 +1），再用热度图画回相机颜色。
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch29
{
    public class OverdrawFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            public Material countMaterial;     // Cookbook/Ch29/OverdrawCount
            public Material heatmapMaterial;   // Cookbook/Ch29/OverdrawHeatmap
            public bool opaque = true;
            public bool transparent = true;
            public LayerMask layerMask = -1;
        }
        public Settings settings = new Settings();
        OverdrawPass m_Pass;

        public override void Create() { m_Pass = new OverdrawPass(); }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (settings.countMaterial == null || settings.heatmapMaterial == null) return;
            if (renderingData.cameraData.cameraType == CameraType.Preview) return;
            m_Pass.renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
            m_Pass.Setup(settings);
            renderer.EnqueuePass(m_Pass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_Pass.SetCameraColor(renderer.cameraColorTargetHandle);
        }

        protected override void Dispose(bool disposing) { m_Pass?.Dispose(); }

        class OverdrawPass : ScriptableRenderPass
        {
            // 和 URP 自己画不透明/透明物体时用的 LightMode 列表一致
            static readonly List<ShaderTagId> s_Tags = new List<ShaderTagId>
            {
                new ShaderTagId("UniversalForward"), new ShaderTagId("UniversalForwardOnly"),
                new ShaderTagId("SRPDefaultUnlit"), new ShaderTagId("LightweightForward"),
            };
            Settings m_Settings;
            RTHandle m_CameraColor, m_Count;

            public OverdrawPass() { profilingSampler = new ProfilingSampler("OverdrawView"); }
            public void Setup(Settings s) { m_Settings = s; }
            public void SetCameraColor(RTHandle h) { m_CameraColor = h; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;
                desc.depthBufferBits = 0;
                desc.colorFormat = RenderTextureFormat.RHalf;   // 计数可能超过 1，要浮点格式
                RenderingUtils.ReAllocateIfNeeded(ref m_Count, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_OverdrawCount");
                ConfigureTarget(m_Count);
                ConfigureClear(ClearFlag.Color, Color.black);
            }

            //#region execute
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    // ConfigureTarget/ConfigureClear 已经把 m_Count 设为目标并清成 0
                    context.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                    if (m_Settings.opaque) Draw(context, ref renderingData, RenderQueueRange.opaque, SortingCriteria.CommonOpaque);
                    if (m_Settings.transparent) Draw(context, ref renderingData, RenderQueueRange.transparent, SortingCriteria.CommonTransparent);
                    Blitter.BlitCameraTexture(cmd, m_Count, m_CameraColor, m_Settings.heatmapMaterial, 0);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            void Draw(ScriptableRenderContext context, ref RenderingData renderingData, RenderQueueRange range, SortingCriteria sort)
            {
                var drawing = CreateDrawingSettings(s_Tags, ref renderingData, sort);
                drawing.overrideMaterial = m_Settings.countMaterial;   // 所有物体都用计数材质画
                drawing.overrideMaterialPassIndex = 0;
                var filtering = new FilteringSettings(range, m_Settings.layerMask);
                context.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);
            }
            //#endregion

            public void Dispose() { m_Count?.Release(); }
        }
    }
}
