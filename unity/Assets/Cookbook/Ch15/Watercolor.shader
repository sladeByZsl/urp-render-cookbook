// 水彩感：颜料按“透射率^浓度”叠在纸上（Beer–Lambert 式减色），
// 用噪声扰动色阶边界模拟水渍晕开，边界和轮廓处颜料堆积变深，纸纹让颜料沉淀出颗粒感。
Shader "Cookbook/Ch15/Watercolor"
{
    Properties
    {
        _BaseColor ("Pigment Color", Color) = (0.85, 0.35, 0.3, 1)
        _ShadowPigment ("Shadow Pigment", Color) = (0.35, 0.35, 0.75, 1)
        [NoScaleOffset] _NoiseTex ("Noise (fBm)", 2D) = "gray" {}
        _PaperColor ("Paper Color", Color) = (0.97, 0.95, 0.9, 1)
        _PaperScale ("Paper Grain Scale", Float) = 3
        _Bands ("Wash Bands", Range(1, 5)) = 3
        _Wobble ("Edge Wobble", Range(0, 0.5)) = 0.18
        _Density ("Pigment Density", Range(0, 3)) = 1.1
        _EdgeDarken ("Edge Darkening", Range(0, 2)) = 0.8
        _Granulation ("Granulation", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _ShadowPigment, _PaperColor;
            float _PaperScale;
            half  _Bands, _Wobble, _Density, _EdgeDarken, _Granulation;
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

            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);

            //#region frag
            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                NprLight L = GetNprLight(i.positionWS, N);

                // 纸纹和水渍噪声都固定在画面上（纸不会跟着物体动）
                float2 suv = GetNormalizedScreenSpaceUV(i.positionCS) * float2(_ScreenParams.x / _ScreenParams.y, 1);
                half wash  = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, suv * 1.3).r - 0.5h;   // 低频：晕染
                half grain = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, suv * _PaperScale * 8).r; // 高频：纸纹

                // 1) 受光 + 噪声扰动，再分成几层“罩染”
                half light = saturate(L.ndotl) * L.shadow + wash * _Wobble;
                half f = saturate(light) * _Bands;
                half fr = frac(f);
                half tone = (floor(f) + smoothstep(0.35h, 0.65h, fr)) / _Bands;   // 0 = 最暗，1 = 最亮

                // 2) 色阶交界处颜料干后堆积（“水边线”）
                half edge = exp(-pow((fr - 0.5h) / 0.12h, 2)) * step(0.02h, f) * step(f, _Bands - 0.02h);

                // 3) 轮廓处的颜料堆积：N·V 越小越靠近轮廓，加噪声让边缘不规则
                half rim = smoothstep(0.55h, 0.95h, 1.0h - saturate(dot(N, V)) + wash * 0.4h);

                // 4) 浓度：暗处颜料多，再叠加边缘堆积和纸纹沉淀
                half density = _Density * lerp(0.25h, 1.0h, 1.0h - tone);
                density += (edge * 0.6h + rim) * _EdgeDarken;
                density *= lerp(1.0h, 0.6h + 0.8h * grain, _Granulation);

                // 5) 暗部换一种偏冷的颜料，然后按 Beer–Lambert：透射率 = 颜料色^浓度
                half3 pigment = lerp(_BaseColor.rgb, _BaseColor.rgb * _ShadowPigment.rgb * 1.6h, saturate(1.0h - tone) * 0.7h);
                half3 paper = _PaperColor.rgb * (0.94h + 0.06h * grain);
                half3 col = paper * pow(saturate(pigment), max(density, 0.0h));
                return half4(col, 1);
            }
            //#endregion
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
