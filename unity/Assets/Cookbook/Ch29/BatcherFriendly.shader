// 案例 29.1：一个“对合批友好”的最小 Shader：
//  · 所有材质属性都在 UnityPerMaterial CBUFFER 里 → SRP Batcher 兼容
//  · 支持 GPU Instancing（multi_compile_instancing），并把颜色做成可逐实例覆盖的属性
//  · 支持 LOD Cross-Fade（与 URP Lit 相同的关键字与函数）
Shader "Cookbook/Ch29/BatcherFriendly"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #if defined(LOD_FADE_CROSSFADE)
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
            #endif

            //#region cbuffer
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            // SRP Batcher：每个材质一份常量缓冲，布局在所有变体里必须一致
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
            CBUFFER_END

            // GPU Instancing：允许用 MaterialPropertyBlock 逐实例覆盖颜色
            UNITY_INSTANCING_BUFFER_START(PerInstance)
                UNITY_DEFINE_INSTANCED_PROP(half4, _InstanceColor)
            UNITY_INSTANCING_BUFFER_END(PerInstance)
            //#endregion

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
            #if defined(LOD_FADE_CROSSFADE)
                LODFadeCrossFade(i.positionCS);   // 抖动裁剪，两级 LOD 交叉淡入淡出
            #endif
                half4 tint = UNITY_ACCESS_INSTANCED_PROP(PerInstance, _InstanceColor);
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _BaseColor.rgb;
                albedo *= any(tint.rgb) ? tint.rgb : 1;     // 没设置逐实例颜色时为 0，退回材质颜色
                Light light = GetMainLight();
                half ndl = saturate(dot(normalize(i.normalWS), light.direction));
                half3 color = albedo * (light.color * ndl + SampleSH(normalize(i.normalWS)));
                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}
