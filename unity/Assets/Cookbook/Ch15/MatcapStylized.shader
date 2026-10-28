// Matcap（材质捕获）：把“一个球在某种光照下的样子”存成贴图，用观察空间法线去查表。
// 修正了透视畸变（以视线方向为基准建立局部坐标系），并可选地叠加场景阴影。
Shader "Cookbook/Ch15/MatcapStylized"
{
    Properties
    {
        [NoScaleOffset] _MatCap ("MatCap", 2D) = "gray" {}
        _BaseColor ("Tint", Color) = (1, 1, 1, 1)
        [Toggle] _PerspectiveFix ("Perspective Correction", Float) = 1
        _ShadowStrength ("Receive Shadow Strength", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            float _PerspectiveFix;
            half  _ShadowStrength;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex NprVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"

            TEXTURE2D(_MatCap); SAMPLER(sampler_MatCap);

            //#region matcap-uv
            float2 MatcapUV(float3 positionWS, float3 normalWS)
            {
                float3 normalVS = normalize(TransformWorldToViewDir(normalWS));
                // 朴素做法：直接取观察空间法线的 xy
                float2 naive = normalVS.xy;

                // 修正：以“从该点指向相机”的方向 V 为 z 轴，重新构造 x/y 轴，
                // 等于把每个像素都当成“正对相机”的那一点来查表，画面边缘不再被拉扯
                float3 V = normalize(-TransformWorldToView(positionWS));   // 观察空间里相机在原点
                float3 up = normalize(float3(0, 1, 0) - V * V.y);          // 把世界“上”投影到垂直于 V 的平面
                float3 right = cross(up, V);
                float2 corrected = float2(dot(normalVS, right), dot(normalVS, up));

                float2 n = lerp(naive, corrected, _PerspectiveFix);
                return n * 0.49 + 0.5;    // 0.49 而非 0.5：避开贴图最外圈的边缘像素
            }
            //#endregion

            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                half3 col = SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap, MatcapUV(i.positionWS, N)).rgb * _BaseColor.rgb;
                // Matcap 不认识场景里的灯，阴影只能“乘”上去：这是风格化里常见的折中
                NprLight L = GetNprLight(i.positionWS, N);
                col *= lerp(1.0h, L.shadow, _ShadowStrength);
                return half4(col, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex NprShadowVert
            #pragma fragment NprNullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex NprDepthVert
            #pragma fragment NprNullFrag
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }
    }
}
