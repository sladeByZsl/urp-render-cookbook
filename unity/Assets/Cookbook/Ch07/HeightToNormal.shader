// 不用法线贴图，直接从高度图算法线：①中心差分（多采样 4 次）②屏幕导数 ddx/ddy（只采样 1 次）。
// 模式 0 是烘焙好的法线贴图，作为参照。
Shader "Cookbook/Ch07/HeightToNormal"
{
    Properties
    {
        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [NoScaleOffset][Normal] _BumpMap("Normal Map (reference)", 2D) = "bump" {}
        [NoScaleOffset] _HeightMap("Height Map", 2D) = "black" {}
        _HeightStrength("Height Strength (per texel)", Range(0, 16)) = 6
        [Enum(NormalMap,0,CentralDifference,1,ScreenDerivative,2)] _Mode("Mode", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _HeightMap_TexelSize;   // Unity 自动填充：(1/宽, 1/高, 宽, 高)
            half _HeightStrength;
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
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"

            TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);   SAMPLER(sampler_BumpMap);
            TEXTURE2D(_HeightMap); SAMPLER(sampler_HeightMap);

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

            float SampleHeight(float2 uv) { return SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv).r; }

            //#region central
            // 中心差分：在 U、V 方向各取左右两个邻居。结果与离线烘焙法线贴图的算法一致。
            half3 NormalFromHeightCentral(float2 uv)
            {
                float2 t = _HeightMap_TexelSize.xy;
                float hL = SampleHeight(uv - float2(t.x, 0));
                float hR = SampleHeight(uv + float2(t.x, 0));
                float hD = SampleHeight(uv - float2(0, t.y));
                float hU = SampleHeight(uv + float2(0, t.y));
                // 每个纹素的高度差 × 强度 = 斜率；法线 = normalize(-dh/du, -dh/dv, 1)
                float dhdu = (hR - hL) * 0.5 * _HeightStrength;
                float dhdv = (hU - hD) * 0.5 * _HeightStrength;
                return normalize(half3(-dhdu, -dhdv, 1));
            }
            //#endregion

            //#region derivative
            // 屏幕导数：ddx/ddy 给出“相邻像素之间”h 和 uv 的变化量，解一个 2×2 线性方程
            // 就能把屏幕空间的变化换算成 dh/du、dh/dv。只采样一次，但精度受 2×2 像素块限制。
            half3 NormalFromHeightDerivative(float2 uv)
            {
                float h = SampleHeight(uv);
                float2 duvdx = ddx(uv), duvdy = ddy(uv);
                float dhdx = ddx(h), dhdy = ddy(h);
                // [duvdx; duvdy] · (dh/du, dh/dv) = (dhdx, dhdy)，用克拉默法则求解
                float det = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
                float2 grad = float2(dhdx * duvdy.y - dhdy * duvdx.y,
                                     duvdx.x * dhdy - duvdy.x * dhdx) / (abs(det) > 1e-12 ? det : 1e-12);
                grad *= _HeightMap_TexelSize.xy * _HeightStrength;   // 每 UV 单位 → 每纹素
                return normalize(half3(-grad, 1));
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                half3 normalTS;
                if (_Mode < 0.5)      normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv));
                else if (_Mode < 1.5) normalTS = NormalFromHeightCentral(i.uv);
                else                  normalTS = NormalFromHeightDerivative(i.uv);

                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3 normalWS = NormalizeNormalPerPixel(
                    TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, i.normalWS)));
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                return half4(Ch07Shade(i.positionWS, normalWS, albedo, 0.45, 0.15, 1), 1);
            }
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
