// 案例 28.5：体积光 Renderer Feature —— 半分辨率光线步进 → 模糊 → 合成。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch28
{
    public class VolumetricLightFeature : ScriptableRendererFeature
    {
        public enum Output { Composite, ScatterOnly }

        [System.Serializable]
        public class Settings
        {
            public Material material;                 // Cookbook/Ch28/VolumetricLight
            [Range(1, 4)] public int downsample = 2;  // 体积光是低频信号，半分辨率甚至 1/4 分辨率都够
            public bool blur = true;
            public Output output = Output.Composite;
            public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
        }
        public Settings settings = new Settings();

        VolumetricPass m_Pass;

        public override void Create() { m_Pass = new VolumetricPass(); }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var camType = renderingData.cameraData.cameraType;
            if (settings.material == null || camType == CameraType.Preview || camType == CameraType.Reflection)
                return;
            // 没有主光阴影就没有“光束”，直接跳过
            if (!renderingData.shadowData.supportsMainLightShadows)
                return;
            m_Pass.renderPassEvent = settings.renderPassEvent;
            m_Pass.ConfigureInput(ScriptableRenderPassInput.Depth);
            m_Pass.Setup(settings);
            renderer.EnqueuePass(m_Pass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_Pass.SetCameraColor(renderer.cameraColorTargetHandle);
        }

        protected override void Dispose(bool disposing) { m_Pass?.Dispose(); }

        class VolumetricPass : ScriptableRenderPass
        {
            static readonly int s_TexelSize = Shader.PropertyToID("_VolTexelSize");
            static readonly int s_Result = Shader.PropertyToID("_VolumetricResult");
            Settings m_Settings;
            RTHandle m_CameraColor, m_Vol, m_VolTemp, m_Copy;

            public VolumetricPass() { profilingSampler = new ProfilingSampler("VolumetricLight"); }
            public void Setup(Settings s) { m_Settings = s; }
            public void SetCameraColor(RTHandle h) { m_CameraColor = h; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;
                desc.depthBufferBits = 0;
                RenderingUtils.ReAllocateIfNeeded(ref m_Copy, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_VolumetricColorCopy");

                var volDesc = desc;
                volDesc.width = Mathf.Max(1, desc.width / m_Settings.downsample);
                volDesc.height = Mathf.Max(1, desc.height / m_Settings.downsample);
                volDesc.colorFormat = RenderTextureFormat.ARGBHalf;   // 散射值可能 >1，用半精度浮点
                RenderingUtils.ReAllocateIfNeeded(ref m_Vol, volDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_Volumetric");
                RenderingUtils.ReAllocateIfNeeded(ref m_VolTemp, volDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_VolumetricTemp");
                ConfigureTarget(m_CameraColor);
            }

            //#region execute
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var mat = m_Settings.material;
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    int w = m_Vol.rt.width, h = m_Vol.rt.height;
                    mat.SetVector(s_TexelSize, new Vector4(1f / w, 1f / h, w, h));

                    CoreUtils.SetRenderTarget(cmd, m_Vol);
                    Blitter.BlitTexture(cmd, new Vector4(1, 1, 0, 0), mat, 0);       // 光线步进
                    if (m_Settings.blur)
                    {
                        Blitter.BlitCameraTexture(cmd, m_Vol, m_VolTemp, mat, 1);      // 横向模糊
                        Blitter.BlitCameraTexture(cmd, m_VolTemp, m_Vol, mat, 2);      // 纵向模糊
                    }
                    cmd.SetGlobalTexture(s_Result, m_Vol);
                    Blitter.BlitCameraTexture(cmd, m_CameraColor, m_Copy);
                    Blitter.BlitCameraTexture(cmd, m_Copy, m_CameraColor, mat,
                        m_Settings.output == Output.Composite ? 3 : 4);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            //#endregion

            public void Dispose() { m_Vol?.Release(); m_VolTemp?.Release(); m_Copy?.Release(); }
        }
    }
}
