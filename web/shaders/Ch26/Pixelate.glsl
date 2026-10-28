// 案例 26.7：像素化。把 UV 吸附到“大像素”中心，用点采样取色；再在 sRGB 空间做色阶量化 + Bayer 抖动。
Shader "Cookbook/Ch26/Pixelate"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "Pixelate"
            GLSLPROGRAM
            uniform vec4 _PixelateParams;   // x 像素尺寸, y 色阶数, z 抖动强度

            VARYING vec2 texcoord;
            #ifdef VERTEX
            // Blit.hlsl 的 Vert：用 gl_VertexID 生成盖住全屏的大三角形（_BlitTexture、_BlitTexture_TexelSize 等在 Core.glsl 里声明）
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            #ifdef FRAGMENT
            // 4×4 Bayer 矩阵，返回 [0,1) 的阈值
            float Bayer4(uvec2 p)
            {
                const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
                return m[(p.y & 3u) * 4u + (p.x & 3u)] / 16.0;
            }

            //#region frag
            vec4 Frag()
            {
                vec2 screen = _ScreenParams.xy;
                float size = _PixelateParams.x;

                // 1) 当前像素属于哪个“大像素”，取它中心的颜色（点采样，避免边缘被双线性混色）
                vec2 block = floor(texcoord * screen / size);
                vec2 uv = (block + 0.5) * size / screen;
                // GLSL 不能按调用指定 sampler_PointClamp：用 texelFetch 按整数纹素坐标取
                ivec2 texSize = textureSize(_BlitTexture, 0);
                vec3 c = texelFetch(_BlitTexture, clamp(ivec2(uv * vec2(texSize)), ivec2(0), texSize - 1), 0).rgb;

                // 2) 色阶量化：在 sRGB 空间均匀分级（线性空间分级会让暗部台阶过粗）
                float levels = _PixelateParams.y;
                if (levels > 0.5)
                {
                    vec3 s = LinearToSRGB(saturate(c));
                    float threshold = (Bayer4(uvec2(block)) - 0.5) * _PixelateParams.z;   // 以大像素为单位抖动
                    s = floor(s * (levels - 1.0) + 0.5 + threshold) / (levels - 1.0);
                    c = SRGBToLinear(saturate(s));
                }
                return vec4(c, 1.0);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
