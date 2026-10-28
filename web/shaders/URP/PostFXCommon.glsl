// URP 后处理共用的小函数（Filtering.hlsl 的双三次采样等）

// Filtering.hlsl 的 SampleTexture2DBicubic（4 次双线性采样拼出 B 样条三次插值）
// texSize = (宽, 高, 1/宽, 1/高)
vec4 SampleTexture2DBicubic(sampler2D tex, vec2 coord, vec4 texSize, vec2 maxCoord)
{
    vec2 xy = coord * texSize.xy + 0.5;
    vec2 ic = floor(xy);
    vec2 fc = fract(xy);
    vec2 r  = 0.16666667 + fc * (-0.5 + fc * (0.5 - fc * 0.16666667));
    vec2 mr = 0.66666667 + fc * (-1.0 + 0.5 * fc) * fc;
    vec2 ml = 0.16666667 + fc * (0.5 + fc * (0.5 - fc * 0.5));
    vec2 l  = 1.0 - mr - ml - r;
    vec2 w0 = r + mr, w1 = ml + l;
    vec2 o0 = -1.0 + mr / w0, o1 = 1.0 + l / w1;
    return w0.y * (w0.x * textureLod(tex, min((ic + vec2(o0.x, o0.y) - 0.5) * texSize.zw, maxCoord), 0.0)
                 + w1.x * textureLod(tex, min((ic + vec2(o1.x, o0.y) - 0.5) * texSize.zw, maxCoord), 0.0))
         + w1.y * (w0.x * textureLod(tex, min((ic + vec2(o0.x, o1.y) - 0.5) * texSize.zw, maxCoord), 0.0)
                 + w1.x * textureLod(tex, min((ic + vec2(o1.x, o1.y) - 0.5) * texSize.zw, maxCoord), 0.0));
}

// Random.hlsl 的 InterleavedGradientNoise
float InterleavedGradientNoise(vec2 pixCoord, int frameCount)
{
    const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    vec2 frameMagicScale = vec2(2.083, 4.867);
    pixCoord += float(frameCount) * frameMagicScale;
    return fract(magic.z * fract(dot(pixCoord, magic.xy)));
}
