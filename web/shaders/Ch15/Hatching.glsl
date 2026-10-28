// 素描排线（Hatching）：按受光强度在 6 级笔触贴图（TAM）之间混合。（GLSL 版，对应 Ch15/Hatching.shader）
// 两张 RGB 贴图共 6 个通道，一次采样拿到 3 级，2 次采样完成全部混合。
Shader "Cookbook/Ch15/Hatching"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform float _HatchScale, _ScreenSpace, _ScreenTileSize;
        uniform vec4 _InkColor, _PaperColor, _BaseColor;
        uniform float _Tint, _Ambient, _Exposure;
        uniform float _OutlineWidth;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #define NPR_VARYINGS
            #include "Ch15/NPRCommon.glsl"

            uniform sampler2D _Hatch0;
            uniform sampler2D _Hatch1;

            #ifdef VERTEX
            void main() { NprVert(); }
            #endif

            #ifdef FRAGMENT
            //#region hatch
            // intensity：1 = 最亮（纸白），0 = 最暗（第 6 级）
            float Hatch(vec2 huv, float intensity)
            {
                vec3 h0 = texture(_Hatch0, huv).rgb;
                vec3 h1 = texture(_Hatch1, huv).rgb;

                // 把亮度映射到 0..6：0 = 纸白，k = 第 k 级笔触
                float level = (1.0 - intensity) * 6.0;
                // 帐篷形权重：离 level 最近的两级各分一部分，总和恒为 1
                vec3 w0 = saturate(1.0 - abs(level - vec3(1, 2, 3)));
                vec3 w1 = saturate(1.0 - abs(level - vec3(4, 5, 6)));
                float wWhite = saturate(1.0 - level);

                return wWhite + dot(h0, w0) + dot(h1, w1);
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                NprLight L = GetNprLight(positionWS, N);

                // 只关心“明暗”，不关心光的颜色：先算一个标量亮度
                float light = saturate(L.ndotl) * L.shadow * Luminance(L.color);
                float intensity = saturate((light * (1.0 - _Ambient) + _Ambient) * _Exposure);

                // 两种 UV：物体 UV（笔触贴在表面上）/ 屏幕 UV（笔触固定在画面上，每 _ScreenTileSize 像素重复一次）
                vec2 screenUV = gl_FragCoord.xy / _ScreenTileSize;
                vec2 huv = mix(uv * _HatchScale, screenUV, _ScreenSpace);

                float h = Hatch(huv, intensity);
                vec3 paper = _PaperColor.rgb * mix(vec3(1.0), _BaseColor.rgb, _Tint);
                vec3 col = mix(_InkColor.rgb, paper, h);
                return vec4(col, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            GLSLPROGRAM
            #ifdef VERTEX
            void main()
            {
                vec4 positionCS = TransformObjectToHClip(positionOS.xyz);
                vec3 normalCS = mat3(UNITY_MATRIX_VP) * TransformObjectToWorldNormal(normalOS);
                vec2 offset = normalize(normalCS.xy) * _OutlineWidth * positionCS.w;
                offset.x *= _ScreenParams.y / _ScreenParams.x;
                positionCS.xy += offset;
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = _InkColor; }
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
