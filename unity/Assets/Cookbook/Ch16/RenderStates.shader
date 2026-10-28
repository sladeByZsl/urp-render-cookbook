// 深度/剔除状态实验台：ZTest、ZWrite、Cull 都是材质属性，可在 Inspector 里直接切换。
// 渲染状态写成 [属性名] 的形式，Unity 会在提交绘制时读取材质上的值。
Shader "Cookbook/Ch16/RenderStates"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0.9, 0.5, 0.2, 1)
        [HDR] _BackColor ("Back Face Color", Color) = (0.2, 0.6, 0.9, 1)
        //#region props
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 4   // LessEqual
        [Enum(Off, 0, On, 1)] _ZWrite ("ZWrite", Float) = 1
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2            // Back
        //#endregion
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _BackColor;
            float _ZTest, _ZWrite, _Cull;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            //#region state
            ZTest [_ZTest]
            ZWrite [_ZWrite]
            Cull [_Cull]
            //#endregion
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                bool front = IS_FRONT_VFACE(face, true, false);
                float3 N = normalize(i.normalWS) * (front ? 1.0 : -1.0);
                half3 albedo = front ? _BaseColor.rgb : _BackColor.rgb;
                return half4(SimpleLighting(albedo, N, i.positionWS, 0.4h), 1);
            }
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
    }
}
