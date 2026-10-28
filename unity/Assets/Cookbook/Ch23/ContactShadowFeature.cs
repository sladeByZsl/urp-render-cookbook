using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch23
{
    /// 案例 23.9：接触阴影（Contact Shadows）。
    /// 在深度预渲染之后，用一个全屏 Pass 从每个像素出发、沿主光方向在屏幕空间里步进几步，
    /// 检查有没有被深度缓冲里更靠前的表面挡住，结果写进一张 R8 的全屏纹理 _ContactShadowTexture。
    /// 接收物体的 Shader 再用屏幕 UV 读它，与阴影贴图的结果取最小值。
    /// 结构完全仿照 URP 14 自带的 ScreenSpaceShadows（Runtime/RendererFeatures/ScreenSpaceShadows.cs）。
    public class ContactShadowFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            [Tooltip("沿光线方向追踪的世界空间长度（米）。接触阴影只负责“贴脚”的那一小段")]
            public float length = 0.35f;
            [Range(4, 64)] public int steps = 16;
            [Tooltip("认为是“挡住”的最大深度差（米），超过它视为在物体背后穿过，不算遮挡")]
            public float thickness = 0.15f;
            [Tooltip("起点沿光方向的偏移，防止表面自己挡自己")]
            public float bias = 0.01f;
            [Range(0, 1)] public float intensity = 1f;
        }

        public Settings settings = new Settings();

        const string k_ShaderName = "Cookbook/Ch23/ContactShadowPass";
        Material m_Material;
        ContactShadowPass m_Pass;

        public override void Create()
        {
            m_Pass ??= new ContactShadowPass();
            // 与 URP 的屏幕空间阴影相同的时机：深度预渲染之后、不透明物体之前
            m_Pass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses + 1;
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            int mainLight = renderingData.lightData.mainLightIndex;
            if (mainLight < 0) return;
            if (m_Material == null)
            {
                var shader = Shader.Find(k_ShaderName);
                if (shader == null) return;
                m_Material = CoreUtils.CreateEngineMaterial(shader);
            }
            // 方向光的 forward 是光线前进方向，取反得到“指向光源”的 L
            Vector3 L = -renderingData.lightData.visibleLights[mainLight].localToWorldMatrix.GetColumn(2);
            m_Pass.Setup(settings, m_Material, L.normalized);
            renderer.EnqueuePass(m_Pass);
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
            CoreUtils.Destroy(m_Material);
        }

        //#region pass
        class ContactShadowPass : ScriptableRenderPass
        {
            static readonly int s_Params = Shader.PropertyToID("_ContactParams");
            static readonly int s_LightDir = Shader.PropertyToID("_ContactLightDir");
            readonly ProfilingSampler m_Sampler = new ProfilingSampler("ContactShadows");

            RTHandle m_Target;
            Material m_Material;
            Settings m_Settings;
            Vector3 m_LightDir;

            public void Setup(Settings s, Material material, Vector3 lightDir)
            {
                m_Settings = s; m_Material = material; m_LightDir = lightDir;
                // 声明需要深度纹理：URP 会因此安排 DepthPrepass，保证此时 _CameraDepthTexture 已就绪
                ConfigureInput(ScriptableRenderPassInput.Depth);
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                desc.graphicsFormat = RenderingUtils.SupportsGraphicsFormat(GraphicsFormat.R8_UNorm, FormatUsage.Linear | FormatUsage.Render)
                    ? GraphicsFormat.R8_UNorm : GraphicsFormat.B8G8R8A8_UNorm;
                RenderingUtils.ReAllocateIfNeeded(ref m_Target, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_ContactShadowTexture");
                cmd.SetGlobalTexture(m_Target.name, m_Target.nameID);
                ConfigureTarget(m_Target);
                ConfigureClear(ClearFlag.None, Color.white);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                // URP 14 里 renderingData.commandBuffer 是 internal，自己的 Feature 从池里借一个
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, m_Sampler))
                {
                    m_Material.SetVector(s_Params, new Vector4(m_Settings.length, m_Settings.steps, m_Settings.thickness, m_Settings.bias));
                    m_Material.SetVector(s_LightDir, new Vector4(m_LightDir.x, m_LightDir.y, m_LightDir.z, m_Settings.intensity));
                    // 源和目标是同一张图：Shader 根本不读 _BlitTexture，只借 Blitter 画一个全屏三角形
                    Blitter.BlitCameraTexture(cmd, m_Target, m_Target, m_Material, 0);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose() => m_Target?.Release();
        }
        //#endregion
    }
}
