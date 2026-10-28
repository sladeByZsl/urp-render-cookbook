// 案例 21.4：极坐标漩涡传送门——角度 + 半径当 UV，扭转、旋转、向内吸入；顺带处理 atan2 接缝（GLSL 版，对应 Ch21/Portal.shader）
Shader "Cookbook/Ch21/Portal"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Blend One One          // 叠加发光：越叠越亮，不需要排序
            ZWrite Off
            Cull Off
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #include "Ch21/UVAnim.glsl"

            uniform vec4 _ColorInner, _ColorOuter;
            uniform float _Arms, _Twist, _Spin, _Inward, _RadialTiling;
            uniform float _Contrast;
            uniform float _Phase;
            uniform float _FixSeam, _Debug;
            uniform sampler2D _NoiseTex;

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy;
            }
            #endif

            #ifdef FRAGMENT
            //#region swirl
            vec2 SwirlUV(vec2 polar, float t, float spin)
            {
                // x：角度 × 臂数（必须是整数才能首尾相接）+ 半径 × 扭转（越往里转得越多）+ 时间旋转
                // y：半径 × 平铺 − 时间（图案不断向中心流）
                return vec2(polar.x * _Arms + polar.y * _Twist + t * spin,
                            polar.y * _RadialTiling - t * _Inward);
            }

            // 带接缝修正的采样：atan2 在 ±π 处从 1 跳回 0，硬件按 2×2 像素块求导会得到巨大的 ddx，
            // 于是选中最低一级 mip，在接缝上画出一条线。修正：另算一份“接缝挪到对面”的角度，取较小的导数
            float SampleSwirl(vec2 polar, float t, float spin)
            {
                vec2 suv = SwirlUV(polar, t, spin);
                vec2 dx = dFdx(suv), dy = dFdy(suv);
                if (_FixSeam > 0.5)
                {
                    vec2 uvAlt = SwirlUV(vec2(fract(polar.x + 0.5), polar.y), t, spin);
                    vec2 dxAlt = dFdx(uvAlt), dyAlt = dFdy(uvAlt);
                    dx.x = abs(dx.x) < abs(dxAlt.x) ? dx.x : dxAlt.x;
                    dy.x = abs(dy.x) < abs(dyAlt.x) ? dy.x : dyAlt.x;
                }
                return textureGrad(_NoiseTex, suv, dx, dy).r;
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                vec2 polar = ToPolar(uv, vec2(0.5, 0.5));
                float t = _Time.y + _Phase;

                if (_Debug > 0.5 && _Debug < 1.5) return vec4(polar.x, polar.y, 0.0, 1.0);
                if (_Debug > 1.5 && _Debug < 2.5) return vec4(fract(SwirlUV(polar, t, _Spin)), 0.0, 1.0);
                // 只看一层漩涡噪声并二值化：接缝处取到最低级 mip（≈ 平均灰），在黑白图案里显出一道灰线
                if (_Debug > 3.5) { vec2 u = SwirlUV(polar, t, _Spin); float d = max(length(dFdx(u)), length(dFdy(u))); return vec4(vec3(saturate(log2(d * 512.0) / 10.0)), 1.0); }
                if (_Debug > 2.5) return vec4(vec3(smoothstep(0.5, 0.7, SampleSwirl(polar, t, _Spin))), 1.0);

                // 两层速度不同的漩涡相乘，图案更“活”
                float n1 = SampleSwirl(polar, t, _Spin);
                float n2 = SampleSwirl(polar * vec2(1, 0.7), t * 1.3, -_Spin * 0.6);
                float swirl = pow(saturate(n1 * n2 * 2.0), _Contrast);

                float r = polar.y;
                float disc = smoothstep(1.0, 0.8, r);                     // 外缘淡出
                float rim  = exp(-pow((r - 0.86) * 9.0, 2.0));            // 外圈一道亮环
                float core = exp(-r * r * 18.0);                          // 中心光核
                vec3 col = mix(_ColorInner.rgb, _ColorOuter.rgb, saturate(r * 1.2));
                vec3 result = col * (swirl * disc + rim * 0.8) + _ColorInner.rgb * core;
                return vec4(result, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
