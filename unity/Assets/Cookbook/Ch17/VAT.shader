// 播放 VAT：顶点用 uv1.x（自己的编号）+ 当前帧号去查位置/法线贴图，相邻两帧之间线性插值。
// 帧号 = _Time.y * _FPS + _Frame；静帧时 _Time≈0，直接用 _Frame 指定。
Shader "Cookbook/Ch17/VAT"
{
    Properties
    {
        [NoScaleOffset] _PosTex ("VAT Position", 2D) = "black" {}
        [NoScaleOffset] _NrmTex ("VAT Normal", 2D) = "bump" {}
        _FPS ("Frames Per Second", Float) = 24
        _Frame ("Frame Offset", Float) = 0
        _RootColor ("Root Color", Color) = (0.45, 0.12, 0.35, 1)
        _TipColor ("Tip Color", Color) = (1, 0.55, 0.45, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float _FPS, _Frame;
            half4 _RootColor, _TipColor;
            float4 _PosTex_TexelSize;      // (1/宽, 1/高, 宽, 高)：高 = 帧数
        CBUFFER_END
        TEXTURE2D(_PosTex);
        TEXTURE2D(_NrmTex);
        #include "Assets/Cookbook/Ch17/VertexAnimCommon.hlsl"

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float frames = _PosTex_TexelSize.w;
            float f = fmod(_Time.y * _FPS + _Frame, frames);
            float f0 = floor(f);
            float f1 = fmod(f0 + 1.0, frames);       // 最后一帧插值回第一帧，循环无缝
            float w = f - f0;

            // 采样纹素中心；必须用点采样 + LOD 0，否则相邻顶点/相邻帧会被双线性混在一起
            float2 uv0 = float2(v.uv1.x, (f0 + 0.5) / frames);
            float2 uv1 = float2(v.uv1.x, (f1 + 0.5) / frames);
            float3 p0 = SAMPLE_TEXTURE2D_LOD(_PosTex, sampler_PointClamp, uv0, 0).xyz;
            float3 p1 = SAMPLE_TEXTURE2D_LOD(_PosTex, sampler_PointClamp, uv1, 0).xyz;
            float3 n0 = SAMPLE_TEXTURE2D_LOD(_NrmTex, sampler_PointClamp, uv0, 0).xyz;
            float3 n1 = SAMPLE_TEXTURE2D_LOD(_NrmTex, sampler_PointClamp, uv1, 0).xyz;

            v.positionOS.xyz = lerp(p0, p1, w);      // 贴图里存的是绝对位置，直接替换
            v.normalOS = normalize(lerp(n0, n1, w));
        }
        //#endregion

        #include "Assets/Cookbook/Ch17/VertexAnimPasses.hlsl"
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex VAForwardVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            half4 frag(VAVaryings i) : SV_Target
            {
                half3 albedo = lerp(_RootColor.rgb, _TipColor.rgb, i.uv.y);
                // 横向的环纹，方便看出扭转
                albedo *= 0.8h + 0.2h * step(0.5h, frac(i.uv.x * 4.0h));
                return half4(VALighting(albedo, normalize(i.normalWS), i.positionWS, 0.6h, 48.0h), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex VAShadowVert
            #pragma fragment VANullFrag
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex VADepthVert
            #pragma fragment VANullFrag
            ENDHLSL
        }
    }
}
