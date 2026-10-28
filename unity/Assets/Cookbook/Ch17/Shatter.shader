// 碎裂与吸附重组：每个三角形是一块碎片，围绕自己的中心旋转、沿面法线飞出并受“重力”下落。
// _Progress 从 0 到 1 是碎裂；反过来从 1 到 0 播放，就是碎片飞回来“吸附”成形。
// 碎片开始运动的时间由它在 _SweepDir 方向上的位置决定，形成一道扫过模型的“裂解前沿”。
Shader "Cookbook/Ch17/Shatter"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0.75, 0.78, 0.85, 1)
        [HDR] _GlowColor ("Glow Color", Color) = (2.5, 0.9, 0.3, 1)
        _Progress ("Progress", Range(0, 1)) = 0.4
        _SweepDir ("Sweep Direction", Vector) = (0, 1, 0, 0)
        _Spread ("Sweep Spread", Range(0, 2)) = 1
        _Distance ("Fly Distance", Range(0, 3)) = 0.8
        _Spin ("Spin (radians)", Range(0, 20)) = 8
        _Gravity ("Gravity", Range(0, 3)) = 0.6
        _Shrink ("Shrink", Range(0, 1)) = 0.6
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/GeometricTools.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _GlowColor;
            float4 _SweepDir;
            float _Progress, _Spread, _Distance, _Spin, _Gravity, _Shrink;
        CBUFFER_END
        #include "Assets/Cookbook/Ch17/VertexAnimCommon.hlsl"

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float3 center = v.uv1.xyz;
            float rnd = v.uv1.w;
            float3 faceN = v.uv2.xyz;

            // 1) 这块碎片自己的进度 p：沿扫描方向越靠前越早开始，再加一点随机
            // 物体空间坐标大致在 -1..1，映射到 0..1 后乘以 _Spread
            float start = saturate(dot(center, normalize(_SweepDir.xyz)) * 0.5 + 0.5) * _Spread + rnd * 0.2;
            float p = saturate(_Progress * (1.0 + _Spread + 0.2) - start);
            float ease = p * p * (3.0 - 2.0 * p);                  // smoothstep 曲线，起步柔和

            // 2) 绕碎片中心、绕一根随机轴旋转，并逐渐缩小
            float3 axis = normalize(float3(rnd - 0.5, frac(rnd * 7.13) - 0.5, frac(rnd * 3.71) - 0.5) + 1e-4);
            float angle = ease * _Spin * (0.5 + rnd);
            float3x3 R = RotationFromAxisAngle(axis, sin(angle), cos(angle));
            float3 local = mul(R, v.positionOS.xyz - center) * (1.0 - ease * _Shrink);

            // 3) 沿面法线飞出 + 抛物线下落（物体空间的 -Y）
            float3 offset = faceN * ease * _Distance * (0.6 + rnd) + float3(0, 1, 0) * (0.3 * ease - _Gravity * ease * ease);

            v.positionOS.xyz = center + local + offset;
            v.normalOS = mul(R, v.normalOS);                     // 法线跟着碎片一起转
            v.uv2.w = p;                                         // 进度交给片元做发光
        }
        //#endregion

        #include "Assets/Cookbook/Ch17/VertexAnimPasses.hlsl"
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off    // 碎片翻转后会露出背面
            HLSLPROGRAM
            #pragma vertex VAForwardVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            half4 frag(VAVaryings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float3 N = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0, -1.0);
                half3 col = VALighting(_BaseColor.rgb, N, i.positionWS, 0.6h, 64.0h);
                // 刚脱离的碎片最亮，飞远后逐渐冷却
                half p = i.extra.w;
                half glow = saturate(p * 6.0h) * (1.0h - p);
                return half4(col + _GlowColor.rgb * glow, 1);
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
