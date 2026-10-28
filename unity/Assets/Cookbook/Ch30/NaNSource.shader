// 30.7 节问题现场四（错误示范）：在少数像素上产生 NaN 的 Shader。
// 现实中的来源：sqrt/pow/log 的参数为负、normalize 零向量、0/0。
Shader "Cookbook/Ch30/NaNSource"
{
    Properties
    {
        [MainColor] _BaseColor ("Color", Color) = (0.8, 0.8, 0.8, 1)
        _BadRatio ("Bad Pixel Ratio", Range(0, 0.05)) = 0.002
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _BadRatio;
            CBUFFER_END
            uint _NaNBits;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; float2 uv : TEXCOORD1; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv = input.uv;
                return o;
            }

            //#region nan
            float4 frag(Varyings i) : SV_Target
            {
                float2 cell = floor(i.uv * 160);
                float n = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
                // 现实里的写法类似 float k = sqrt(n - _BadRatio); —— 少数像素参数为负，结果是 NaN。
                // sqrt(负数) 和写死的 NaN 常量都可能被编译器的快速数学优化“优化掉”，为了让演示可重复，
                // 这里用运行时传入的 NaN 位模式（指数全 1、尾数非 0）。
                float k = sqrt(n);
                if (n < _BadRatio) k = asfloat(_NaNBits);   // _NaNBits = 0x7FC00000，运行时由 C# 传入，编译器无法提前折叠
                Light light = GetMainLight();
                float3 color = _BaseColor.rgb * (saturate(dot(normalize(i.normalWS), light.direction)) * light.color + 0.3);
                return float4(color * (0.8 + 0.2 * k), 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
