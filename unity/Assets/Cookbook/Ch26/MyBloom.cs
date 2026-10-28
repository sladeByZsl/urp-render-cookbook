// 案例 26.4：自制 Bloom —— 亮部提取（软阈值）→ 下采样金字塔 → 逐级上采样合并 → 叠加回画面。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    public enum BloomDebugView { None, Prefilter, BloomOnly }

    [Serializable] public sealed class BloomDebugViewParameter : VolumeParameter<BloomDebugView>
    {
        public BloomDebugViewParameter(BloomDebugView value, bool overrideState = false) : base(value, overrideState) { }
    }

    //#region volume
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/My Bloom", typeof(UniversalRenderPipeline))]
    public sealed class MyBloomVolume : VolumeComponent, IPostProcessComponent
    {
        [Tooltip("线性亮度超过它的部分才会泛光")]
        public MinFloatParameter threshold = new MinFloatParameter(1f, 0f);
        [Tooltip("软膝：阈值附近的过渡宽度（相对阈值的比例）")]
        public ClampedFloatParameter softKnee = new ClampedFloatParameter(0.5f, 0f, 1f);
        public MinFloatParameter intensity = new MinFloatParameter(0f, 0f);
        [Tooltip("上采样时低分辨率层所占比例，越大光晕越大越柔")]
        public ClampedFloatParameter scatter = new ClampedFloatParameter(0.7f, 0f, 1f);
        public ColorParameter tint = new ColorParameter(Color.white, false, false, true);
        public ClampedIntParameter maxIterations = new ClampedIntParameter(6, 1, 8);
        public BloomDebugViewParameter debugView = new BloomDebugViewParameter(BloomDebugView.None);

        public bool IsActive() => intensity.value > 0f;
        public bool IsTileCompatible() => false;
    }
    //#endregion

    public class MyBloomFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/MyBloom";
        protected override PostPassBase CreatePass(Material m) => new MyBloomPass(m);
    }

    class MyBloomPass : PostPassBase
    {
        static readonly int s_Params = Shader.PropertyToID("_BloomParams");      // x 阈值, y 膝宽, z scatter, w 强度
        static readonly int s_Tint = Shader.PropertyToID("_BloomTint");
        static readonly int s_DebugView = Shader.PropertyToID("_BloomDebugView");
        static readonly int s_LowMip = Shader.PropertyToID("_BloomLowMip");
        static readonly int s_BloomTex = Shader.PropertyToID("_BloomTex");
        const int PassPrefilter = 0, PassDown = 1, PassUp = 2, PassComposite = 3;
        const int MaxLevels = 8;

        readonly RTHandle[] m_Down = new RTHandle[MaxLevels];
        readonly RTHandle[] m_Up = new RTHandle[MaxLevels];
        RTHandle m_Temp;
        int m_MaxIterations, m_Levels;
        BloomDebugView m_Debug;

        public MyBloomPass(Material m) : base(m, "Ch26 My Bloom") { }

        public override bool Prepare(VolumeStack stack, ref RenderingData renderingData)
        {
            var v = stack.GetComponent<MyBloomVolume>();
            if (v == null || !v.IsActive()) return false;
            float threshold = v.threshold.value;
            material.SetVector(s_Params, new Vector4(threshold, threshold * v.softKnee.value, v.scatter.value, v.intensity.value));
            material.SetColor(s_Tint, v.tint.value);
            m_Debug = v.debugView.value;
            material.SetFloat(s_DebugView, (float)m_Debug);
            m_MaxIterations = v.maxIterations.value;
            return true;
        }

        //#region alloc
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 金字塔从半分辨率开始，一直缩到短边只剩几个像素或达到最大层数
            var desc = ColorDesc(ref renderingData, 2);
            int minSide = Mathf.Min(desc.width, desc.height);
            m_Levels = Mathf.Clamp(Mathf.FloorToInt(Mathf.Log(minSide, 2f)) - 1, 1, m_MaxIterations);
            for (int i = 0; i < m_Levels; i++)
            {
                Alloc(ref m_Down[i], desc, "_Ch26BloomDown" + i);
                if (i < m_Levels - 1) Alloc(ref m_Up[i], desc, "_Ch26BloomUp" + i);
                desc.width = Mathf.Max(1, desc.width / 2);
                desc.height = Mathf.Max(1, desc.height / 2);
            }
            Alloc(ref m_Temp, ColorDesc(ref renderingData), "_Ch26BloomTemp");
        }
        //#endregion

        //#region render
        protected override void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 1) 亮部提取 + 第一次降采样（全分辨率 → 1/2）
            Blitter.BlitCameraTexture(cmd, cameraColor, m_Down[0], material, PassPrefilter);

            // 2) 下采样金字塔：1/2 → 1/4 → 1/8 …（13 次采样的抗闪烁下采样核）
            for (int i = 1; i < m_Levels; i++)
                Blitter.BlitCameraTexture(cmd, m_Down[i - 1], m_Down[i], material, PassDown);

            // 3) 上采样：从最小层开始，每级 = lerp(本级下采样结果, 上一级的放大结果, scatter)
            for (int i = m_Levels - 2; i >= 0; i--)
            {
                RTHandle low = (i == m_Levels - 2) ? m_Down[i + 1] : m_Up[i + 1];
                cmd.SetGlobalTexture(s_LowMip, low);      // 每次迭代不同 → 用全局纹理逐次记录
                Blitter.BlitCameraTexture(cmd, m_Down[i], m_Up[i], material, PassUp);
            }

            // 4) 合成：相机颜色 + 泛光 × 强度 × 颜色
            RTHandle bloom = m_Debug == BloomDebugView.Prefilter ? m_Down[0]
                           : (m_Levels > 1 ? m_Up[0] : m_Down[0]);
            cmd.SetGlobalTexture(s_BloomTex, bloom);
            Blitter.BlitCameraTexture(cmd, cameraColor, m_Temp, material, PassComposite);
            Blitter.BlitCameraTexture(cmd, m_Temp, cameraColor);
        }
        //#endregion

        public override void Dispose()
        {
            for (int i = 0; i < MaxLevels; i++) { Release(ref m_Down[i]); Release(ref m_Up[i]); }
            Release(ref m_Temp);
        }
    }
}
