// 只看“间接高光”：按粗糙度从预过滤 cubemap 的不同 mip 取环境反射。
// 模式 0：URP 的 GlossyEnvironmentReflection（探针、混合、盒体投影全包）；
// 模式 1：手动采样全局环境 cubemap，粗糙度 → mip 用线性映射（对照用）；
// 模式 2：手动采样，使用 URP 的非线性映射 PerceptualRoughnessToMipmapLevel。
Shader "Cookbook/Ch08/EnvReflection"
{
    Properties
    {
        _Roughness("Perceptual Roughness", Range(0, 1)) = 0.3
        [Enum(URP,0,ManualLinear,1,ManualURPCurve,2)] _Mode("Mode", Float) = 0
        _Tint("Tint", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _Tint;
            half _Roughness;
            half _Mode;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile _ _FORWARD_PLUS
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; float3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }

            //#region manual
            // 手动版：全局环境反射（Lighting 窗口里的 Environment Reflections）由 URP 设置为
            // _GlossyEnvironmentCubeMap，它的 mip 链是按粗糙度预过滤过的
            half3 SampleEnvManual(half3 R, half perceptualRoughness, bool urpCurve)
            {
                half mip = urpCurve
                    ? PerceptualRoughnessToMipmapLevel(perceptualRoughness)   // r·(1.7-0.7r)·6
                    : perceptualRoughness * UNITY_SPECCUBE_LOD_STEPS;          // 线性：r·6
                half4 encoded = SAMPLE_TEXTURECUBE_LOD(_GlossyEnvironmentCubeMap, sampler_GlossyEnvironmentCubeMap, R, mip);
                // HDR 解码：RGBM/dLDR 编码的 cubemap 需要 _HDR 参数还原，浮点格式时它只是乘一个强度
                return DecodeHDREnvironment(encoded, _GlossyEnvironmentCubeMap_HDR);
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                half3 N = normalize(i.normalWS);
                half3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 R = reflect(-V, N);
                half3 c;
                if (_Mode < 0.5)
                {
                    float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    c = GlossyEnvironmentReflection(R, i.positionWS, _Roughness, 1.0h, screenUV);
                }
                else
                {
                    c = SampleEnvManual(R, _Roughness, _Mode > 1.5);
                }
                return half4(c * _Tint.rgb, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch08DepthVert
            #pragma fragment Ch08NullFrag
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }
    }
}
