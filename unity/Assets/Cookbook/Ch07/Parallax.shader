// 视差映射对比：None（只有法线贴图）/ Simple（URP 自带的单步偏移）/ Steep / POM，外加可选的视差自阴影。
Shader "Cookbook/Ch07/Parallax"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Range(0, 3)) = 1
        [NoScaleOffset] _ParallaxMap("Height Map", 2D) = "white" {}
        _Parallax("Height Scale (UV)", Range(0, 0.15)) = 0.05
        [KeywordEnum(None, Simple, Steep, POM)] _Mode("Parallax Mode", Float) = 3
        _MinLayers("Min Layers", Range(2, 64)) = 8
        _MaxLayers("Max Layers", Range(2, 64)) = 32
        [Toggle(_PARALLAX_SHADOW)] _SelfShadow("Self Shadow", Float) = 1
        _ShadowSteps("Shadow Steps", Range(2, 32)) = 16
        _ShadowSoftness("Shadow Softness", Range(1, 64)) = 12
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half _BumpScale;
            half _Parallax;
            half _MinLayers;
            half _MaxLayers;
            half _ShadowSteps;
            half _ShadowSoftness;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _MODE_NONE _MODE_SIMPLE _MODE_STEEP _MODE_POM
            #pragma shader_feature_local _PARALLAX_SHADOW
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
            #include "Assets/Cookbook/Ch07/Parallax.hlsl"

            TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);     SAMPLER(sampler_BumpMap);
            TEXTURE2D(_ParallaxMap); SAMPLER(sampler_ParallaxMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                half4  tangentWS  : TEXCOORD3;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.normalWS = nrm.normalWS;
                o.tangentWS = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.uv;
                float2 dx = ddx(uv), dy = ddy(uv);
                // 视线转到切线空间。URP 的 GetViewDirectionTangentSpace 要求传入“插值后未归一化”的 N/T，
                // 它内部用同一个缩放因子处理三根轴，保持与 MikkTSpace 一致。
                half3 viewDirWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 viewDirTS = GetViewDirectionTangentSpace(i.tangentWS, i.normalWS, viewDirWS);
                float hitDepth = 0;

            #if defined(_MODE_SIMPLE)
                // URP Lit 的做法（ParallaxMapping.hlsl）：采样一次高度，沿视线偏移一步
                uv += ParallaxMapping(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), viewDirTS, _Parallax, uv);
            #elif defined(_MODE_STEEP)
                uv = SteepParallax(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), uv, normalize(viewDirTS),
                                   _Parallax, _MinLayers, _MaxLayers, hitDepth);
            #elif defined(_MODE_POM)
                uv = ParallaxOcclusion(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), uv, normalize(viewDirTS),
                                       _Parallax, _MinLayers, _MaxLayers, hitDepth);
            #endif

                // 之后所有贴图都用偏移后的 UV 采样，并沿用原始 UV 的导数，避免台阶边缘的 mip 跳变
                half3 albedo = SAMPLE_TEXTURE2D_GRAD(_BaseMap, sampler_BaseMap, uv, dx, dy).rgb;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(_BumpMap, sampler_BumpMap, uv, dx, dy), _BumpScale);
                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3x3 tbn = half3x3(i.tangentWS.xyz, bitangent, i.normalWS);
                half3 normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tbn));

                half selfShadow = 1;
            #if defined(_PARALLAX_SHADOW) && (defined(_MODE_STEEP) || defined(_MODE_POM))
                // 把主光方向也转到切线空间：TBN 是正交基，转置即逆，mul(tbn, v) = (T·v, B·v, N·v)
                half3 lightDirTS = normalize(mul(tbn, GetMainLight().direction));
                selfShadow = ParallaxSelfShadow(TEXTURE2D_ARGS(_ParallaxMap, sampler_ParallaxMap), uv, dx, dy,
                                                hitDepth, lightDirTS, _Parallax, _ShadowSteps, _ShadowSoftness);
            #endif

                half3 color = Ch07Shade(i.positionWS, normalWS, albedo, 0.45, 0.12, selfShadow);
                return half4(color, 1);
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
            #pragma vertex Ch07ShadowVert
            #pragma fragment Ch07NullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch07DepthVert
            #pragma fragment Ch07NullFrag
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            ENDHLSL
        }
    }
}
