// 案例 25.4：给 RenderObjects 当 Override Material 用的“叠加边缘光”。
// 物体已经在不透明 Pass 里画过一次，这里在同一深度上再画一遍，用加法混合叠上菲涅尔边缘光。
Shader "Cookbook/Ch25/RimOverlay"
{
    Properties
    {
        [HDR] _RimColor ("Rim Color", Color) = (0.2, 0.8, 1.6, 1)
        _RimPower ("Rim Power", Range(0.5, 8)) = 2.5
        _FillAlpha ("Fill", Range(0, 1)) = 0.12
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "RimOverlay"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Blend One One          // 加法：只增亮，不遮盖原来的颜色
            ZWrite Off
            ZTest LEqual           // 与自己在不透明 Pass 写下的深度相等，能通过

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _RimColor;
                float  _RimPower;
                float  _FillAlpha;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
                float3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half rim = pow(1.0 - saturate(dot(n, v)), _RimPower);
                return half4(_RimColor.rgb * (rim + _FillAlpha), 1.0);
            }
            ENDHLSL
        }
    }
}
