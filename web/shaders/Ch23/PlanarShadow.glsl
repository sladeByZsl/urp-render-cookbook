// 案例 23.3：平面投影阴影（Planar Shadow）（GLSL 版）。
// 第一个 Pass 正常着色；第二个 Pass（SRPDefaultUnlit）把同一个网格沿主光方向“拍扁”到地面上，
// 输出半透明的阴影色，并用模板测试保证同一个像素只被阴影覆盖一次，避免重叠部分变黑。
Shader "Cookbook/Ch23/PlanarShadow"
{
    SubShader
    {
        // 排在普通不透明物体之后，保证地面已经画好，阴影才能混合到地面颜色上
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry+10" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform vec4  _ShadowColor;
        uniform float _PlaneHeight;
        uniform float _ShadowFalloff;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            VARYING vec3 normalWS;
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 n = normalize(normalWS);
                Light l = GetMainLight();
                vec3 c = _BaseColor.rgb * (l.color * saturate(dot(n, l.direction)) + SampleSH(n));
                fragColor = vec4(c, 1);
            }
            #endif
            ENDGLSL
        }

        //#region planar
        Pass
        {
            Name "PlanarShadow"
            Tags { "LightMode"="SRPDefaultUnlit" }   // URP 会把它和 UniversalForward 一起画

            Stencil
            {
                Ref 1
                Comp [_StencilComp]   // NotEqual：这个像素还没画过阴影才画
                Pass Replace          // 画过就把模板写成 1，后面的阴影三角形再来就被拒绝
            }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            GLSLPROGRAM
            VARYING float fade;

            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                // _MainLightPosition.xyz 对方向光来说是“指向光源”的单位向量 L
                vec3 L = normalize(_MainLightPosition.xyz);

                // 求沿 -L 方向走多远能碰到平面 y = h：  P' = P - L * (P.y - h) / L.y
                float height = positionWS.y - _PlaneHeight;
                vec3 projected = positionWS - L * (height / max(L.y, 1e-3));
                projected.y = _PlaneHeight + 0.002;   // 抬高 2 毫米，避免与地面 Z-Fighting

                gl_Position = TransformWorldToHClip(projected);
                // 离地越高的部位投下的阴影越淡，模拟真实阴影随距离变软变淡
                fade = saturate(1.0 - height * _ShadowFalloff);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                fragColor = vec4(_ShadowColor.rgb, _ShadowColor.a * fade);
            }
            #endif
            ENDGLSL
        }
        //#endregion

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH23_DEPTH_PASS
            #include "Ch23/Ch23Common.glsl"
            ENDGLSL
        }
    }
}
