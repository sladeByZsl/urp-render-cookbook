// 头发：Kajiya-Kay 双高光（Scheuermann 2004 的实时版本）。
// 发丝方向默认取网格切线 T；Unity 球体的切线是“横向”的，所以球形发帽要勾选 Strand Along V（用副切线做发丝方向）。
Shader "Cookbook/Ch12/HairKK"
{
    Properties
    {
        [MainColor] _BaseColor ("Hair Color", Color) = (0.22, 0.12, 0.06, 1)
        [KeywordEnum(BlinnPhong, Single, Dual)] _Mode ("Specular Model", Float) = 2
        [Toggle] _StrandAlongV ("Strand Along V (use bitangent)", Float) = 1
        _ShiftTex ("Shift Noise (R)", 2D) = "gray" {}
        _ShiftAmount ("Noise Shift Amount", Range(0, 1)) = 0.4
        [Header(Primary)]
        _PrimaryColor ("Primary Color", Color) = (1, 0.95, 0.9, 1)
        _PrimaryShift ("Primary Shift", Range(-1, 1)) = 0.1
        _PrimaryExp ("Primary Exponent", Range(1, 1000)) = 300
        [Header(Secondary)]
        _SecondaryColor ("Secondary Color", Color) = (0.8, 0.5, 0.25, 1)
        _SecondaryShift ("Secondary Shift", Range(-1, 1)) = -0.25
        _SecondaryExp ("Secondary Exponent", Range(1, 1000)) = 60
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _ShiftTex_ST;
            half4 _BaseColor, _PrimaryColor, _SecondaryColor;
            half  _StrandAlongV, _ShiftAmount;
            half  _PrimaryShift, _PrimaryExp, _SecondaryShift, _SecondaryExp;
        CBUFFER_END
        TEXTURE2D(_ShiftTex); SAMPLER(sampler_ShiftTex);
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex Ch12Vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _MODE_BLINNPHONG _MODE_SINGLE _MODE_DUAL
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch12/Ch12Common.hlsl"

            struct MaterialCtx
            {
                float3 N, V, T;
                float3 albedo;
                float  shiftNoise;   // 每根发丝的随机偏移
                float  sparkle;      // 第二高光的闪烁遮罩
            };

            //#region shade
            half3 ShadeOneLight(MaterialCtx m, Light light)
            {
                float3 L = light.direction;
                float3 H = normalize(L + m.V);
                float NoL = dot(m.N, L);

                // 漫反射：发丝是半透明细圆柱，Lambert 太“硬”，压一个下限让暗部不死黑
                float3 diffuse = m.albedo * lerp(0.25, 1.0, saturate(NoL));

                float3 spec = 0;
            #if defined(_MODE_BLINNPHONG)
                spec = _PrimaryColor.rgb * pow(saturate(dot(m.N, H)), _PrimaryExp * 0.5);
            #else
                float3 t1 = AdvShiftTangent(m.T, m.N, _PrimaryShift + m.shiftNoise);
                spec = _PrimaryColor.rgb * AdvKajiyaKay(t1, H, _PrimaryExp);
              #if defined(_MODE_DUAL)
                float3 t2 = AdvShiftTangent(m.T, m.N, _SecondaryShift + m.shiftNoise);
                spec += _SecondaryColor.rgb * m.sparkle * AdvKajiyaKay(t2, H, _SecondaryExp);
              #endif
            #endif
                // 背光面不给高光（发丝本身会挡住），用平滑过渡避免硬边
                spec *= smoothstep(-0.1, 0.3, NoL);

                return (diffuse + spec * 0.5) * light.color * (light.distanceAttenuation * light.shadowAttenuation);
            }
            //#endregion

            #include "Assets/Cookbook/Ch12/LightLoop.hlsl"

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 T, B, N; Ch12BuildFrame(i, T, B, N);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                //#region strand
                MaterialCtx m;
                m.N = N; m.V = V;
                m.T = _StrandAlongV > 0.5 ? B : T;   // 发丝方向
                half n = SAMPLE_TEXTURE2D(_ShiftTex, sampler_ShiftTex, TRANSFORM_TEX(i.uv, _ShiftTex)).r;
                m.shiftNoise = (n - 0.5) * _ShiftAmount;
                m.sparkle = saturate(n * 1.6 - 0.3);
                // 发丝颜色也带一点随机明暗，看起来才像一缕缕的
                m.albedo = _BaseColor.rgb * lerp(0.7, 1.15, n);
                //#endregion

                half3 color = AccumulateDirectLighting(m, i.positionWS, screenUV);
                color += SampleSH(N) * m.albedo;

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // URP 自带的阴影 Pass 只在 _ALPHATEST_ON 时才读 _BaseMap，其余部分与材质无关，直接复用
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
