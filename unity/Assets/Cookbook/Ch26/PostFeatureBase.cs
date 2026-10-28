// 26.3 节：把案例 26.1 里每个后处理都要重复的部分抽成两个基类。
//   PostFeatureBase —— 管 Shader→材质、跳过不该处理的相机、按 Volume 是否启用决定入队、Dispose。
//   PostPassBase    —— 管相机目标、ProfilingScope、命令缓冲、RT 分配工具、执行后恢复渲染目标。
// 每个具体效果只需写：一个 VolumeComponent、一个几行的 Feature、一个只关心“怎么画”的 Pass。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    //#region feature-base
    public abstract class PostFeatureBase : ScriptableRendererFeature
    {
        public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        [Tooltip("留空则按 ShaderName 查找；正式项目请直接拖入，保证打包时 Shader 不被剔除")]
        public Shader shader;

        protected abstract string ShaderName { get; }
        protected abstract PostPassBase CreatePass(Material material);

        Material m_Material;
        PostPassBase m_Pass;

        public override void Create()
        {
            Dispose(true);
            if (shader == null) shader = Shader.Find(ShaderName);
            if (shader == null) { Debug.LogWarning($"{name}: 找不到 Shader {ShaderName}"); return; }
            m_Material = CoreUtils.CreateEngineMaterial(shader);
            m_Pass = CreatePass(m_Material);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (m_Pass == null) return;
            ref var cameraData = ref renderingData.cameraData;
            if (cameraData.cameraType == CameraType.Preview || cameraData.cameraType == CameraType.Reflection) return;
            if (!cameraData.postProcessEnabled) return;

            // Prepare：读 VolumeStack、写材质常量；返回 false 表示本帧无效果
            if (!m_Pass.Prepare(VolumeManager.instance.stack, ref renderingData)) return;

            m_Pass.renderPassEvent = passEvent;
            m_Pass.ConfigureInput(m_Pass.RequiredInputs);   // 深度/法线等输入必须在入队前声明
            renderer.EnqueuePass(m_Pass);
        }

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
    }
    //#endregion

    //#region pass-base
    public abstract class PostPassBase : ScriptableRenderPass
    {
        protected readonly Material material;
        protected RTHandle cameraColor, cameraDepth;

        protected PostPassBase(Material material, string profilerName)
        {
            this.material = material;
            profilingSampler = new ProfilingSampler(profilerName);
        }

        public virtual ScriptableRenderPassInput RequiredInputs => ScriptableRenderPassInput.None;

        public abstract bool Prepare(VolumeStack stack, ref RenderingData renderingData);

        // 真正的绘制：source 就是相机颜色，结果也要写回它
        protected abstract void Render(CommandBuffer cmd, ref RenderingData renderingData);

        public void SetTarget(RTHandle color, RTHandle depth) { cameraColor = color; cameraDepth = depth; }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                Render(cmd, ref renderingData);
                CoreUtils.SetRenderTarget(cmd, cameraColor, cameraDepth);   // 还给 URP 一个“原样”的目标
            }
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public virtual void Dispose() { }

        // ---------- 工具 ----------
        /// 相机颜色同格式、去掉 MSAA 与深度、按 downsample 缩小的描述符
        protected static RenderTextureDescriptor ColorDesc(ref RenderingData renderingData, int downsample = 1)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;
            desc.width = Mathf.Max(1, desc.width / downsample);
            desc.height = Mathf.Max(1, desc.height / downsample);
            return desc;
        }

        protected static void Alloc(ref RTHandle handle, in RenderTextureDescriptor desc, string name,
            FilterMode filter = FilterMode.Bilinear)
        {
            RenderingUtils.ReAllocateIfNeeded(ref handle, desc, filter, TextureWrapMode.Clamp, name: name);
        }

        protected static void Release(ref RTHandle handle)
        {
            handle?.Release();
            handle = null;
        }
    }
    //#endregion

    //#region simple-pass
    /// 最常见的“单 Pass 全屏效果”：相机颜色 →(材质)→ 临时 RT → 拷回相机颜色。
    public abstract class SimplePostPass<T> : PostPassBase where T : VolumeComponent, IPostProcessComponent
    {
        RTHandle m_Temp;

        protected SimplePostPass(Material m, string name) : base(m, name) { }

        /// 把 Volume 参数写进材质
        protected abstract void Apply(T volume, ref RenderingData renderingData);

        public override bool Prepare(VolumeStack stack, ref RenderingData renderingData)
        {
            var v = stack.GetComponent<T>();
            if (v == null || !v.IsActive()) return false;
            Apply(v, ref renderingData);
            return true;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            Alloc(ref m_Temp, ColorDesc(ref renderingData), "_Ch26Temp_" + typeof(T).Name);
        }

        protected override void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            Blitter.BlitCameraTexture(cmd, cameraColor, m_Temp, material, 0);
            Blitter.BlitCameraTexture(cmd, m_Temp, cameraColor);
        }

        public override void Dispose() => Release(ref m_Temp);
    }
    //#endregion
}
