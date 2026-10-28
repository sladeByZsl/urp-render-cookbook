// 双面材质：Cull Off 让背面也画出来；但背面的插值法线仍朝“外”，必须按 SV_IsFrontFace 翻转，
// 否则背面的光照是反的。背面还可以用另一种颜色（例如纸张、叶片的背面更浅）。
Shader "Cookbook/Ch16/TwoSided"
{
    Properties
    {
        _BaseColor ("Front Color", Color) = (0.85, 0.35, 0.25, 1)
        _BackColor ("Back Color", Color) = (0.95, 0.85, 0.55, 1)
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 0
        [Toggle] _FlipBackNormal ("Flip Back Face Normal", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _BackColor;
            float _Cull, _FlipBackNormal;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            //#region frag
            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                // IS_FRONT_VFACE 屏蔽了平台差异：D3D/Metal 是 bool，旧的 GL 是 float 符号
                bool isFront = IS_FRONT_VFACE(face, true, false);
                float3 N = normalize(i.normalWS);
                if (!isFront && _FlipBackNormal > 0.5) N = -N;
                half3 albedo = isFront ? _BaseColor.rgb : _BackColor.rgb;
                return half4(SimpleLighting(albedo, N, i.positionWS, 0.3h), 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull [_Cull]
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            float4 vert(Attributes v) : SV_POSITION { return Ch16ShadowPositionCS(v.positionOS.xyz, v.normalOS); }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull [_Cull]
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            float4 vert(Attributes v) : SV_POSITION { return TransformObjectToHClip(v.positionOS.xyz); }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
