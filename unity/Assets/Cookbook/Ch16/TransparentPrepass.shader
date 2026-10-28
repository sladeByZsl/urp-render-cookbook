// 双 Pass 半透明：第一个 Pass 只写深度（不写颜色），第二个 Pass 用 LEqual 正常混合。
// 结果是每个像素只留下“离相机最近的那层表面”，自身前后层次不再错乱。
// URP 的 DrawObjectsPass 按 SRPDefaultUnlit → UniversalForward 的顺序绘制同一物体的多个 Pass，
// 所以把预深度放在 SRPDefaultUnlit 里，就能保证它先于颜色 Pass 执行。
Shader "Cookbook/Ch16/TransparentPrepass"
{
    Properties
    {
        _BaseColor ("Color (A = opacity)", Color) = (0.3, 0.7, 1, 0.45)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
        CBUFFER_END
        ENDHLSL

        //#region prepass
        Pass
        {
            Name "DepthPrepass"
            Tags { "LightMode"="SRPDefaultUnlit" }
            ZWrite On
            ColorMask 0          // 只写深度，不动颜色
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            float4 vert(Attributes v) : SV_POSITION { return TransformObjectToHClip(v.positionOS.xyz); }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual         // 深度相等的那层（最前面的表面）才能通过
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            half4 frag(Varyings i) : SV_Target
            {
                return half4(SimpleLighting(_BaseColor.rgb, normalize(i.normalWS), i.positionWS, 0.8h), _BaseColor.a);
            }
            ENDHLSL
        }
        //#endregion
    }
}
