// 使用“手工烘焙”的光照贴图作为间接漫反射，直接光（主光 + 实时阴影）照常实时计算——
// 这正是 Mixed Lighting 里 Baked Indirect 模式的分工。
Shader "Cookbook/Ch08/ManualLightmap"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (0.75, 0.75, 0.75, 1)
        [NoScaleOffset] _BakedGI("Baked GI (linear)", 2D) = "white" {}
        [Enum(SH,0,Baked,1,ShowBakedOnly,2)] _Mode("Indirect Source", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BakedGI); SAMPLER(sampler_BakedGI);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; float2 lightmapUV : TEXCOORD1; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 uv         : TEXCOORD0;   // xy 贴图 UV，zw 光照贴图 UV
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv.xy = TRANSFORM_TEX(input.uv, _BaseMap);
                o.uv.zw = input.lightmapUV;      // 真正的光照贴图还要乘 unity_LightmapST，这里一张图只给一个物体用
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 N = normalize(i.normalWS);
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv.xy).rgb * _BaseColor.rgb;
                half3 baked = SAMPLE_TEXTURE2D(_BakedGI, sampler_BakedGI, i.uv.zw).rgb;
                if (_Mode > 1.5) return half4(baked, 1);          // 直接看光照贴图里存了什么

                // 间接漫反射：光照贴图（含天空遮蔽） 或 球谐（处处一样，没有遮蔽）
                half3 indirect = _Mode > 0.5 ? baked : SampleSH(N);
                // 直接光：实时主光 + 实时阴影
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half3 direct = mainLight.color * saturate(dot(N, mainLight.direction)) * mainLight.shadowAttenuation;
                return half4(albedo * (indirect + direct), 1);
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
