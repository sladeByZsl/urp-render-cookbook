// 案例 21.3：Flowmap——用一张“流向图”驱动贴图沿任意方向流动，双相位消除跳变
Shader "Cookbook/Ch21/Flowmap"
{
    Properties
    {
        _BaseMap ("Base", 2D) = "white" {}
        [NoScaleOffset] _FlowMap ("Flow Map (RG)", 2D) = "gray" {}
        _FlowStrength ("Flow Strength", Range(0, 1)) = 0.25
        _Speed ("Cycle Speed", Float) = 0.5
        _Phase ("Phase (for stills)", Float) = 0
        [Enum(ShowFlow,0,SinglePhase,1,DualPhase,2)] _Mode ("Mode", Float) = 2
        [Toggle] _UseRamp ("Use Ramp (lava look)", Float) = 0
        [NoScaleOffset] _RampTex ("Ramp", 2D) = "white" {}
        _Intensity ("Ramp Intensity", Float) = 2
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
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Cookbook/Ch21/UVAnim.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half _FlowStrength;
                float _Speed, _Phase;
                half _Mode, _UseRamp, _Intensity;
            CBUFFER_END
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_FlowMap); SAMPLER(sampler_FlowMap);
            TEXTURE2D(_RampTex); SAMPLER(sampler_RampTex);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half4 flowTex = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, i.uv);
                if (_Mode < 0.5) return half4(flowTex.rg, 0, 1);          // 直接显示流向图

                // RG 存的是 0..1，映射回 -1..1 的方向向量（0.5 灰 = 静止）
                float2 flow = (flowTex.rg * 2.0 - 1.0) * _FlowStrength;
                float t = (_Time.y + _Phase) * _Speed;
                float2 uv = TRANSFORM_TEX(i.uv, _BaseMap);

                half4 c;
                if (_Mode < 1.5)
                {
                    // 单相位：UV 沿流向越漂越远，到 frac 归零时整张图“啪”地跳回原位
                    c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv - flow * frac(t));
                }
                else
                {
                    FlowSample fs = FlowUV(uv, flow, t);
                    half4 c0 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, fs.uv0);
                    half4 c1 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, fs.uv1);
                    c = c0 * fs.w0 + c1 * (1.0 - fs.w0);
                }

                if (_UseRamp > 0.5)
                {
                    half k = smoothstep(0.2, 0.9, c.r);
                    c.rgb = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, float2(k, 0.5)).rgb * (k * k * _Intensity);
                }
                return half4(c.rgb, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
