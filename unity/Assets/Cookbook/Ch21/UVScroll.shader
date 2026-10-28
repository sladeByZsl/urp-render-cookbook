// 案例 21.1：UV 滚动——单层滚动 → 双层叠加 → UV 扰动 + 渐变映射，做出流动的熔岩
Shader "Cookbook/Ch21/UVScroll"
{
    Properties
    {
        [NoScaleOffset] _NoiseTex ("Noise", 2D) = "gray" {}
        [NoScaleOffset] _RampTex ("Color Ramp", 2D) = "white" {}
        _Layer1 ("Layer1 Tiling(xy) Speed(zw)", Vector) = (1, 2, 0, -0.15)
        _Layer2 ("Layer2 Tiling(xy) Speed(zw)", Vector) = (1.7, 1.3, 0.05, -0.08)
        [Toggle] _SecondLayer ("Second Layer", Float) = 1
        _Distort ("UV Distort", Range(0, 0.5)) = 0.15
        [Toggle] _UseRamp ("Use Ramp", Float) = 1
        _Intensity ("Emission Intensity", Float) = 1.6
        _Phase ("Phase (time offset for stills)", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _Layer1, _Layer2;
                half _SecondLayer, _Distort, _UseRamp, _Intensity;
                float _Phase;
            CBUFFER_END
            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);
            TEXTURE2D(_RampTex);  SAMPLER(sampler_RampTex);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; half fog : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                o.fog = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                // 时间：运行时用 _Time.y，配图时 _Time 不可控，用 _Phase 指定“第几秒”
                // frac 把偏移量限制在 0..1：贴图是 Repeat 寻址，结果不变，但避免长时间运行后浮点精度下降
                float t = _Time.y + _Phase;
                float2 off1 = frac(_Layer1.zw * t);
                float2 off2 = frac(_Layer2.zw * t);

                // 第二层：既参与叠加，也用来扰动第一层的 UV
                half n2 = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, i.uv * _Layer2.xy + off2).r;
                float2 distort = (n2 - 0.5) * _Distort * _SecondLayer;
                half n1 = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, i.uv * _Layer1.xy + off1 + distort).r;

                half v = lerp(n1, n1 * n2 * 2.0, _SecondLayer);     // 两层相乘再 ×2，保持平均亮度
                v = saturate(v);

                half3 col = v.xxx;
                if (_UseRamp > 0.5)
                {
                    // 渐变映射：灰度 → 颜色。暗处是冷却的黑色岩壳，亮处是高温的黄白色
                    half k = smoothstep(0.3, 1.0, v);
                    col = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, float2(k, 0.5)).rgb * (k * k * _Intensity);
                }
                col = MixFog(col, i.fog);
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
