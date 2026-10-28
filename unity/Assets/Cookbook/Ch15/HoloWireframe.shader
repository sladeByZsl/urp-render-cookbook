// 全息线框：叠加混合（Blend One One）、双面、不写深度。
// 线框发光 + 菲涅尔填充 + 沿世界 Y 的扫描线；扫描线用 _Phase 控制，运行时再加上 _Time。
Shader "Cookbook/Ch15/HoloWireframe"
{
    Properties
    {
        [HDR] _WireColor ("Wire Color", Color) = (0.3, 1.6, 2.4, 1)
        [HDR] _FillColor ("Fresnel Fill Color", Color) = (0.05, 0.3, 0.5, 1)
        _WireWidth ("Wire Width (pixels)", Range(0.5, 5)) = 1.2
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 2.5
        _BackFade ("Back Face Fade", Range(0, 1)) = 0.35
        _ScanDensity ("Scanline Density", Float) = 18
        _ScanSpeed ("Scanline Speed", Float) = 0.6
        _Phase ("Phase (for stills)", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "Holo"
            Tags { "LightMode"="UniversalForward" }
            Blend One One
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma vertex NprVert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _WireColor, _FillColor;
                float _WireWidth, _FresnelPower, _BackFade, _ScanDensity, _ScanSpeed, _Phase;
            CBUFFER_END
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"

            float WireFactor(float3 bary, float widthPixels)
            {
                float3 d = fwidth(bary);
                float3 a = smoothstep(d * (widthPixels - 0.5), d * (widthPixels + 0.5), bary);
                return 1.0 - min(a.x, min(a.y, a.z));
            }

            //#region frag
            half4 frag(NprVaryings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                // 双面渲染时，背面的法线要翻过来，菲涅尔才对
                float3 N = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0, -1.0);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half fresnel = pow(1.0h - saturate(dot(N, V)), _FresnelPower);

                float wire = WireFactor(i.color.rgb, _WireWidth);
                // 扫描线：世界 Y 方向的周期亮带；静帧用 _Phase，运行时随 _Time 移动
                float t = _Time.y * _ScanSpeed + _Phase;
                half scan = pow(saturate(sin((i.positionWS.y - t) * _ScanDensity) * 0.5 + 0.5), 6);

                half3 col = _WireColor.rgb * wire + _FillColor.rgb * (fresnel + 0.15h * scan) + _WireColor.rgb * scan * 0.08h;
                col *= IS_FRONT_VFACE(face, 1.0, _BackFade);   // 背面暗一些，增加层次
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
