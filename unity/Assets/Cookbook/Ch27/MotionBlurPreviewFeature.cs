using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch27
{
    /// 27.17 节配图用：在编辑模式下复现 URP 的相机运动模糊。
    /// URP 14 的 PostProcessPass 里有一行 `useMotionBlur = useMotionBlur && Application.isPlaying;`，
    /// 不在 Play 模式时 Motion Blur 一律关闭。这个 Feature 直接调用 URP 自带的
    /// Hidden/Universal Render Pipeline/CameraMotionBlur.shader，参数含义与 MotionBlur Volume 完全一致，
    /// 只是“上一帧的 VP 矩阵”由外部指定。顺带也演示了这个 Shader 需要哪些输入。
    public class MotionBlurPreviewFeature : ScriptableRendererFeature
    {
        [Tooltip("只对这台相机生效（为空则对所有 Game 相机生效）")]
        public Camera targetCamera;
        [Tooltip("上一帧的 GPU 视图投影矩阵：GL.GetGPUProjectionMatrix(P, true) * V")]
        public Matrix4x4 previousViewProj = Matrix4x4.identity;
        [Range(0f, 1f)] public float intensity = 0.5f;
        [Range(0f, 0.2f)] public float clamp = 0.05f;
        [Tooltip("0 = Low（2×2 次采样）  1 = Medium（3×2）  2 = High（4×2），对应 Shader 的三个 Pass")]
        [Range(0, 2)] public int quality = 2;

        Material m_Material;
        BlurPass m_Pass;

        public override void Create()
        {
            m_Pass ??= new BlurPass();
            m_Pass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;   // 与 URP 一样：在色调映射之前，作用于 HDR 颜色
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            var cam = renderingData.cameraData.camera;
            if (cam.cameraType != CameraType.Game || (targetCamera != null && cam != targetCamera) || intensity <= 0f) return;
            if (m_Material == null)
            {
                var shader = Shader.Find("Hidden/Universal Render Pipeline/CameraMotionBlur");
                if (shader == null) return;
                m_Material = CoreUtils.CreateEngineMaterial(shader);
            }
            m_Pass.Setup(this, m_Material);
            renderer.EnqueuePass(m_Pass);
        }

        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_Pass.source = renderer.cameraColorTargetHandle;   // URP 14：只能在这里（而不是 AddRenderPasses）取颜色目标
        }

        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
            CoreUtils.Destroy(m_Material);
        }

        class BlurPass : ScriptableRenderPass
        {
            static readonly int s_ViewProjM = Shader.PropertyToID("_ViewProjM");
            static readonly int s_PrevViewProjM = Shader.PropertyToID("_PrevViewProjM");
            static readonly int s_Intensity = Shader.PropertyToID("_Intensity");
            static readonly int s_Clamp = Shader.PropertyToID("_Clamp");
            static readonly int s_SourceSize = Shader.PropertyToID("_SourceSize");
            readonly ProfilingSampler m_Sampler = new ProfilingSampler("MotionBlurPreview");

            public RTHandle source;
            RTHandle m_Temp;
            MotionBlurPreviewFeature m_Owner;
            Material m_Material;

            public void Setup(MotionBlurPreviewFeature owner, Material material)
            {
                m_Owner = owner; m_Material = material;
                ConfigureInput(ScriptableRenderPassInput.Depth);   // 速度由深度重建世界坐标后算出
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthBufferBits = 0;
                desc.msaaSamples = 1;
                RenderingUtils.ReAllocateIfNeeded(ref m_Temp, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_MotionBlurPreviewTemp");
            }

            //#region execute
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                ref var cameraData = ref renderingData.cameraData;
                var vp = GL.GetGPUProjectionMatrix(cameraData.GetProjectionMatrix(), true) * cameraData.GetViewMatrix();
                m_Material.SetMatrix(s_ViewProjM, vp);
                m_Material.SetMatrix(s_PrevViewProjM, m_Owner.previousViewProj);
                m_Material.SetFloat(s_Intensity, m_Owner.intensity);
                m_Material.SetFloat(s_Clamp, m_Owner.clamp);

                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, m_Sampler))
                {
                    var d = cameraData.cameraTargetDescriptor;
                    cmd.SetGlobalVector(s_SourceSize, new Vector4(d.width, d.height, 1f / d.width, 1f / d.height));
                    Blitter.BlitCameraTexture(cmd, source, m_Temp, m_Material, m_Owner.quality);
                    Blitter.BlitCameraTexture(cmd, m_Temp, source);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            //#endregion

            public void Dispose() => m_Temp?.Release();
        }
    }
}
