// 案例 29.4：half 精度不够用的典型现场——远离原点时用 half 存世界坐标再算 UV。
// 桌面平台常把 half 当 float 执行，看不出问题；这里按 half 的格式（10 位尾数）手动把数值舍入到
// 它能表示的最近值，模拟它在移动 GPU 上真正以 16 位存储时的样子。
Shader "Cookbook/Ch29/HalfPrecisionDemo"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        _Tiling ("World UV Tiling (1/m)", Float) = 0.5
        [Toggle] _EmulateHalf ("Emulate Half Storage", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Demo"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float _Tiling, _EmulateHalf;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                return o;
            }

            //#region frag
            // half：1 位符号 + 5 位指数 + 10 位尾数。数值落在 [2^e, 2^(e+1)) 时，相邻两个可表示值相差 2^(e-10)
            float2 ToHalfAndBack(float2 v)
            {
                float2 e = floor(log2(max(abs(v), 6.1e-5)));   // 6.1e-5 ≈ half 最小正规数
                float2 ulp = exp2(e - 10);
                return round(v / ulp) * ulp;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 p = i.positionWS.xz;
                if (_EmulateHalf > 0.5) p = ToHalfAndBack(p);      // 相当于 half2 p = positionWS.xz;
                float2 uv = p * _Tiling;
                half3 c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).rgb;
                return half4(c, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
