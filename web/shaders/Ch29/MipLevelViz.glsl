// 案例 29.6：Mip 级别可视化。用屏幕空间导数估算 GPU 会选哪一级 Mip，并按级别着色。（GLSL 版，对应 Ch29/MipLevelViz.shader）
// 级别越高 = 一个像素覆盖的纹素越多；如果近处也是高级别，说明贴图分辨率给多了（浪费带宽和内存）。
Shader "Cookbook/Ch29/MipLevelViz"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "MipViz"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform sampler2D _BaseMap;
            uniform vec4 _BaseMap_TexelSize;   // (1/w, 1/h, w, h)，由引擎自动设置
            uniform vec4 _BaseMap_ST;
            uniform float _Blend;

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region mip
            float ComputeMipLevel(vec2 uv, vec2 texSize)
            {
                // 相邻像素之间 uv 变化了多少个纹素
                vec2 dx = dFdx(uv * texSize);
                vec2 dy = dFdy(uv * texSize);
                float maxSq = max(dot(dx, dx), dot(dy, dy));
                return 0.5 * log2(maxSq);   // = log2(最大纹素跨度)；<0 表示放大（一个纹素盖住多个像素）
            }

            vec3 MipColor(float mip)
            {
                const vec3 c[7] = vec3[7](vec3(0.1, 0.35, 1), vec3(0.15, 0.8, 0.3), vec3(0.95, 0.9, 0.15),
                                          vec3(1, 0.55, 0.1), vec3(0.95, 0.15, 0.1), vec3(0.8, 0.1, 0.7), vec3(0.35, 0.1, 0.5));
                // c[0] 给“放大”区（mip<0），c[1] 起依次是 mip 0,1,2...
                float m = clamp(mip + 1.0, 0.0, 6.0);
                int i = int(floor(m));
                return mix(c[i], c[min(i + 1, 6)], fract(m));
            }
            //#endregion

            void main()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb;
                float mip = ComputeMipLevel(uv, _BaseMap_TexelSize.zw);
                fragColor = vec4(mix(albedo, MipColor(mip), _Blend), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
