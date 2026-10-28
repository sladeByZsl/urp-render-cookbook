// 第 24 章：与“Lit Graph 溶解”等价的手写 Shader。
// Lit Graph 的 Master Stack 输出 Base Color / Metallic / Smoothness / Emission / Alpha / Alpha Clip Threshold，
// 生成代码最终把它们填进 SurfaceData 再调用 UniversalFragmentPBR —— 这里照做一遍。
Shader "Cookbook/Ch24/SGDissolveEquivalent"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (0.75, 0.78, 0.85, 1)
        _Metallic ("Metallic", Range(0, 1)) = 0.6
        _Smoothness ("Smoothness", Range(0, 1)) = 0.55
        _NoiseMap ("Noise", 2D) = "gray" {}
        _Progress ("Progress", Range(0, 1)) = 0.4
        _EdgeWidth ("Edge Width", Range(0.001, 0.3)) = 0.08
        [HDR] _EdgeColor ("Edge Color", Color) = (4, 1.4, 0.3, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Assets/Cookbook/Ch24/StylizedFunctions.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4  _BaseColor;
            half   _Metallic;
            half   _Smoothness;
            float4 _NoiseMap_ST;
            half   _Progress;
            half   _EdgeWidth;
            half4  _EdgeColor;
        CBUFFER_END
        TEXTURE2D(_NoiseMap); SAMPLER(sampler_NoiseMap);

        // 图里“Sample Texture 2D → Dissolve”这一段，所有 Pass 共用
        void DissolveGraph(float2 uv, out float alpha, out float edge)
        {
            float noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, TRANSFORM_TEX(uv, _NoiseMap)).r;
            Dissolve_float(noise, _Progress, _EdgeWidth, alpha, edge);
        }
        ENDHLSL

        Pass
        {
            Name "Universal Forward"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 positionWS : TEXCOORD1; float3 normalWS : TEXCOORD2; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS; o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float alpha, edge;
                DissolveGraph(i.uv, alpha, edge);
                clip(alpha - 0.5);                         // Alpha Clip Threshold = 0.5

                SurfaceData surface = (SurfaceData)0;      // ← Master Stack 的各个 Block
                surface.albedo     = _BaseColor.rgb * (1 - edge);
                surface.metallic   = _Metallic;
                surface.smoothness = _Smoothness;
                surface.occlusion  = 1;
                surface.emission   = edge * _EdgeColor.rgb;
                surface.alpha      = 1;
                surface.normalTS   = half3(0, 0, 1);

                InputData input = (InputData)0;
                input.positionWS = i.positionWS;
                input.normalWS = normalize(i.normalWS);
                input.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                input.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                input.bakedGI = SampleSH(input.normalWS);
                input.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                input.shadowMask = half4(1, 1, 1, 1);
                return UniversalFragmentPBR(input, surface);
            }
            //#endregion
            ENDHLSL
        }

        //#region caster
        Pass
        {
            // Shader Graph 会自动把 Alpha Clip 带进 ShadowCaster / DepthOnly；手写时最容易忘
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            Varyings vert(Attributes v)
            {
                Varyings o;
                CasterAttributes c; c.positionOS = v.positionOS; c.normalOS = v.normalOS;
                o.positionCS = Ch23ShadowCasterVert(c);
                o.uv = v.uv;
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                float alpha, edge;
                DissolveGraph(i.uv, alpha, edge);
                clip(alpha - 0.5);
                return 0;
            }
            ENDHLSL
        }
        //#endregion

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            Varyings vert(Attributes v) { Varyings o; o.positionCS = TransformObjectToHClip(v.positionOS.xyz); o.uv = v.uv; return o; }
            half4 frag(Varyings i) : SV_Target
            {
                float alpha, edge;
                DissolveGraph(i.uv, alpha, edge);
                clip(alpha - 0.5);
                return 0;
            }
            ENDHLSL
        }
    }
}
