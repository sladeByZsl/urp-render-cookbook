// 膨胀 / 呼吸：沿某个方向把顶点推出去。
//   方向 = 网格法线：最简单，但硬边模型（立方体）的同一位置有多个法线不同的顶点，推开后会裂缝；
//   方向 = 从中心指向顶点：同一位置的顶点方向相同，硬边不会裂开（适合大致凸的形体）。
// 呼吸：振幅随时间做正弦，相位再加上沿 Y 的偏移，就成了一道从下往上走的“脉冲”。
Shader "Cookbook/Ch17/Inflate"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0.85, 0.45, 0.4, 1)
        _Amount ("Inflate Amount", Range(-0.2, 0.5)) = 0.08
        [KeywordEnum(Normal, Radial)] _Dir ("Push Direction", Float) = 0
        _PulseFreq ("Pulse Spatial Frequency", Float) = 0
        _Speed ("Breath Speed", Float) = 2
        _Phase ("Phase (for stills)", Float) = 1.5708
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #pragma shader_feature_local_vertex _DIR_NORMAL _DIR_RADIAL
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            float _Amount, _PulseFreq, _Speed, _Phase;
        CBUFFER_END
        #include "Assets/Cookbook/Ch17/VertexAnimCommon.hlsl"

        //#region deform
        void Deform(inout VAAttributes v)
        {
        #if defined(_DIR_RADIAL)
            float3 dir = normalize(v.positionOS.xyz);       // 同一位置 → 同一方向，硬边不裂
        #else
            float3 dir = v.normalOS;
        #endif
            // 呼吸：0..1 之间往复；_PulseFreq > 0 时不同高度相位不同，形成向上传播的脉冲
            float t = _Time.y * _Speed + _Phase;
            float breath = sin(t - v.positionOS.y * _PulseFreq) * 0.5 + 0.5;
            v.positionOS.xyz += dir * _Amount * breath;
            // 均匀膨胀不改变光滑表面的法线方向，这里保持原法线
        }
        //#endregion

        #include "Assets/Cookbook/Ch17/VertexAnimPasses.hlsl"
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex VAForwardVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            half4 frag(VAVaryings i) : SV_Target
            {
                return half4(VALighting(_BaseColor.rgb, normalize(i.normalWS), i.positionWS, 0.5h, 48.0h), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex VAShadowVert
            #pragma fragment VANullFrag
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex VADepthVert
            #pragma fragment VANullFrag
            ENDHLSL
        }
    }
}
