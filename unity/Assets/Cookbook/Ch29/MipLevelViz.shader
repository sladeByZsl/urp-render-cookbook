// 案例 29.6：Mip 级别可视化。用屏幕空间导数估算 GPU 会选哪一级 Mip，并按级别着色。
// 级别越高 = 一个像素覆盖的纹素越多；如果近处也是高级别，说明贴图分辨率给多了（浪费带宽和内存）。
Shader "Cookbook/Ch29/MipLevelViz"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        _Blend ("Overlay Strength", Range(0, 1)) = 0.65
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "MipViz"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            float4 _BaseMap_TexelSize;   // (1/w, 1/h, w, h)，由 Unity 自动设置
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half _Blend;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            //#region mip
            float ComputeMipLevel(float2 uv, float2 texSize)
            {
                // 相邻像素之间 uv 变化了多少个纹素
                float2 dx = ddx(uv * texSize);
                float2 dy = ddy(uv * texSize);
                float maxSq = max(dot(dx, dx), dot(dy, dy));
                return 0.5 * log2(maxSq);   // = log2(最大纹素跨度)；<0 表示放大（一个纹素盖住多个像素）
            }

            half3 MipColor(float mip)
            {
                static const half3 c[7] = { half3(0.1, 0.35, 1), half3(0.15, 0.8, 0.3), half3(0.95, 0.9, 0.15),
                                            half3(1, 0.55, 0.1), half3(0.95, 0.15, 0.1), half3(0.8, 0.1, 0.7), half3(0.35, 0.1, 0.5) };
                // c[0] 给“放大”区（mip<0），c[1] 起依次是 mip 0,1,2...
                float m = clamp(mip + 1, 0, 6);
                int i = (int)floor(m);
                return lerp(c[i], c[min(i + 1, 6)], frac(m));
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                float mip = ComputeMipLevel(i.uv, _BaseMap_TexelSize.zw);
                return half4(lerp(albedo, MipColor(mip), _Blend), 1);
            }
            ENDHLSL
        }
    }
}
