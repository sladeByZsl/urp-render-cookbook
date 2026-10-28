// 草地风动：风场是一张在世界 XZ 上平移的噪声图（阵风），再叠加每根草相位不同的小幅摆动。
// 弯曲量按高度权重的平方分配：根部不动、越靠上越弯；同时略微压低高度，近似保持草叶长度。
Shader "Cookbook/Ch17/Grass"
{
    Properties
    {
        _RootColor ("Root Color", Color) = (0.12, 0.3, 0.08, 1)
        _TipColor ("Tip Color", Color) = (0.6, 0.8, 0.3, 1)
        _GustColor ("Gust Highlight", Color) = (0.95, 0.95, 0.6, 1)
        [NoScaleOffset] _WindNoise ("Wind Noise", 2D) = "gray" {}
        _WindDir ("Wind Direction (xz)", Vector) = (1, 0.3, 0, 0)
        _WindStrength ("Wind Strength", Range(0, 2)) = 0.8
        _WindScale ("Wind Noise Scale", Float) = 0.12
        _WindSpeed ("Wind Speed", Float) = 1
        _Sway ("Sway", Range(0, 0.5)) = 0.12
        _Phase ("Phase (for stills)", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _RootColor, _TipColor, _GustColor;
            float4 _WindDir;
            float _WindStrength, _WindScale, _WindSpeed, _Sway, _Phase;
        CBUFFER_END
        TEXTURE2D(_WindNoise); SAMPLER(sampler_WindNoise);
        #include "Assets/Cookbook/Ch17/VertexAnimCommon.hlsl"

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float h = v.color.r;                 // 0 根 → 1 尖
            float rnd = v.color.g;
            float bladeHeight = v.uv1.w;
            float3 rootWS = TransformObjectToWorld(v.uv1.xyz);
            float2 wind = normalize(_WindDir.xy);
            float t = _Time.y * _WindSpeed + _Phase;

            // 1) 阵风：噪声图沿风向平移，用根部的世界坐标采样 → 整根草取同一个值，相邻的草相近
            float2 nuv = rootWS.xz * _WindScale - wind * t * 0.15;
            float gust = SAMPLE_TEXTURE2D_LOD(_WindNoise, sampler_WindNoise, nuv, 0).r;
            gust = smoothstep(0.3, 0.75, gust);

            // 2) 摆动：每根草相位不同的小幅正弦，避免整齐划一
            float sway = sin(t * 3.0 + rnd * TWO_PI + dot(rootWS.xz, wind) * 2.0) * _Sway;

            // 3) 弯曲：根部不动，按 h² 分配；水平位移 d 时高度大约降低 d²/2（保持叶长）
            float bend = (_WindStrength * (0.2 + gust) + sway) * h * h;
            float3 dirOS = mul((float3x3)GetWorldToObjectMatrix(), float3(wind.x, 0, wind.y));
            v.positionOS.xyz += dirOS * bend * bladeHeight;
            v.positionOS.y   -= 0.5 * bend * bend * bladeHeight;

            v.uv2 = float4(gust, 0, 0, 0);       // 把阵风强度交给片元，用来提亮被风压弯的草尖
        }
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
                float h = i.color.r, rnd = i.color.g;
                // 细长的草叶法线意义不大：往“上”方向偏，整片草地的明暗更柔和
                float3 N = normalize(normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0, -1.0) + float3(0, 1.5, 0));
                half3 albedo = lerp(_RootColor.rgb, _TipColor.rgb, h) * (0.8h + 0.4h * rnd);
                albedo = lerp(albedo, _GustColor.rgb, i.extra.x * h * h * 0.6h);
                half ao = lerp(0.45h, 1.0h, h);   // 草根互相遮挡，简单压暗
                return half4(VALighting(albedo, N, i.positionWS, 0.1h, 16.0h) * ao, 1);
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
