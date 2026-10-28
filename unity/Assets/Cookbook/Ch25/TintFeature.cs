// 案例 25.1 / 25.2：一个完整、可直接用于项目的全屏效果 Renderer Feature（URP 14 写法）。
// 结构：Feature（资源与入队） + Pass（RTHandle 与绘制）。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch25
{
    //#region feature
    public class TintFeature : ScriptableRendererFeature
    {
        [System.Serializable]
        public class Settings
        {
            public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
            public Color tint = Color.white;
            [Range(0, 1)] public float invert = 1f;
            [Range(0, 1)] public float desaturate = 0f;
        }

        public Settings settings = new Settings();
        // 在 Inspector 里拖入 Cookbook/Ch25/Tint。直接引用能保证打包时 Shader 不被剔除；
        // 留空时退回 Shader.Find（只在编辑器或 Shader 已被别处引用时可靠）。
        public Shader shader;

        Material m_Material;
        TintPass m_Pass;

        // Create 在 OnEnable、以及 Inspector 每次改值（OnValidate）时都会被调用，
        // 所以这里必须先清理上一次创建的东西，否则每改一次参数就泄漏一份材质和 RT。
        public override void Create()
        {
            m_Pass?.Dispose();
            CoreUtils.Destroy(m_Material);

            if (shader == null) shader = Shader.Find("Cookbook/Ch25/Tint");
            m_Material = shader != null ? CoreUtils.CreateEngineMaterial(shader) : null;
            m_Pass = new TintPass(m_Material);
        }

        // 每个相机、每帧调用一次：决定这一帧要不要把 Pass 放进队列
        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (m_Material == null) return;
            var camType = renderingData.cameraData.cameraType;
            // 材质球预览、反射探针烘焙用的相机不需要全屏效果
            if (camType == CameraType.Preview || camType == CameraType.Reflection) return;

            m_Pass.renderPassEvent = settings.passEvent;
            m_Pass.Setup(settings);
            renderer.EnqueuePass(m_Pass);
        }

        // 相机的颜色/深度目标在这里才已分配好；在 AddRenderPasses 里取会报错
        public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
        {
            m_Pass.SetTarget(renderer.cameraColorTargetHandle, renderer.cameraDepthTargetHandle);
        }

        // Renderer 被销毁（切换管线资产、改 Renderer 列表、退出）时调用
        protected override void Dispose(bool disposing)
        {
            m_Pass?.Dispose();
            CoreUtils.Destroy(m_Material);
        }
    }
    //#endregion

    //#region pass
    class TintPass : ScriptableRenderPass
    {
        static readonly int s_TintColor = Shader.PropertyToID("_TintColor");
        static readonly int s_Invert = Shader.PropertyToID("_Invert");
        static readonly int s_Desaturate = Shader.PropertyToID("_Desaturate");

        readonly Material m_Material;
        RTHandle m_CameraColor, m_CameraDepth;   // 借来的，不归我们释放
        RTHandle m_Temp;                         // 自己分配的，Dispose 里释放

        public TintPass(Material material)
        {
            m_Material = material;
            profilingSampler = new ProfilingSampler("Ch25 Tint");   // Frame Debugger 里显示的名字
        }

        public void Setup(TintFeature.Settings s)
        {
            // 这些值在一帧内不变，直接写材质即可
            m_Material.SetColor(s_TintColor, s.tint);
            m_Material.SetFloat(s_Invert, s.invert);
            m_Material.SetFloat(s_Desaturate, s.desaturate);
        }

        public void SetTarget(RTHandle color, RTHandle depth)
        {
            m_CameraColor = color;
            m_CameraDepth = depth;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 临时 RT 和相机颜色同尺寸、同格式（HDR 时是浮点格式），但不要 MSAA、不要深度
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            RenderingUtils.ReAllocateIfNeeded(ref m_Temp, desc, FilterMode.Bilinear,
                TextureWrapMode.Clamp, name: "_Ch25TintTemp");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // 不能边读边写同一张纹理：先“相机颜色 → 临时 RT（经过材质）”，再拷回
                Blitter.BlitCameraTexture(cmd, m_CameraColor, m_Temp, m_Material, 0);
                Blitter.BlitCameraTexture(cmd, m_Temp, m_CameraColor);
                // BlitCameraTexture 只绑定了颜色。URP 以为相机的颜色+深度还绑着，
                // 后面的天空盒/透明物体会直接画，所以由我们把深度一起恢复回去。
                CoreUtils.SetRenderTarget(cmd, m_CameraColor, m_CameraDepth);
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
