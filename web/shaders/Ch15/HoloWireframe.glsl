// 全息线框：叠加混合（Blend One One）、双面、不写深度。（GLSL 版，对应 Ch15/HoloWireframe.shader）
// 线框发光 + 菲涅尔填充 + 沿世界 Y 的扫描线；扫描线用 _Phase 控制，运行时再加上 _Time。
Shader "Cookbook/Ch15/HoloWireframe"
{
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
            GLSLPROGRAM
            uniform vec4 _WireColor, _FillColor;
            uniform float _WireWidth, _FresnelPower, _BackFade, _ScanDensity, _ScanSpeed, _Phase;
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            #ifdef VERTEX
            void main() { NprVert(); }
            #endif

            #ifdef FRAGMENT
            float WireFactor(vec3 bary, float widthPixels)
            {
                vec3 d = fwidth(bary);
                vec3 a = smoothstep(d * (widthPixels - 0.5), d * (widthPixels + 0.5), bary);
                return 1.0 - min(a.x, min(a.y, a.z));
            }

            //#region frag
            vec4 frag()
            {
                // 双面渲染时，背面的法线要翻过来，菲涅尔才对（HLSL 的 IS_FRONT_VFACE → gl_FrontFacing）
                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                float fresnel = pow(1.0 - saturate(dot(N, V)), _FresnelPower);

                float wire = WireFactor(vertexColor.rgb, _WireWidth);
                // 扫描线：世界 Y 方向的周期亮带；静帧用 _Phase，运行时随 _Time 移动
                float t = _Time.y * _ScanSpeed + _Phase;
                float scan = pow(saturate(sin((positionWS.y - t) * _ScanDensity) * 0.5 + 0.5), 6.0);

                vec3 col = _WireColor.rgb * wire + _FillColor.rgb * (fresnel + 0.15 * scan) + _WireColor.rgb * scan * 0.08;
                col *= gl_FrontFacing ? 1.0 : _BackFade;   // 背面暗一些，增加层次
                return vec4(col, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
