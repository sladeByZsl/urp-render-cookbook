// 30.7 节问题现场四（错误示范）：数值异常的 Shader。少数像素的分母接近 0，算出极大的 HDR 值（“萤火虫”），
// 再被 Bloom 放大成一团团光斑。同类问题还有 NaN（sqrt/log 参数为负、normalize 零向量、0/0）。
Shader "Cookbook/Ch30/FireflySource"
{
    Properties
    {
        [MainColor] _BaseColor ("Color", Color) = (0.8, 0.8, 0.8, 1)
        _BadRatio ("Bad Pixel Ratio", Range(0, 0.05)) = 0.006
        [Toggle] _Fix ("Fix (clamp denominator)", Float) = 0
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
                float _BadRatio, _Fix;
            CBUFFER_END

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

            //#region firefly
            float4 frag(Varyings i) : SV_Target
            {
                // 每个小格子一个随机数，模拟“偶尔为 0”的输入（例如某个几何项、某张贴图的通道）
                float2 cell = floor(i.uv * 160);
                float n = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
                float denom = n < _BadRatio ? 1e-5 : n;       // 少数像素分母几乎为 0
                if (_Fix > 0.5) denom = max(denom, 0.05);      // 修复：给分母一个合理下限
                float boost = min(0.5 / denom, 1e5);           // 本意：0.5~几 的增益

                Light light = GetMainLight();
                float3 diffuse = _BaseColor.rgb * (saturate(dot(normalize(i.normalWS), light.direction)) * light.color + 0.3);
                return float4(diffuse * (0.85 + 0.15 * saturate(boost)) + boost * 0.002 * (boost > 50), 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
