// 案例 26.2：可分离高斯模糊 + 降采样 + 乒乓 RT。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Gaussian Blur", typeof(UniversalRenderPipeline))]
    public sealed class GaussianBlurVolume : VolumeComponent, IPostProcessComponent
    {
        [Tooltip("采样间距（以低分辨率纹素为单位）。0 = 关闭")]
        public ClampedFloatParameter spread = new ClampedFloatParameter(0f, 0f, 3f);
        [Tooltip("水平+竖直 算一次迭代")]
        public ClampedIntParameter iterations = new ClampedIntParameter(2, 1, 8);
        [Tooltip("先缩小到 1/N 再模糊")]
        public ClampedIntParameter downsample = new ClampedIntParameter(2, 1, 8);

        public bool IsActive() => spread.value > 0f;
        public bool IsTileCompatible() => false;
    }

    public class GaussianBlurFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/GaussianBlur";
        protected override PostPassBase CreatePass(Material m) => new GaussianBlurPass(m);
    }

    //#region pass
    class GaussianBlurPass : PostPassBase
    {
        static readonly int s_Spread = Shader.PropertyToID("_Spread");
        const int PassH = 0, PassV = 1;

        RTHandle m_A, m_B;          // 两张低分辨率 RT，来回倒（乒乓）
        int m_Iterations, m_Downsample;

        public GaussianBlurPass(Material m) : base(m, "Ch26 Gaussian Blur") { }

        public override bool Prepare(VolumeStack stack, ref RenderingData renderingData)
        {
            var v = stack.GetComponent<GaussianBlurVolume>();
            if (v == null || !v.IsActive()) return false;
            material.SetFloat(s_Spread, v.spread.value);
            m_Iterations = v.iterations.value;
            m_Downsample = v.downsample.value;
            return true;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = ColorDesc(ref renderingData, m_Downsample);
            Alloc(ref m_A, desc, "_Ch26BlurA");
            Alloc(ref m_B, desc, "_Ch26BlurB");
        }

        protected override void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // 1) 降采样：双线性拷贝到小图，本身就相当于一次 2×2 盒式滤波
            Blitter.BlitCameraTexture(cmd, cameraColor, m_A, 0, true);
            // 2) 迭代：A →(水平)→ B →(竖直)→ A
            for (int i = 0; i < m_Iterations; i++)
            {
                Blitter.BlitCameraTexture(cmd, m_A, m_B, material, PassH);
                Blitter.BlitCameraTexture(cmd, m_B, m_A, material, PassV);
            }
            // 3) 放大回全分辨率（双线性），覆盖相机颜色
            Blitter.BlitCameraTexture(cmd, m_A, cameraColor, 0, true);
        }

        public override void Dispose()
        {
            Release(ref m_A);
            Release(ref m_B);
        }
    }
    //#endregion
}
