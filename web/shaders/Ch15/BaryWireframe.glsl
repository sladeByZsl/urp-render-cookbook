// 重心坐标线框：网格的顶点色里预先烘焙了重心坐标 (1,0,0)/(0,1,0)/(0,0,1)，（GLSL 版，对应 Ch15/BaryWireframe.shader）
// 光栅化插值后，某个分量接近 0 就说明像素靠近对应的边。fwidth 让线宽以“像素”为单位恒定。
Shader "Cookbook/Ch15/BaryWireframe"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _WireColor;
        uniform float _WireWidth;

        #ifdef FRAGMENT
        //#region wire
        // 返回 0..1 的“线框覆盖度”。bary 来自顶点色插值。
        float WireFactor(vec3 bary, float widthPixels)
        {
            vec3 d = fwidth(bary);                      // 每个分量在一个像素内的变化量
            vec3 a = smoothstep(d * (widthPixels - 0.5), d * (widthPixels + 0.5), bary);
            return 1.0 - min(a.x, min(a.y, a.z));       // 任一分量接近 0 → 在边上
        }
        //#endregion
        #endif
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            #ifdef VERTEX
            void main() { NprVert(); }
            #endif

            #ifdef FRAGMENT
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                NprLight L = GetNprLight(positionWS, N);
                vec3 fill = _BaseColor.rgb * (saturate(L.ndotl) * L.shadow * L.color + SampleSH(N));
                float w = WireFactor(vertexColor.rgb, _WireWidth);
                return vec4(mix(fill, _WireColor.rgb, w), 1.0);
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define NPR_SHADOW_PASS
            #include "Ch15/NPRCommon.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define NPR_DEPTH_PASS
            #include "Ch15/NPRCommon.glsl"
            ENDGLSL
        }
    }
}
