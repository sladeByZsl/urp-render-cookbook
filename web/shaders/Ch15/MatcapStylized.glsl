// Matcap（材质捕获）：把“一个球在某种光照下的样子”存成贴图，用观察空间法线去查表。（GLSL 版，对应 Ch15/MatcapStylized.shader）
// 修正了透视畸变（以视线方向为基准建立局部坐标系），并可选地叠加场景阴影。
Shader "Cookbook/Ch15/MatcapStylized"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor;
        uniform float _PerspectiveFix;
        uniform float _ShadowStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            uniform sampler2D _MatCap;

            #ifdef VERTEX
            void main() { NprVert(); }
            #endif

            #ifdef FRAGMENT
            //#region matcap-uv
            vec2 MatcapUV(vec3 posWS, vec3 nrmWS)
            {
                vec3 normalVS = normalize(TransformWorldToViewDir(nrmWS));
                // 朴素做法：直接取观察空间法线的 xy
                vec2 naive = normalVS.xy;

                // 修正：以“从该点指向相机”的方向 V 为 z 轴，重新构造 x/y 轴，
                // 等于把每个像素都当成“正对相机”的那一点来查表，画面边缘不再被拉扯
                vec3 V = normalize(-TransformWorldToView(posWS));        // 观察空间里相机在原点
                vec3 up = normalize(vec3(0, 1, 0) - V * V.y);            // 把世界“上”投影到垂直于 V 的平面
                vec3 right = cross(up, V);
                vec2 corrected = vec2(dot(normalVS, right), dot(normalVS, up));

                vec2 n = mix(naive, corrected, _PerspectiveFix);
                return n * 0.49 + 0.5;    // 0.49 而非 0.5：避开贴图最外圈的边缘像素
            }
            //#endregion

            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                vec3 col = texture(_MatCap, MatcapUV(positionWS, N)).rgb * _BaseColor.rgb;
                // Matcap 不认识场景里的灯，阴影只能“乘”上去：这是风格化里常见的折中
                NprLight L = GetNprLight(positionWS, N);
                col *= mix(1.0, L.shadow, _ShadowStrength);
                return vec4(col, 1.0);
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
