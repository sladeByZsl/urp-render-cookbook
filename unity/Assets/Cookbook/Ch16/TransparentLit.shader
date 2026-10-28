// 最普通的半透明受光材质：Alpha 混合、默认不写深度。ZWrite 与 Cull 做成属性，用来复现排序问题。
Shader "Cookbook/Ch16/TransparentLit"
{
    Properties
    {
        _BaseColor ("Color (A = opacity)", Color) = (0.3, 0.7, 1, 0.45)
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite [_ZWrite]
            Cull [_Cull]
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _ZWrite, _Cull;
            CBUFFER_END

            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float3 N = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0, -1.0);
                return half4(SimpleLighting(_BaseColor.rgb, N, i.positionWS, 0.8h), _BaseColor.a);
            }
            ENDHLSL
        }
    }
}
