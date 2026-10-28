// 镂空材质的三种做法（GLSL 版）：
//   Alpha Clip：clip() 硬裁剪，边缘锯齿，远处细线会因 mip 平均而消失；
//   Alpha to Coverage（A2C）：把 alpha 转成 MSAA 的覆盖掩码，边缘有 MSAA 级别的过渡（需要开 MSAA）；
//   A2C + 锐化：用 fwidth 把 alpha 重新拉成“一个像素宽的过渡”，既保住细线又不发虚。
Shader "Cookbook/Ch16/Cutout"
{
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        GLSLINCLUDE
        #include "Ch16/Ch16Common.glsl"
        uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform float _Cutoff;
        uniform float _AlphaToMask, _Sharpen, _MipScale;
        uniform vec4 _BaseMap_TexelSize;
        uniform sampler2D _BaseMap;

        #ifdef FRAGMENT
        //#region alpha
        float CutoutAlpha(vec2 uv)
        {
            float a = texture(_BaseMap, uv).a * _BaseColor.a;
            if (_MipScale > 0.5)
            {
                // 远处 mip 把细线和透明背景平均成很低的 alpha，裁剪后线条就“断”了。
                // 按 mip 级别把 alpha 放大一些，抵消平均带来的损失（经验做法，系数可调）
                vec2 texel = uv * _BaseMap_TexelSize.zw;
                vec2 dx = dFdx(texel), dy = dFdy(texel);
                float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
                a *= 1.0 + mip * 0.3;
            }
            return a;
        }
        //#endregion
        #endif
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off
            AlphaToMask [_AlphaToMask]
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { Ch16Vert(); }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec2 uvT = TransformTex(uv, _BaseMap_ST);
                vec4 tex = texture(_BaseMap, uvT);
                float a = CutoutAlpha(uvT);

                if (_AlphaToMask > 0.5)
                {
                    if (_Sharpen > 0.5)
                    {
                        // 以 cutoff 为中心，把 alpha 的过渡压缩到约一个像素宽
                        a = (a - _Cutoff) / max(fwidth(a), 1e-4) + 0.5;
                    }
                    a = saturate(a);
                }
                else
                {
                    if (a - _Cutoff < 0.0) discard;    // 经典 Alpha Test
                    a = 1.0;
                }

                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                vec3 col = SimpleLighting(tex.rgb * _BaseColor.rgb, N, positionWS, 0.2);
                fragColor = vec4(col, a);     // 开启 A2C 时，这个 alpha 决定 MSAA 子样本覆盖了几个
            }
            //#endregion
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            GLSLPROGRAM
            VARYING vec2 uvS;
            #ifdef VERTEX
            void main()
            {
                gl_Position = Ch16ShadowPositionCS(positionOS.xyz, normalOS);
                uvS = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif
            #ifdef FRAGMENT
            // 阴影贴图没有 MSAA，只能用硬裁剪
            void main() { if (CutoutAlpha(uvS) - _Cutoff < 0.0) discard; fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Off
            GLSLPROGRAM
            VARYING vec2 uvS;
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uvS = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif
            #ifdef FRAGMENT
            void main() { if (CutoutAlpha(uvS) - _Cutoff < 0.0) discard; fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
