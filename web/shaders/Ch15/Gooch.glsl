// Gooch 冷暖着色：用“冷→暖”的色相变化代替“暗→亮”的明度变化来表达朝向，（GLSL 版，对应 Ch15/Gooch.shader）
// 暗部不再是死黑，形体在技术插图里依旧清楚。附带白色高光与背面外扩描边。
Shader "Cookbook/Ch15/Gooch"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _CoolColor, _WarmColor, _OutlineColor;
        uniform float _Alpha, _Beta, _SpecPower, _SpecStrength, _ShadowCool;
        uniform float _OutlineWidth;
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
            //#region frag
            vec4 frag()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                NprLight L = GetNprLight(positionWS, N);

                // 1) 冷暖两端：纯冷/暖色 + 一部分物体本色
                vec3 kCool = _CoolColor.rgb + _Alpha * _BaseColor.rgb;
                vec3 kWarm = _WarmColor.rgb + _Beta  * _BaseColor.rgb;

                // 2) 用 (1 + N·L) / 2 在两端之间插值：背光面不是“没有光”，而是“偏冷”
                float t = (1.0 + L.ndotl) * 0.5;
                // 落在投影里的部分往冷端推一些（原始 Gooch 模型没有阴影，这是工程上的补充）
                t *= mix(1.0 - _ShadowCool, 1.0, L.shadow);
                vec3 col = mix(kCool, kWarm, t);

                // 3) 白色高光：Blinn-Phong，只在受光面出现
                vec3 H = normalize(L.direction + V);
                float spec = pow(saturate(dot(N, H)), _SpecPower) * _SpecStrength * L.shadow * step(0.0, L.ndotl);
                col += spec;

                col = MixFog(col, fogFactor);
                return vec4(col, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        // 背面外扩描边（第 14 章讲过的方法，这里只作为技术插图的黑色轮廓线）
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
                // 在裁剪空间沿法线外扩，乘 w 抵消透视除法，使线宽与距离无关
                vec2 offset = normalize(normalCS.xy) * _OutlineWidth * positionCS.w;
                offset.x *= _ScreenParams.y / _ScreenParams.x;   // 纠正宽高比
                positionCS.xy += offset;
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = _OutlineColor; }
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
