// 案例 21.1：UV 滚动——单层滚动 → 双层叠加 → UV 扰动 + 渐变映射，做出流动的熔岩（GLSL 版，对应 Ch21/UVScroll.shader）
Shader "Cookbook/Ch21/UVScroll"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            uniform vec4 _Layer1, _Layer2;
            uniform float _SecondLayer, _Distort, _UseRamp, _Intensity;
            uniform float _Phase;
            uniform sampler2D _NoiseTex;
            uniform sampler2D _RampTex;

            VARYING vec2 uv;
            VARYING float fog;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy;
                fog = ComputeFogFactor(gl_Position.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                // 时间：运行时用 _Time.y，配图时 _Time 不可控，用 _Phase 指定“第几秒”
                // fract 把偏移量限制在 0..1：贴图是 Repeat 寻址，结果不变，但避免长时间运行后浮点精度下降
                float t = _Time.y + _Phase;
                vec2 off1 = fract(_Layer1.zw * t);
                vec2 off2 = fract(_Layer2.zw * t);

                // 第二层：既参与叠加，也用来扰动第一层的 UV
                float n2 = texture(_NoiseTex, uv * _Layer2.xy + off2).r;
                vec2 distort = vec2((n2 - 0.5) * _Distort * _SecondLayer);
                float n1 = texture(_NoiseTex, uv * _Layer1.xy + off1 + distort).r;

                float v = mix(n1, n1 * n2 * 2.0, _SecondLayer);     // 两层相乘再 ×2，保持平均亮度
                v = saturate(v);

                vec3 col = vec3(v);
                if (_UseRamp > 0.5)
                {
                    // 渐变映射：灰度 → 颜色。暗处是冷却的黑色岩壳，亮处是高温的黄白色
                    float k = smoothstep(0.3, 1.0, v);
                    col = texture(_RampTex, vec2(k, 0.5)).rgb * (k * k * _Intensity);
                }
                col = MixFog(col, fog);
                return vec4(col, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
