// 案例 26.5：径向模糊（冲刺/爆炸冲击感）。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    //#region volume
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Radial Blur", typeof(UniversalRenderPipeline))]
    public sealed class RadialBlurVolume : VolumeComponent, IPostProcessComponent
    {
        public Vector2Parameter center = new Vector2Parameter(new Vector2(0.5f, 0.5f));
        [Tooltip("每个像素向中心方向最多拖拽的比例")]
        public ClampedFloatParameter strength = new ClampedFloatParameter(0f, 0f, 1f);
        public ClampedIntParameter samples = new ClampedIntParameter(12, 4, 32);
        [Tooltip("中心这一圈半径内保持清晰（屏幕高度为 1）")]
        public ClampedFloatParameter clearRadius = new ClampedFloatParameter(0.1f, 0f, 0.5f);

        public bool IsActive() => strength.value > 0f;
        public bool IsTileCompatible() => false;
    }
    //#endregion

    public class RadialBlurFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/RadialBlur";
        protected override PostPassBase CreatePass(Material m) => new RadialBlurPass(m);
    }

    //#region pass
    class RadialBlurPass : SimplePostPass<RadialBlurVolume>
    {
        static readonly int s_Params = Shader.PropertyToID("_RadialParams");   // xy 中心, z 强度, w 采样数
        static readonly int s_ClearRadius = Shader.PropertyToID("_ClearRadius");
        public RadialBlurPass(Material m) : base(m, "Ch26 Radial Blur") { }

        protected override void Apply(RadialBlurVolume v, ref RenderingData renderingData)
        {
            var c = v.center.value;
            material.SetVector(s_Params, new Vector4(c.x, c.y, v.strength.value, v.samples.value));
            material.SetFloat(s_ClearRadius, v.clearRadius.value);
        }
    }
    //#endregion
}
