// 30.7 节问题现场四（错误示范）：在少数像素上产生 NaN 的 Shader。（GLSL 版，对应 Ch30/NaNSource.shader）
// 现实中的来源：sqrt/pow/log 的参数为负、normalize 零向量、0/0。
Shader "Cookbook/Ch30/NaNSource"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform vec4  _BaseColor;
            uniform float _BadRatio;
            uniform uint  _NaNBits;

            VARYING vec3 normalWS;
            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = texcoord0.xy;
            }
            #endif

            #ifdef FRAGMENT
            //#region nan
            void main()
            {
                vec2 cell = floor(uv * 160.0);
                float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
                // 现实里的写法类似 float k = sqrt(n - _BadRatio); —— 少数像素参数为负，结果是 NaN。
                // sqrt(负数) 和写死的 NaN 常量都可能被编译器的快速数学优化“优化掉”，为了让演示可重复，
                // 这里用运行时传入的 NaN 位模式（指数全 1、尾数非 0）。
                // 网页版：C# 的 Shader.SetGlobalInteger 不会导出，没设置时（为 0）就用 0x7FC00000，uniform 同样无法被编译器提前折叠
                uint bits = _NaNBits == 0u ? 0x7FC00000u : _NaNBits;
                float k = sqrt(n);
                if (n < _BadRatio) k = uintBitsToFloat(bits);   // HLSL 的 asfloat
                Light light = GetMainLight();
                vec3 color = _BaseColor.rgb * (saturate(dot(normalize(normalWS), light.direction)) * light.color + 0.3);
                fragColor = vec4(color * (0.8 + 0.2 * k), 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
