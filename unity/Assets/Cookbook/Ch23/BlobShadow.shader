// 案例 23.4：圆形 Blob 阴影。
// 一张贴在地面上的 Quad，用 UV 到中心的距离画一个柔和的圆斑，再用“相乘”混合压暗地面。
// 只有一次极便宜的片元计算，没有任何阴影贴图，是移动端大量单位时最常见的阴影方案。
Shader "Cookbook/Ch23/BlobShadow"
{
    Properties
    {
        _ShadowColor ("Shadow Color", Color) = (0.2, 0.22, 0.28, 1)
        _Strength ("Strength", Range(0, 1)) = 0.8
        _Softness ("Softness", Range(0.01, 1)) = 0.6
    }
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

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ShadowColor;
                half  _Strength;
                half  _Softness;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                UNITY_SETUP_INSTANCE_ID(v);
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                // d：0 在圆心，1 在 Quad 内切圆边缘
                half d = length(i.uv - 0.5) * 2.0;
                // 1 - smoothstep 做出中心实、边缘软的衰减；Softness 越大，实心区越小
                half mask = 1.0 - smoothstep(1.0 - _Softness, 1.0, d);
                mask *= mask;                               // 平方让过渡更接近真实半影
                half3 c = lerp(half3(1, 1, 1), _ShadowColor.rgb, mask * _Strength);
                return half4(c, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
