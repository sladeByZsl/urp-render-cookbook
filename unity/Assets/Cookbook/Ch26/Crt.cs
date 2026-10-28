// 案例 26.8：CRT 显示器——屏幕弯曲、扫描线、荧光粉栅格、边缘暗角、轻微色差与闪烁。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/CRT", typeof(UniversalRenderPipeline))]
    public sealed class CrtVolume : VolumeComponent, IPostProcessComponent
    {
        [Tooltip("总开关强度，0 = 关闭")]
        public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);
        public ClampedFloatParameter curvature = new ClampedFloatParameter(0.12f, 0f, 0.5f);
        [Tooltip("模拟的扫描线行数")]
        public ClampedFloatParameter lineCount = new ClampedFloatParameter(240f, 60f, 1080f);
        public ClampedFloatParameter scanlineStrength = new ClampedFloatParameter(0.5f, 0f, 1f);
        [Tooltip("RGB 荧光粉栅格强度")]
        public ClampedFloatParameter maskStrength = new ClampedFloatParameter(0.35f, 0f, 1f);
        public ClampedFloatParameter flicker = new ClampedFloatParameter(0.03f, 0f, 0.2f);

        public bool IsActive() => intensity.value > 0f;
        public bool IsTileCompatible() => false;
    }

    public class CrtFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/Crt";
        protected override PostPassBase CreatePass(Material m) => new Pass(m);

        class Pass : SimplePostPass<CrtVolume>
        {
            static readonly int s_Params0 = Shader.PropertyToID("_CrtParams0");   // x 强度, y 弯曲, z 行数, w 扫描线强度
            static readonly int s_Params1 = Shader.PropertyToID("_CrtParams1");   // x 栅格强度, y 闪烁
            public Pass(Material m) : base(m, "Ch26 CRT") { }
            protected override void Apply(CrtVolume v, ref RenderingData rd)
            {
                material.SetVector(s_Params0, new Vector4(v.intensity.value, v.curvature.value, v.lineCount.value, v.scanlineStrength.value));
                material.SetVector(s_Params1, new Vector4(v.maskStrength.value, v.flicker.value, 0, 0));
            }
        }
    }
}
