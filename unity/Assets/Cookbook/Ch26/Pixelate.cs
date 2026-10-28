// 案例 26.7：像素化 + 调色板量化 + 有序抖动。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Pixelate", typeof(UniversalRenderPipeline))]
    public sealed class PixelateVolume : VolumeComponent, IPostProcessComponent
    {
        [Tooltip("一个“大像素”占多少屏幕像素；1 = 关闭")]
        public ClampedIntParameter pixelSize = new ClampedIntParameter(1, 1, 64);
        [Tooltip("每个通道保留几级颜色；0 = 不量化")]
        public ClampedIntParameter colorLevels = new ClampedIntParameter(0, 0, 32);
        [Tooltip("量化时叠加 4×4 Bayer 有序抖动的强度")]
        public ClampedFloatParameter dither = new ClampedFloatParameter(1f, 0f, 1f);

        public bool IsActive() => pixelSize.value > 1 || colorLevels.value > 0;
        public bool IsTileCompatible() => false;
    }

    public class PixelateFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/Pixelate";
        protected override PostPassBase CreatePass(Material m) => new Pass(m);

        class Pass : SimplePostPass<PixelateVolume>
        {
            static readonly int s_Params = Shader.PropertyToID("_PixelateParams");  // x 像素尺寸, y 色阶, z 抖动
            public Pass(Material m) : base(m, "Ch26 Pixelate") { }
            protected override void Apply(PixelateVolume v, ref RenderingData rd)
                => material.SetVector(s_Params, new Vector4(v.pixelSize.value, v.colorLevels.value, v.dither.value, 0));
        }
    }
}
