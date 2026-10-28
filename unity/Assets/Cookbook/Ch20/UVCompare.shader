// 案例 20.1：同一张贴图的三种贴法——网格 UV、世界空间 XZ 平面投影、三平面投影
Shader "Cookbook/Ch20/UVCompare"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _Tiling ("World Tiling (1/m)", Float) = 0.25
        _Sharpness ("Triplanar Sharpness", Range(1, 32)) = 4
        [KeywordEnum(MeshUV, WorldXZ, Triplanar, Weights)] _UVMode ("UV Mode", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // 所有 Pass 共用同一份 CBUFFER，保证 SRP Batcher 兼容
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float _Tiling;
            float _Sharpness;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _UVMODE_MESHUV _UVMODE_WORLDXZ _UVMODE_TRIPLANAR _UVMODE_WEIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch20/TerrainCommon.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                half   fogFactor  : TEXCOORD3;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                half3 albedo;
            #if defined(_UVMODE_MESHUV)
                albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
            #elif defined(_UVMODE_WORLDXZ)
                // 世界空间 UV：从正上方往下“投影”，平地完美，陡坡被拉成竖条
                albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.positionWS.xz * _Tiling).rgb;
            #else
                float3 w = TriplanarWeights(n, _Sharpness);
                #if defined(_UVMODE_WEIGHTS)
                    albedo = w;     // 调试：R=X 投影 G=Y 投影 B=Z 投影
                #else
                    TriplanarUV uv = GetTriplanarUV(i.positionWS, n, _Tiling);
                    albedo = SampleTriplanar(TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap), uv, w).rgb;
                #endif
            #endif
                return Ch20ShadePBR(i.positionWS, n, i.positionCS, albedo, 0, 0.15, 1, i.fogFactor);
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
            #pragma vertex Ch20ShadowVert
            #pragma fragment Ch20EmptyFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch20DepthVert
            #pragma fragment Ch20EmptyFrag
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex Ch20DepthVert
            #pragma fragment Ch20DepthNormalsFrag
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
    }
}
