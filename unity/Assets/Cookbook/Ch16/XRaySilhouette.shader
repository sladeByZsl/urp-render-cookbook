// 被遮挡部分的“X 光”剪影：ZTest Greater 只画在“已有东西比我更近”的像素上，
// 再用模板排除角色自身可见的部分。颜色带菲涅尔边缘，看起来像发光的轮廓。
// 既可以作为角色的第二个材质使用，也可以作为 RenderObjects Feature 的 Override Material。
Shader "Cookbook/Ch16/XRaySilhouette"
{
    Properties
    {
        [HDR] _RimColor ("Rim Color", Color) = (0.2, 0.8, 1.6, 1)
        _FillAlpha ("Fill Alpha", Range(0, 1)) = 0.25
        _RimPower ("Rim Power", Range(0.5, 8)) = 2
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 5           // Greater
        [IntRange] _StencilRef ("Stencil Ref", Range(0, 255)) = 1
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("Stencil Comp", Float) = 6   // NotEqual
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "XRay"
            Tags { "LightMode"="UniversalForward" }
            //#region state
            ZTest [_ZTest]
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha
            Stencil
            {
                Ref  [_StencilRef]
                Comp [_StencilComp]
            }
            //#endregion
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half4 _RimColor;
                half  _FillAlpha, _RimPower;
                float _ZTest, _StencilRef, _StencilComp;
            CBUFFER_END

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half rim = pow(1.0h - saturate(dot(N, V)), _RimPower);
                half a = saturate(_FillAlpha + rim);
                return half4(_RimColor.rgb, a);
            }
            ENDHLSL
        }
    }
}
