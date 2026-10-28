// 卡通头发 + 天使环（Angel Ring）。
// 天使环本质是 Kajiya-Kay 发丝高光的“色阶化”：一条沿头顶环绕的硬边亮带，边缘用噪声切成锯齿。
Shader "Cookbook/Ch14/ToonHair"
{
    Properties
    {
        [MainColor] _BaseColor ("Hair Color", Color) = (0.25, 0.22, 0.45, 1)
        _ShadeColor ("Shade Color", Color) = (0.13, 0.1, 0.28, 1)
        [KeywordEnum(Off, Smooth, Toon)] _Ring ("Angel Ring", Float) = 2
        [HDR] _RingColor ("Ring Color", Color) = (0.85, 0.85, 1.1, 1)
        _RingShift ("Ring Shift", Range(-1, 1)) = 0.0
        _RingExponent ("Ring Exponent", Range(4, 400)) = 120
        _RingThreshold ("Ring Threshold", Range(0, 1)) = 0.55
        _ShiftTex ("Strand Noise (R)", 2D) = "gray" {}
        _RingNoise ("Ring Jaggedness", Range(0, 1)) = 0.35
        _RingFollowView ("Follow View (0 = light, 1 = camera)", Range(0, 1)) = 1
        [Toggle] _StrandAlongV ("Strand Along V (use bitangent)", Float) = 1
        _OutlineColor ("Outline Color", Color) = (0.15, 0.1, 0.12, 1)
        _OutlineWidth ("Outline Width (px)", Range(0, 10)) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _ShiftTex_ST;
            half4 _BaseColor, _ShadeColor, _RingColor;
            half  _RingShift, _RingExponent, _RingThreshold, _RingNoise, _RingFollowView, _StrandAlongV;
            half4 _OutlineColor;
            half  _OutlineWidth;
        CBUFFER_END
        TEXTURE2D(_ShiftTex); SAMPLER(sampler_ShiftTex);
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex ToonVert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _RING_OFF _RING_SMOOTH _RING_TOON
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"

            //#region frag
            half4 frag(ToonVaryings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half3 N = normalize(i.normalWS);
                half3 Tm = normalize(i.tangentWS.xyz);
                half3 Bm = cross(N, Tm) * i.tangentWS.w;
                half3 T = _StrandAlongV > 0.5 ? Bm : Tm;          // 发丝方向
                half3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();

                half band = ToonBand(dot(N, light.direction) * 0.5 + 0.5, 0.5, 0.02);
                half3 color = lerp(_ShadeColor.rgb, _BaseColor.rgb, band) * light.color;
                color += SampleSH(half3(0, 0, 0)) * _BaseColor.rgb * 0.3;

                // 天使环的“光源”：可以跟主光走，也可以固定在相机上方——后者让环始终出现在头顶，
                // 这是很多二次元项目的选择（美术要的是稳定的造型，而不是物理正确）
                half3 viewUp = normalize(UNITY_MATRIX_I_V._m01_m11_m21);
                half3 Lring = normalize(lerp(light.direction, normalize(V + viewUp * 0.6), _RingFollowView));
                half3 H = normalize(Lring + V);

                half noise = SAMPLE_TEXTURE2D(_ShiftTex, sampler_ShiftTex, TRANSFORM_TEX(i.uv, _ShiftTex)).r;
                half shift = _RingShift + (noise - 0.5) * _RingNoise;   // 每缕头发偏移不同 → 锯齿边
                half s = StrandSpecular(T, N, H, shift, _RingExponent);

                half ring = 0;
            #if defined(_RING_SMOOTH)
                ring = s;                                               // 写实版：连续的发丝高光
            #elif defined(_RING_TOON)
                ring = ToonBand(s, _RingThreshold, 0.02);               // 卡通版：切成硬边色块
            #endif
                color = lerp(color, _RingColor.rgb * lerp(0.6, 1.0, band), ring * 0.9);

                return half4(MixFog(color, i.fogFactor), 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            HLSLPROGRAM
            #pragma vertex OutlineVert
            #pragma fragment OutlineFrag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonOutlinePass.hlsl"
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
