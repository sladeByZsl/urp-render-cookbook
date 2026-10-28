// 第 24 章：Blackboard Keyword 生成的代码长什么样。
// Graph 里建了两个 Keyword：
//   Enum    “Pattern”，Reference = _PATTERN，Entries = STRIPES / DOTS / CHECKER，Definition = Shader Feature，Scope = Local
//   Boolean “Use Rim”，Reference = _USE_RIM_ON，Definition = Shader Feature，Scope = Local
// Shader Graph 会为它们生成下面 Properties 里的两行和 Pass 里的两行 #pragma —— 与手写完全一致。
Shader "Cookbook/Ch24/SGKeywordEquivalent"
{
    Properties
    {
        [KeywordEnum(Stripes, Dots, Checker)] _PATTERN ("Pattern", Float) = 0
        [Toggle] _USE_RIM ("Use Rim", Float) = 0
        _ColorA ("Color A", Color) = (0.95, 0.85, 0.6, 1)
        _ColorB ("Color B", Color) = (0.25, 0.45, 0.8, 1)
        _Tiling ("Tiling", Float) = 8
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Universal Forward"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            //#region pragmas
            #pragma shader_feature_local _PATTERN_STRIPES _PATTERN_DOTS _PATTERN_CHECKER
            #pragma shader_feature_local _ _USE_RIM_ON
            //#endregion
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ColorA;
                half4 _ColorB;
                float _Tiling;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; float3 positionWS : TEXCOORD2; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS; o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                return o;
            }

            //#region keyword
            half4 frag(Varyings i) : SV_Target
            {
                float2 uv = i.uv * _Tiling;
                half mask;
                // 一个 Enum Keyword 节点 = 一组 #if/#elif，每个分支对应节点上的一个输入口
            #if defined(_PATTERN_STRIPES)
                mask = step(0.5, frac(uv.x + uv.y));
            #elif defined(_PATTERN_DOTS)
                mask = step(length(frac(uv) - 0.5), 0.3);
            #else // _PATTERN_CHECKER
                float2 c = floor(uv);
                mask = fmod(c.x + c.y, 2.0);
            #endif
                half3 albedo = lerp(_ColorA.rgb, _ColorB.rgb, mask);

                half3 n = normalize(i.normalWS);
                Light l = GetMainLight();
                half3 color = albedo * (l.color * saturate(dot(n, l.direction)) + SampleSH(n));

                // Boolean Keyword 节点 = 一个 #if，On / Off 两个输入口
            #if defined(_USE_RIM_ON)
                half3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                color += pow(1 - saturate(dot(n, v)), 3) * half3(1.0, 0.9, 0.7) * 1.5;
            #endif
                return half4(color, 1);
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
            #pragma vertex Ch23DepthOnlyVert
            #pragma fragment Ch23NullFrag
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            ENDHLSL
        }
    }
}
