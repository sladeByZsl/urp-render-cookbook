// 案例 26.3：Kawase 模糊与 Dual Kawase 模糊。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    public enum KawaseMode { Kawase, DualKawase }

    // 枚举型参数要声明一个具体子类，Volume Inspector 才能正确序列化和绘制
    [Serializable] public sealed class KawaseModeParameter : VolumeParameter<KawaseMode>
    {
        public KawaseModeParameter(KawaseMode value, bool overrideState = false) : base(value, overrideState) { }
    }

    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Kawase Blur", typeof(UniversalRenderPipeline))]
    public sealed class KawaseBlurVolume : VolumeComponent, IPostProcessComponent
    {
        public KawaseModeParameter mode = new KawaseModeParameter(KawaseMode.DualKawase);
        [Tooltip("Kawase：迭代次数；Dual Kawase：金字塔层数")]
        public ClampedIntParameter iterations = new ClampedIntParameter(0, 0, 8);
        [Tooltip("采样偏移倍数")]
        public ClampedFloatParameter offset = new ClampedFloatParameter(1f, 0.5f, 3f);

        public bool IsActive() => iterations.value > 0;
        public bool IsTileCompatible() => false;
    }

    public class KawaseBlurFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/KawaseBlur";
        protected override PostPassBase CreatePass(Material m) => new KawaseBlurPass(m);
    }

    class KawaseBlurPass : PostPassBase
    {
        static readonly int s_Offset = Shader.PropertyToID("_KawaseOffset");
        const int PassKawase = 0, PassDown = 1, PassUp = 2;
        const int MaxLevels = 8;

        readonly RTHandle[] m_Pyramid = new RTHandle[MaxLevels + 1];
        RTHandle m_PingA, m_PingB;
        KawaseMode m_Mode;
        int m_Iterations;
        float m_Offset;

        public KawaseBlurPass(Material m) : base(m, "Ch26 Kawase Blur") { }

        public override bool Prepare(VolumeStack stack, ref RenderingData renderingData)
        {
            var v = stack.GetComponent<KawaseBlurVolume>();
            if (v == null || !v.IsActive()) return false;
            m_Mode = v.mode.value;
            m_Iterations = v.iterations.value;
            m_Offset = v.offset.value;
            return true;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (m_Mode == KawaseMode.Kawase)
            {
                var desc = ColorDesc(ref renderingData, 2);
                Alloc(ref m_PingA, desc, "_Ch26KawaseA");
                Alloc(ref m_PingB, desc, "_Ch26KawaseB");
            }
            else
            {
                // 第 i 层是 1/2^i 分辨率；第 0 层就是相机颜色本身，不分配
                for (int i = 1; i <= m_Iterations; i++)
                    Alloc(ref m_Pyramid[i], ColorDesc(ref renderingData, 1 << i), "_Ch26DualKawase" + i);
            }
        }

        protected override void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (m_Mode == KawaseMode.Kawase) RenderKawase(cmd);
            else RenderDualKawase(cmd);
        }

        //#region kawase
        void RenderKawase(CommandBuffer cmd)
        {
            Blitter.BlitCameraTexture(cmd, cameraColor, m_PingA, 0, true);
            var src = m_PingA; var dst = m_PingB;
            for (int i = 0; i < m_Iterations; i++)
            {
                // 每次迭代偏移不同：用 cmd.SetGlobalFloat 记录进命令缓冲。
                // 若用 material.SetFloat，所有迭代最终都会读到最后一次设置的值（见正文）
                cmd.SetGlobalFloat(s_Offset, (i + 0.5f) * m_Offset);
                Blitter.BlitCameraTexture(cmd, src, dst, material, PassKawase);
                (src, dst) = (dst, src);
            }
            Blitter.BlitCameraTexture(cmd, src, cameraColor, 0, true);
        }
        //#endregion

        //#region dual
        void RenderDualKawase(CommandBuffer cmd)
        {
            cmd.SetGlobalFloat(s_Offset, m_Offset);
            // 下行：全分辨率 → 1/2 → 1/4 …，每一步用 5 次采样的 Down 核
            RTHandle prev = cameraColor;
            for (int i = 1; i <= m_Iterations; i++)
            {
                Blitter.BlitCameraTexture(cmd, prev, m_Pyramid[i], material, PassDown);
                prev = m_Pyramid[i];
            }
            // 上行：逐级放大回去，每一步用 8 次采样的 Up 核，最后一步直接写回相机颜色
            for (int i = m_Iterations - 1; i >= 0; i--)
            {
                RTHandle dst = i == 0 ? cameraColor : m_Pyramid[i];
                Blitter.BlitCameraTexture(cmd, m_Pyramid[i + 1], dst, material, PassUp);
            }
        }
        //#endregion

        public override void Dispose()
        {
            Release(ref m_PingA);
            Release(ref m_PingB);
            for (int i = 0; i < m_Pyramid.Length; i++) Release(ref m_Pyramid[i]);
        }
    }
}
