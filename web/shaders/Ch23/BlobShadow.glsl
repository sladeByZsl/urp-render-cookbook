// 案例 23.4：圆形 Blob 阴影（GLSL 版）。
// 一张贴在地面上的 Quad，用 UV 到中心的距离画一个柔和的圆斑，再用“相乘”混合压暗地面。
// 只有一次极便宜的片元计算，没有任何阴影贴图，是移动端大量单位时最常见的阴影方案。
Shader "Cookbook/Ch23/BlobShadow"
{
    SubShader
    {
        // 放在不透明物体之后、透明物体之前：地面已经画好，可以对它做相乘
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent-100" "IgnoreProjector"="True" }

        Pass
        {
            Name "Blob"
            Tags { "LightMode"="UniversalForward" }
            Blend DstColor Zero      // 结果 = 地面色 × 片元色，片元色为 1 时完全不影响地面
            ZWrite Off
            Offset -1, -1            // 往相机方向挪一点，避免与地面深度打架

            GLSLPROGRAM
            uniform vec4  _ShadowColor;
            uniform float _Strength;
            uniform float _Softness;

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy;
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                // d：0 在圆心，1 在 Quad 内切圆边缘
                float d = length(uv - 0.5) * 2.0;
                // 1 - smoothstep 做出中心实、边缘软的衰减；Softness 越大，实心区越小
                float mask = 1.0 - smoothstep(1.0 - _Softness, 1.0, d);
                mask *= mask;                               // 平方让过渡更接近真实半影
                vec3 c = mix(vec3(1, 1, 1), _ShadowColor.rgb, mask * _Strength);
                return vec4(c, 1);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
