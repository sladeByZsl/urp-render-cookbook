// 案例 29.4：half 精度不够用的典型现场——远离原点时用 half 存世界坐标再算 UV。（GLSL 版，对应 Ch29/HalfPrecisionDemo.shader）
// 桌面平台常把 half 当 float 执行，看不出问题；这里按 half 的格式（10 位尾数）手动把数值舍入到
// 它能表示的最近值，模拟它在移动 GPU 上真正以 16 位存储时的样子。
// （GLSL ES 的 mediump 在桌面浏览器上同样常被当成 highp 执行，所以网页版也用同样的手动舍入来模拟）
Shader "Cookbook/Ch29/HalfPrecisionDemo"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Demo"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform sampler2D _BaseMap;
            uniform vec4 _BaseMap_ST;
            uniform float _Tiling, _EmulateHalf;

            VARYING vec3 positionWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            // half：1 位符号 + 5 位指数 + 10 位尾数。数值落在 [2^e, 2^(e+1)) 时，相邻两个可表示值相差 2^(e-10)
            vec2 ToHalfAndBack(vec2 v)
            {
                vec2 e = floor(log2(max(abs(v), vec2(6.1e-5))));   // 6.1e-5 ≈ half 最小正规数
                vec2 ulp = exp2(e - 10.0);
                return round(v / ulp) * ulp;
            }

            void main()
            {
                vec2 p = positionWS.xz;
                if (_EmulateHalf > 0.5) p = ToHalfAndBack(p);      // 相当于 half2 p = positionWS.xz;
                vec2 uv = p * _Tiling;
                vec3 c = texture(_BaseMap, uv).rgb;
                fragColor = vec4(c, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
