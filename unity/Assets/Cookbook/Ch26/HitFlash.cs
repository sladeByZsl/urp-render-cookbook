// 案例 26.10：受击红屏。Volume 组件 + 一个用 Volume 权重驱动它的 MonoBehaviour。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Hit Flash", typeof(UniversalRenderPipeline))]
    public sealed class HitFlashVolume : VolumeComponent, IPostProcessComponent
    {
        public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);
        public ColorParameter color = new ColorParameter(new Color(0.75f, 0.02f, 0.02f), false, false, true);
        [Tooltip("血丝状边缘的噪声尺度")]
        public ClampedFloatParameter noiseScale = new ClampedFloatParameter(6f, 1f, 20f);
        [Tooltip("动画相位（运行时可由脚本递增；书中截图用固定值）")]
        public FloatParameter phase = new FloatParameter(0f);

        public bool IsActive() => intensity.value > 0f;
        public bool IsTileCompatible() => false;
    }

    public class HitFlashFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/HitFlash";
        protected override PostPassBase CreatePass(Material m) => new Pass(m);

        class Pass : SimplePostPass<HitFlashVolume>
        {
            static readonly int s_Color = Shader.PropertyToID("_HitColor");
            static readonly int s_Params = Shader.PropertyToID("_HitParams");   // x 强度, y 噪声尺度, z 相位
            public Pass(Material m) : base(m, "Ch26 Hit Flash") { }
            protected override void Apply(HitFlashVolume v, ref RenderingData rd)
            {
                material.SetColor(s_Color, v.color.value);
                material.SetVector(s_Params, new Vector4(v.intensity.value, v.noiseScale.value, v.phase.value, 0));
            }
        }
    }
}
