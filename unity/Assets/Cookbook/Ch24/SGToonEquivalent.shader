// 第 24 章：与“Unlit Graph + Custom Function 卡通光照”逐节点等价的手写 Shader。
// 用途有两个：
//   1) 让 Custom Function 用到的 .hlsl 在普通 Shader 里真实编译一遍（_float 和 _half 两套都调用到）；
//   2) 渲染书中的效果图（Shader Graph 资源无法在批处理里手写生成）。
// SHADERGRAPH_PREVIEW 在这里被声明成一个本地关键字，只是为了把“预览分支”也编译、也能拍出来看，
// 真正的 Shader Graph 不需要也不应该这样做。
Shader "Cookbook/Ch24/SGToonEquivalent"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.95, 0.6, 0.45, 1)
        _ShadowTint ("Shadow Tint", Color) = (0.45, 0.4, 0.65, 1)
        _Steps ("Steps", Range(1, 6)) = 3
        _Smooth ("Smooth", Range(0, 0.5)) = 0.08
        [HDR] _RimColor ("Rim Color", Color) = (1, 0.95, 0.85, 1)
        _RimPower ("Rim Power", Range(0.5, 8)) = 4
        [Toggle] _UseHalf ("调用 _half 版本", Float) = 0
        [Toggle] _AddLights ("Additional Lights", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half4 _ShadowTint;
            half  _Steps;
            half  _Smooth;
            half4 _RimColor;
            half  _RimPower;
            half  _UseHalf;
            half  _AddLights;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "Universal Forward"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // —— 这几行就是在 Unlit Graph 的 Blackboard 里要手动加的 Keyword ——
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma shader_feature_local _ SHADERGRAPH_PREVIEW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Cookbook/Ch24/CustomLighting.hlsl"
            #include "Assets/Cookbook/Ch24/StylizedFunctions.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; float3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS; o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            //#region graph
            half4 frag(Varyings i) : SV_Target
            {
                // [Position 节点 World] [Normal Vector 节点 World] [View Direction 节点 World] [Screen Position 节点 Default]
                float3 positionWS = i.positionWS;
                float3 normalWS = normalize(i.normalWS);
                float3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                // [Custom Function: MainLight]
                float3 lightDir, lightColor; float distAtten, shadowAtten;
                if (_UseHalf > 0.5)
                {
                    half3 d, c; half da, sa;
                    MainLight_half(positionWS, d, c, da, sa);
                    lightDir = d; lightColor = c; distAtten = da; shadowAtten = sa;
                }
                else MainLight_float(positionWS, lightDir, lightColor, distAtten, shadowAtten);

                // [Dot Product] → [Custom Function: ToonRamp]
                float NdotL = dot(normalWS, lightDir);
                float ramp;
                if (_UseHalf > 0.5) { half r; ToonRamp_half(NdotL, shadowAtten, _Steps, _Smooth, r); ramp = r; }
                else ToonRamp_float(NdotL, shadowAtten, _Steps, _Smooth, ramp);

                // [Lerp] 阴影色 ↔ 固有色，再乘主光颜色
                float3 albedo = _BaseColor.rgb;
                float3 toon = lerp(albedo * _ShadowTint.rgb, albedo, ramp) * lightColor;

                // [Custom Function: RimLight] 只在受光侧出现
                float rim;
                RimLight_float(normalWS, viewWS, lightDir, _RimPower, 1, rim);
                rim *= step(0.5, ramp);   // 阴影里不出边缘光

                // [Custom Function: AdditionalLightsLambert] 点光、聚光
                float3 extra = 0;
                if (_AddLights > 0.5)
                {
                    AdditionalLightsLambert_float(positionWS, normalWS, screenUV, extra);
                    half3 extraHalf; AdditionalLightsLambert_half(positionWS, normalWS, screenUV, extraHalf);
                    extra = _UseHalf > 0.5 ? (float3)extraHalf : extra;
                }

                // [Ambient 节点（Equator/Sky）] 这里用等价的 SampleSH
                #if defined(SHADERGRAPH_PREVIEW)
                    float3 ambient = 0.2;
                #else
                    float3 ambient = SampleSH(normalWS);
                #endif

                float3 color = toon + albedo * (ambient * 0.6 + extra) + rim * _RimColor.rgb;
                return half4(color, 1);   // → Master Stack 的 Base Color
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
            #pragma vertex Ch23ShadowCasterVert
            #pragma fragment Ch23NullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch23DepthOnlyVert
            #pragma fragment Ch23NullFrag
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            ENDHLSL
        }
    }
}
