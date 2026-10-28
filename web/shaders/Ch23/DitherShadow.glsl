// 案例 23.8：半透明物体的抖动阴影（Dithered Shadow）（GLSL 版）。
// 阴影贴图只存一个深度，表达不了“半透明”。办法是在 ShadowCaster 里按透明度用 Bayer 矩阵
// 有规律地丢掉一部分像素：alpha = 0.3 就大约只留 30% 的阴影像素，再经过软阴影 PCF 一平均，
// 接收端看到的就是“30% 浓度”的阴影。
Shader "Cookbook/Ch23/DitherShadow"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _DitherShadow;
        uniform float _ShadowAlphaScale;
        uniform sampler2D _BaseMap;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            GLSLPROGRAM
            VARYING vec2 uv;
            VARYING vec3 normalWS;
            VARYING vec3 positionWS;
            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS; positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec4 tex = texture(_BaseMap, uv) * _BaseColor;
                vec3 n = normalize(normalWS);
                Light l = GetMainLight();
                vec3 v = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 h = normalize(l.direction + v);
                float spec = pow(saturate(dot(n, h)), 64.0) * 0.6;
                vec3 c = tex.rgb * (l.color * saturate(dot(n, l.direction)) + SampleSH(n)) + spec * l.color;
                fragColor = vec4(c, tex.a);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            Cull Back

            GLSLPROGRAM
            #include "Ch23/Ch23Common.glsl"
            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = Ch23ShadowCasterVert();
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region dither
            // 4×4 Bayer 矩阵：相邻阈值尽量分散，丢弃的像素在空间上均匀
            const float kBayer4x4[16] = float[16](
                 0.0,  8.0,  2.0, 10.0,
                12.0,  4.0, 14.0,  6.0,
                 3.0, 11.0,  1.0,  9.0,
                15.0,  7.0, 13.0,  5.0
            );

            void main()
            {
                float alpha = texture(_BaseMap, uv).a * _BaseColor.a * _ShadowAlphaScale;
                if (_DitherShadow > 0.5)
                {
                    // 在 ShadowCaster 里，gl_FragCoord.xy 就是阴影贴图上的像素坐标
                    uvec2 p = uvec2(gl_FragCoord.xy) & 3u;
                    float threshold = (kBayer4x4[p.y * 4u + p.x] + 0.5) / 16.0;
                    if (alpha - threshold < 0.0) discard;
                }
                fragColor = vec4(0.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
