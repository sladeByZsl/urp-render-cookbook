// 被遮挡部分的“X 光”剪影：ZTest Greater 只画在“已有东西比我更近”的像素上，（GLSL 版）
// 再用模板排除角色自身可见的部分。颜色带菲涅尔边缘，看起来像发光的轮廓。
// 既可以作为角色的第二个材质使用，也可以作为 RenderObjects Feature 的 Override Material。
Shader "Cookbook/Ch16/XRaySilhouette"
{
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
            GLSLPROGRAM
            #include "Ch16/Ch16Common.glsl"
            uniform vec4 _RimColor;
            uniform float _FillAlpha, _RimPower;

            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                float rim = pow(1.0 - saturate(dot(N, V)), _RimPower);
                float a = saturate(_FillAlpha + rim);
                fragColor = vec4(_RimColor.rgb, a);
            }
            #endif
            ENDGLSL
        }
    }
}
