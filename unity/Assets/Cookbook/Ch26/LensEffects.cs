// 案例 26.6：两个“镜头类”效果——色差（Chromatic Aberration）与暗角（Vignette）。
// 各自独立的 Volume + Feature，演示多个自定义后处理如何叠加与排序。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    //#region volumes
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/My Chromatic Aberration", typeof(UniversalRenderPipeline))]
    public sealed class MyChromaticAberration : VolumeComponent, IPostProcessComponent
    {
        public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);
        [Tooltip("沿径向分几段采样；3 = 只取 RGB 三次，越多色散越平滑")]
        public ClampedIntParameter samples = new ClampedIntParameter(6, 3, 16);
        public bool IsActive() => intensity.value > 0f;
        public bool IsTileCompatible() => false;
    }

    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/My Vignette", typeof(UniversalRenderPipeline))]
    public sealed class MyVignette : VolumeComponent, IPostProcessComponent
    {
        public ColorParameter color = new ColorParameter(Color.black, false, false, true);
        public Vector2Parameter center = new Vector2Parameter(new Vector2(0.5f, 0.5f));
        public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);
        public ClampedFloatParameter smoothness = new ClampedFloatParameter(0.5f, 0.05f, 1f);
        [Tooltip("勾选后按屏幕宽高比修正成正圆")]
        public BoolParameter rounded = new BoolParameter(false);
        public bool IsActive() => intensity.value > 0f;
        public bool IsTileCompatible() => false;
    }
    //#endregion

    public class MyChromaticAberrationFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/MyChromaticAberration";
        protected override PostPassBase CreatePass(Material m) => new Pass(m);

        class Pass : SimplePostPass<MyChromaticAberration>
        {
            static readonly int s_Params = Shader.PropertyToID("_CAParams");
            public Pass(Material m) : base(m, "Ch26 Chromatic Aberration") { }
            protected override void Apply(MyChromaticAberration v, ref RenderingData rd)
                => material.SetVector(s_Params, new Vector4(v.intensity.value, v.samples.value, 0, 0));
        }
    }

    public class MyVignetteFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/MyVignette";
        protected override PostPassBase CreatePass(Material m) => new Pass(m);

        class Pass : SimplePostPass<MyVignette>
        {
            static readonly int s_Color = Shader.PropertyToID("_VignetteColor");
            static readonly int s_Params = Shader.PropertyToID("_VignetteParams");  // xy 中心, z 强度, w 柔和度
            static readonly int s_Rounded = Shader.PropertyToID("_VignetteRounded");
            public Pass(Material m) : base(m, "Ch26 Vignette") { }
            protected override void Apply(MyVignette v, ref RenderingData rd)
            {
                material.SetColor(s_Color, v.color.value);
                var c = v.center.value;
                material.SetVector(s_Params, new Vector4(c.x, c.y, v.intensity.value, v.smoothness.value));
                material.SetFloat(s_Rounded, v.rounded.value ? 1f : 0f);
            }
        }
    }
}
