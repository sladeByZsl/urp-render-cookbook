// 盒体投影（Box Projection）演示：用 URP 的 BoxProjectedCubemapDirection 修正反射方向。
// 为了在批处理拍摄中完全可控，探针参数（cubemap、位置、盒体）由材质直接提供；
// 场景里真正的反射探针走的是 GlossyEnvironmentReflection 里同一个函数，原理完全相同。
Shader "Cookbook/Ch08/BoxProjection"
{
    Properties
    {
        [NoScaleOffset] _Cube("Probe Cubemap", Cube) = "" {}
        _ProbePosition("Probe Position (xyz)", Vector) = (0, 1.5, 0, 1)
        _BoxMin("Box Min", Vector) = (-3, 0, -3, 0)
        _BoxMax("Box Max", Vector) = (3, 3, 3, 0)
        [Toggle(_BOX_PROJECTION)] _UseBox("Box Projection", Float) = 1
        _BaseColor("Base Color", Color) = (0.1, 0.1, 0.11, 1)
        _Reflectivity("Reflectivity", Range(0, 1)) = 0.6
        _Roughness("Perceptual Roughness", Range(0, 1)) = 0.05
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _ProbePosition;
            float4 _BoxMin;
            float4 _BoxMax;
            half4 _BaseColor;
            half _Reflectivity;
            half _Roughness;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _BOX_PROJECTION
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURECUBE(_Cube); SAMPLER(sampler_Cube);

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

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 N = normalize(i.normalWS);
                half3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 R = reflect(-V, N);
            #if defined(_BOX_PROJECTION)
                // 第 4 个分量 w > 0 表示“这个探针启用了盒体投影”，与 URP 的 unity_SpecCube0_ProbePosition 约定一致
                R = BoxProjectedCubemapDirection(R, i.positionWS, float4(_ProbePosition.xyz, 1), _BoxMin, _BoxMax);
            #endif
                half mip = PerceptualRoughnessToMipmapLevel(_Roughness);
                half3 refl = SAMPLE_TEXTURECUBE_LOD(_Cube, sampler_Cube, R, mip).rgb;

                // 简化的菲涅尔：掠射角反射更强
                half NoV = saturate(dot(N, V));
                half F = _Reflectivity + (1 - _Reflectivity) * Pow4(1 - NoV) * 0.5;
                half3 diffuse = _BaseColor.rgb * SampleSH(N);
                return half4(lerp(diffuse, refl, F), 1);
            }
            //#endregion
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
