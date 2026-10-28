// 案例 30.1：可切换输出的“调试视图” Shader。把中间量直接画成颜色，是 Shader 调试最快的手段。
// _DebugView：0 最终光照 1 世界法线 2 UV 3 N·L 4 主光阴影 5 切线空间法线贴图 6 世界坐标网格
Shader "Cookbook/Ch30/DebugView"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [NoScaleOffset][Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1
        [Enum(Final,0, NormalWS,1, UV,2, NdotL,3, Shadow,4, NormalMapTS,5, WorldGrid,6)] _DebugView ("Debug View", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "ForwardDebug"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            // 需要逐像素源码级调试（RenderDoc/PIX 单步）时打开下面这行；发布前删掉
            // #pragma enable_d3d11_debug_symbols
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half _BumpScale;
                half _DebugView;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                half4 tangentWS : TEXCOORD3;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                o.tangentWS = half4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            //#region debug
            half4 frag(Varyings i) : SV_Target
            {
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                half3 bitangentWS = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3 normalWS = normalize(TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangentWS, i.normalWS)));

                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half ndl = saturate(dot(normalWS, light.direction));
                int view = (int)_DebugView;

                // 约定：方向向量 [-1,1] 映射到 [0,1] 再显示；标量直接显示为灰度
                if (view == 1) return half4(normalWS * 0.5 + 0.5, 1);
                if (view == 2) return half4(frac(i.uv), 0, 1);
                if (view == 3) return half4(ndl.xxx, 1);
                if (view == 4) return half4(light.shadowAttenuation.xxx, 1);
                if (view == 5) return half4(normalTS * 0.5 + 0.5, 1);
                if (view == 6)
                {
                    float3 g = abs(frac(i.positionWS * 2 + 0.5) - 0.5) / fwidth(i.positionWS * 2);
                    half line01 = 1 - saturate(min(g.x, min(g.y, g.z)));
                    return half4(lerp(half3(0.15, 0.15, 0.18), half3(1, 0.6, 0.2), line01), 1);
                }

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 color = albedo * (light.color * ndl * light.shadowAttenuation + SampleSH(normalWS));
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }
        // 投射阴影直接借用 URP Lit 的 ShadowCaster（会让本 Shader 不兼容 SRP Batcher，调试 Shader 无所谓）
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}
