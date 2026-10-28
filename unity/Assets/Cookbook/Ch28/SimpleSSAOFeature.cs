// 案例 28.4：简化版 SSAO 的 Renderer Feature。
// 两种接入方式：
//   IntoLighting      —— 像 URP 自带 SSAO 一样，在不透明物体之前算好 AO，作为 _ScreenSpaceOcclusionTexture
//                        交给 Lit 等着色器，只压暗间接光（以及少量直接光）；
//   MultiplyAfterOpaque —— 不透明物体画完后直接把 AO 乘到颜色上（对应 URP SSAO 的 After Opaque 选项），
//                        便宜、对自定义 Shader 也生效，但直接光也会被压暗。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch28
{
    public class SimpleSSAOFeature : ScriptableRendererFeature
    {
        public enum Mode { IntoLighting, MultiplyAfterOpaque, ShowAO }

        [System.Serializable]
        public class Settings
        {
            public Material material;            // Cookbook/Ch28/SimpleSSAO
            public Mode mode = Mode.IntoLighting;
            public bool blur = true;
            public bool halfResolution = false;
            [Range(0, 1)] public float directLightingStrength = 0.25f;
        }
        public Settings settings = new Settings();

        SSAOPass m_Pass;

        public override void Create() { m_Pass = new SSAOPass(); }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var camType = renderingData.cameraData.cameraType;
            if (settings.material == null || camType == CameraType.Preview || camType == CameraType.Reflection)
                return;
            //#region event
            // 进光照：必须在不透明物体之前，且要等深度/法线预通道画完（+1 与 URP 自带 SSAO 一致）
            m_Pass.renderPassEvent = settings.mode == Mode.IntoLighting
                ? RenderPassEvent.AfterRenderingPrePasses + 1
                : RenderPassEvent.AfterRenderingOpaques;
            // 要法线：Forward 路径下这会让 URP 执行 DepthNormals 预通道
            m_Pass.ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
            //#endregion
            m_Pass.Setup(settings);
            renderer.EnqueuePass(m_Pass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_Pass.SetCameraColor(renderer.cameraColorTargetHandle);
        }

        protected override void Dispose(bool disposing) { m_Pass?.Dispose(); }

        class SSAOPass : ScriptableRenderPass
        {
            static readonly int s_TexelSize = Shader.PropertyToID("_SSAOTexelSize");
            static readonly int s_Result = Shader.PropertyToID("_SSAOResult");
            static readonly int s_URPOcclusionTex = Shader.PropertyToID("_ScreenSpaceOcclusionTexture");
            static readonly int s_URPOcclusionParam = Shader.PropertyToID("_AmbientOcclusionParam");
            const string k_URPKeyword = "_SCREEN_SPACE_OCCLUSION";   // ShaderKeywordStrings.ScreenSpaceOcclusion

            Settings m_Settings;
            RTHandle m_CameraColor, m_AO, m_AOTemp, m_ColorCopy;

            public SSAOPass() { profilingSampler = new ProfilingSampler("SimpleSSAO"); }
            public void Setup(Settings s) { m_Settings = s; }
            public void SetCameraColor(RTHandle h) { m_CameraColor = h; }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.msaaSamples = 1;
                desc.depthBufferBits = 0;
                var aoDesc = desc;
                if (m_Settings.halfResolution) { aoDesc.width /= 2; aoDesc.height /= 2; }
                aoDesc.colorFormat = RenderTextureFormat.ARGB32;   // AO 只要 8 位精度
                RenderingUtils.ReAllocateIfNeeded(ref m_AO, aoDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SimpleSSAO");
                RenderingUtils.ReAllocateIfNeeded(ref m_AOTemp, aoDesc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_SimpleSSAOTemp");
                if (m_Settings.mode != Mode.IntoLighting)
                    RenderingUtils.ReAllocateIfNeeded(ref m_ColorCopy, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_SimpleSSAOColor");
                ConfigureTarget(m_AO);
            }

            //#region execute
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var mat = m_Settings.material;
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, profilingSampler))
                {
                    int w = m_AO.rt.width, h = m_AO.rt.height;
                    mat.SetVector(s_TexelSize, new Vector4(1f / w, 1f / h, w, h));

                    // 1) AO：没有输入纹理，直接画全屏三角形到 m_AO
                    CoreUtils.SetRenderTarget(cmd, m_AO);
                    Blitter.BlitTexture(cmd, new Vector4(1, 1, 0, 0), mat, 0);
                    // 2) 可分离双边模糊：AO → Temp（横）→ AO（竖）
                    if (m_Settings.blur)
                    {
                        Blitter.BlitCameraTexture(cmd, m_AO, m_AOTemp, mat, 1);
                        Blitter.BlitCameraTexture(cmd, m_AOTemp, m_AO, mat, 2);
                    }

                    if (m_Settings.mode == Mode.IntoLighting)
                    {
                        // 3a) 按 URP 的约定把结果交给光照：纹理 + 关键字 + 参数（w = 直接光受 AO 影响的比例）
                        cmd.SetGlobalTexture(s_URPOcclusionTex, m_AO);
                        cmd.SetGlobalVector(s_URPOcclusionParam, new Vector4(1, 0, 0, m_Settings.directLightingStrength));
                        CoreUtils.SetKeyword(cmd, k_URPKeyword, true);
                    }
                    else
                    {
                        // 3b) 直接乘到相机颜色上（或只显示 AO）
                        cmd.SetGlobalTexture(s_Result, m_AO);
                        Blitter.BlitCameraTexture(cmd, m_CameraColor, m_ColorCopy);
                        Blitter.BlitCameraTexture(cmd, m_ColorCopy, m_CameraColor, mat, m_Settings.mode == Mode.ShowAO ? 4 : 3);
                    }
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                // 关键字是全局状态，用完一定要关，否则会“漏”到下一台相机
                if (m_Settings != null && m_Settings.mode == Mode.IntoLighting)
                    CoreUtils.SetKeyword(cmd, k_URPKeyword, false);
            }
            //#endregion

            public void Dispose()
            {
                m_AO?.Release(); m_AOTemp?.Release(); m_ColorCopy?.Release();
            }
        }
    }
}
