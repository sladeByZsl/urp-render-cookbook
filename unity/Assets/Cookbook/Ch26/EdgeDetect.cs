// 案例 26.9：基于深度 + 法线的 Sobel 描边（屏幕空间描边）。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    //#region volume
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Edge Detect", typeof(UniversalRenderPipeline))]
    public sealed class EdgeDetectVolume : VolumeComponent, IPostProcessComponent
    {
        public ClampedFloatParameter intensity = new ClampedFloatParameter(0f, 0f, 1f);
        [Tooltip("采样间距（像素），越大线越粗")]
        public ClampedFloatParameter thickness = new ClampedFloatParameter(1f, 0.5f, 4f);
        [Tooltip("深度梯度 / 中心深度 超过它算边。越小越敏感")]
        public ClampedFloatParameter depthThreshold = new ClampedFloatParameter(0.15f, 0.001f, 1f);
        [Tooltip("法线梯度超过它算边。设到最大即“只用深度”")]
        public ClampedFloatParameter normalThreshold = new ClampedFloatParameter(1.5f, 0.05f, 4f);
        public ColorParameter edgeColor = new ColorParameter(new Color(0.05f, 0.05f, 0.08f), false, false, true);
        [Tooltip("0 = 线叠在原图上；1 = 只显示线（背景换成 backgroundColor）")]
        public ClampedFloatParameter edgesOnly = new ClampedFloatParameter(0f, 0f, 1f);
        public ColorParameter backgroundColor = new ColorParameter(new Color(0.95f, 0.93f, 0.88f), false, false, true);

        public bool IsActive() => intensity.value > 0f;
        public bool IsTileCompatible() => false;
    }
    //#endregion

    public class EdgeDetectFeature : PostFeatureBase
    {
        protected override string ShaderName => "Cookbook/Ch26/EdgeDetect";
        protected override PostPassBase CreatePass(Material m) => new Pass(m);

        //#region pass
        class Pass : SimplePostPass<EdgeDetectVolume>
        {
            static readonly int s_Params = Shader.PropertyToID("_EdgeParams");     // x 强度, y 粗细, z 深度阈值, w 法线阈值
            static readonly int s_EdgeColor = Shader.PropertyToID("_EdgeColor");
            static readonly int s_BgColor = Shader.PropertyToID("_EdgeBgColor");   // a = edgesOnly

            public Pass(Material m) : base(m, "Ch26 Edge Detect") { }

            // 告诉 URP：本 Pass 需要 _CameraDepthTexture 和 _CameraNormalsTexture。
            // Normal 会让 URP 额外跑一遍 DepthNormals 预渲染（前向路径下），这是这个效果的主要开销。
            public override ScriptableRenderPassInput RequiredInputs =>
                ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal;

            protected override void Apply(EdgeDetectVolume v, ref RenderingData rd)
            {
                material.SetVector(s_Params, new Vector4(v.intensity.value, v.thickness.value, v.depthThreshold.value, v.normalThreshold.value));
                material.SetColor(s_EdgeColor, v.edgeColor.value);
                var bg = v.backgroundColor.value; bg.a = v.edgesOnly.value;
                material.SetColor(s_BgColor, bg);
            }
        }
        //#endregion
    }
}
