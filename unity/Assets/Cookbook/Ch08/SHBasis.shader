// 可视化前三阶（l = 0,1,2）实数球谐基函数 Y_lm。
// 模式 0：在单位球面上着色；模式 1：把球面顶点沿径向推到 |Y_lm| 处，得到经典的“花瓣”形状。
// 暖色 = 正值，冷色 = 负值。
Shader "Cookbook/Ch08/SHBasis"
{
    Properties
    {
        _L("Band l", Range(0, 2)) = 1
        _M("Order m", Range(-2, 2)) = 0
        [Enum(Sphere,0,Lobe,1)] _Mode("Mode", Float) = 1
        _Scale("Lobe Scale", Float) = 1
        _PosColor("Positive", Color) = (0.93, 0.48, 0.22, 1)
        _NegColor("Negative", Color) = (0.16, 0.48, 0.72, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _PosColor;
            half4 _NegColor;
            float _L;
            float _M;
            float _Mode;
            float _Scale;
        CBUFFER_END

        //#region basis
        // 实数球谐基函数，系数与 core 的 SphericalHarmonics.hlsl 中 kSHBasis0~4 一致。
        // d 为单位方向；Unity 的 SphericalHarmonicsL2 也按这 9 个函数、这个顺序存系数。
        float SHBasis(int l, int m, float3 d)
        {
            float x = d.x, y = d.y, z = d.z;
            if (l == 0) return 0.282095;                                   // Y00 = 1/2·sqrt(1/π)
            if (l == 1)
            {
                if (m == -1) return 0.488603 * y;                          // Y1-1
                if (m == 0)  return 0.488603 * z;                          // Y10
                return 0.488603 * x;                                       // Y11
            }
            if (m == -2) return 1.092548 * x * y;                          // Y2-2
            if (m == -1) return 1.092548 * y * z;                          // Y2-1
            if (m == 0)  return 0.315392 * (3.0 * z * z - 1.0);            // Y20
            if (m == 1)  return 1.092548 * x * z;                          // Y21
            return 0.546274 * (x * x - y * y);                             // Y22
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float  value      : TEXCOORD1;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 dir = normalize(input.positionOS.xyz);
                float y = SHBasis((int)round(_L), (int)round(_M), dir);
                float3 p = _Mode > 0.5 ? dir * abs(y) * _Scale : input.positionOS.xyz;
                o.positionWS = TransformObjectToWorld(p);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.value = y;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 变形后的网格没有正确法线，用屏幕导数求面法线，做一点简单明暗
                float3 n = normalize(cross(ddy(i.positionWS), ddx(i.positionWS)));
                float3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                if (dot(n, v) < 0) n = -n;
                float3 l = normalize(float3(-0.4, 0.8, -0.6));
                half shade = 0.35 + 0.65 * saturate(dot(n, l));
                half3 c = i.value >= 0 ? _PosColor.rgb : _NegColor.rgb;
                if (_Mode < 0.5) c *= saturate(abs(i.value) * 2.0) * 0.85 + 0.15;   // 球面模式：亮度 = |Y|
                return half4(c * shade, 1);
            }
            ENDHLSL
        }
    }
}
