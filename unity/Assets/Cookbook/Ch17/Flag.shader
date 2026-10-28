// 旗帜飘动：在细分平面（物体空间 XZ 平面，法线 +Y）上沿 Y 方向位移。
// 位移 = 沿旗面传播的正弦波 + 噪声扰动，振幅从旗杆处的 0 逐渐增大；
// 法线用有限差分重新计算（对位移函数在 x、z 方向各取一个邻点）。
Shader "Cookbook/Ch17/Flag"
{
    Properties
    {
        [MainTexture] _BaseMap ("Flag Texture", 2D) = "white" {}
        [MainColor] _BaseColor ("Tint", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _NoiseTex ("Noise", 2D) = "gray" {}
        _Amplitude ("Amplitude", Range(0, 0.5)) = 0.18
        _WaveLength ("Wave Length", Range(0.2, 4)) = 1.3
        _Speed ("Speed", Range(0, 5)) = 2.2
        _NoiseStrength ("Noise Strength", Range(0, 1)) = 0.5
        _Phase ("Phase (for stills)", Float) = 0
        _FlagWidth ("Flag Width (object space X)", Float) = 2
        [Toggle] _RecalcNormal ("Recalculate Normal", Float) = 1
        [Toggle] _DeformShadow ("Deform In Shadow Pass", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            float _Amplitude, _WaveLength, _Speed, _NoiseStrength, _Phase, _FlagWidth, _RecalcNormal, _DeformShadow;
        CBUFFER_END
        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);
        #include "Assets/Cookbook/Ch17/VertexAnimCommon.hlsl"

        //#region displace
        // 位移只依赖旗面上的 (x, z) 坐标和时间：这是能用有限差分求法线的前提
        float FlagOffset(float2 xz)
        {
            float u = xz.x / _FlagWidth + 0.5;             // 0 = 旗杆一侧，1 = 自由端
            float t = _Time.y * _Speed + _Phase;           // 运行时 _Time 驱动；静帧用 _Phase
            float k = TWO_PI / _WaveLength;
            float pin = smoothstep(0.0, 0.25, u) * u;      // 旗杆处钉死，越往外摆得越大
            // 主波沿 +x 传播，次波斜向传播，让波峰不那么整齐
            float w = sin(k * xz.x - t) + 0.35 * sin(k * 1.7 * (xz.x * 0.6 + xz.y) - t * 1.3);
            // 噪声：随时间平移，制造“阵风”造成的不规则起伏
            float2 nuv = xz * 0.12 + float2(-t * 0.05, t * 0.02);   // 低频采样：只要大尺度的起伏
            float n = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, nuv, 0).r * 2.0 - 1.0;
            return (w + n * _NoiseStrength * 2.0) * _Amplitude * pin;
        }
        //#endregion

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float3 p = v.positionOS.xyz;
            float h = FlagOffset(p.xz);

            if (_RecalcNormal > 0.5)
            {
                // 有限差分：在 x、z 方向各挪一小步，得到两个“切线”，叉乘就是新法线
                const float e = 0.04;   // 步长太小会放大噪声贴图的双线性折痕
                float hx = FlagOffset(p.xz + float2(e, 0));
                float hz = FlagOffset(p.xz + float2(0, e));
                float3 tangent   = float3(e, hx - h, 0);
                float3 bitangent = float3(0, hz - h, e);
                v.normalOS = normalize(cross(bitangent, tangent));
            }
            v.positionOS.y += h;
        }

        // 阴影 Pass 专用：_DeformShadow = 0 时不变形，用来演示“影子不动”的错误
        void DeformForShadow(inout VAAttributes v)
        {
            if (_DeformShadow > 0.5) Deform(v);
        }
        #define VA_DEFORM_SHADOW DeformForShadow
        //#endregion

        #include "Assets/Cookbook/Ch17/VertexAnimPasses.hlsl"
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off
            HLSLPROGRAM
            #pragma vertex VAForwardVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            half4 frag(VAVaryings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float3 N = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0, -1.0);   // 旗子两面都要正确受光
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, TRANSFORM_TEX(i.uv, _BaseMap)).rgb * _BaseColor.rgb;
                return half4(VALighting(albedo, N, i.positionWS, 0.25h, 24.0h), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            HLSLPROGRAM
            #pragma vertex VAShadowVert
            #pragma fragment VANullFrag
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Off
            HLSLPROGRAM
            #pragma vertex VADepthVert
            #pragma fragment VANullFrag
            ENDHLSL
        }
    }
}
