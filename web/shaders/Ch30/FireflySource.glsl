// 30.7 节问题现场四（错误示范）：数值异常的 Shader。少数像素的分母接近 0，算出极大的 HDR 值（“萤火虫”），（GLSL 版，对应 Ch30/FireflySource.shader）
// 再被 Bloom 放大成一团团光斑。同类问题还有 NaN（sqrt/log 参数为负、normalize 零向量、0/0）。
Shader "Cookbook/Ch30/FireflySource"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform vec4  _BaseColor;
            uniform float _BadRatio, _Fix;

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
            //#region firefly
            void main()
            {
                // 每个小格子一个随机数，模拟“偶尔为 0”的输入（例如某个几何项、某张贴图的通道）
                vec2 cell = floor(uv * 160.0);
                float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
                float denom = n < _BadRatio ? 1e-5 : n;       // 少数像素分母几乎为 0
                if (_Fix > 0.5) denom = max(denom, 0.05);      // 修复：给分母一个合理下限
                float boost = min(0.5 / denom, 1e5);           // 本意：0.5~几 的增益

                Light light = GetMainLight();
                vec3 diffuse = _BaseColor.rgb * (saturate(dot(normalize(normalWS), light.direction)) * light.color + 0.3);
                fragColor = vec4(diffuse * (0.85 + 0.15 * saturate(boost)) + boost * 0.002 * (boost > 50.0 ? 1.0 : 0.0), 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
