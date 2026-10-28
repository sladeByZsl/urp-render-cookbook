// 色阶化漫反射：Lambert → step → smoothstep → Ramp 贴图，以及阴影色的几种给法。
Shader "Cookbook/Ch14/ToonRamp"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.95, 0.55, 0.4, 1)
        [KeywordEnum(Lambert, Step, Smooth, Texture)] _Ramp ("Ramp Mode", Float) = 2
        _Threshold ("Threshold (half-lambert)", Range(0, 1)) = 0.5
        _Softness ("Edge Softness", Range(0, 0.5)) = 0.03
        [NoScaleOffset] _RampTex ("Ramp Texture", 2D) = "white" {}
        _ShadeColor ("1st Shade Color", Color) = (0.55, 0.3, 0.38, 1)
        _ShadeColor2 ("2nd Shade Color", Color) = (0.32, 0.17, 0.3, 1)
        _Shade2Threshold ("2nd Shade Threshold", Range(0, 1)) = 0.25
        _Shade2Strength ("2nd Shade Strength", Range(0, 1)) = 0
        _AmbientStrength ("Ambient Strength", Range(0, 1)) = 0.35
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _ShadeColor, _ShadeColor2;
            half  _Threshold, _Softness, _Shade2Threshold, _Shade2Strength, _AmbientStrength;
        CBUFFER_END
        TEXTURE2D(_RampTex); SAMPLER(sampler_RampTex);
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ToonVert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _RAMP_LAMBERT _RAMP_STEP _RAMP_SMOOTH _RAMP_TEXTURE
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"

            //#region frag
            half4 frag(ToonVaryings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half3 N = normalize(i.normalWS);
                Light light = GetMainLight();
                half NoL = dot(N, light.direction);
                half halfLambert = NoL * 0.5 + 0.5;     // 0~1，比 saturate(NoL) 更适合当查表坐标

                half3 color;
            #if defined(_RAMP_LAMBERT)
                color = _BaseColor.rgb * saturate(NoL);                      // 对照：普通 Lambert
            #elif defined(_RAMP_TEXTURE)
                // Ramp 贴图：横向就是“明暗 → 颜色”的映射表，美术可以随意画色阶与色相
                half3 ramp = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, float2(clamp(halfLambert, 0.01, 0.99), 0.5)).rgb;
                color = _BaseColor.rgb * ramp;
            #else
              #if defined(_RAMP_STEP)
                half band = step(_Threshold, halfLambert);                   // 硬边：会有锯齿
              #else
                // 软一点的硬边：过渡宽度至少一个像素（fwidth = 这个量在相邻像素间的变化），硬边也不会出锯齿
                half band = ToonBand(halfLambert, _Threshold, max(_Softness, fwidth(halfLambert)));
              #endif
                // 亮部用固有色，暗部用美术指定的阴影色，而不是“固有色 × 0.5”
                color = lerp(_ShadeColor.rgb, _BaseColor.rgb, band);
                // 可选的第二层阴影：在更暗的位置再切一档
                half band2 = ToonBand(halfLambert, _Shade2Threshold, _Softness);
                color = lerp(lerp(color, _ShadeColor2.rgb, _Shade2Strength), color, band2);
            #endif
                color *= light.color;

                // 环境光：只取球谐的常数项（平均环境色），避免环境光把色块又“抹圆”
                color += SampleSH(half3(0, 0, 0)) * _BaseColor.rgb * _AmbientStrength;
                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // URP 自带的阴影 Pass 只在 _ALPHATEST_ON 时才读 _BaseMap，其余部分与材质无关，直接复用
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
