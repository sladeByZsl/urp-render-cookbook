// 第 4 章：程序化图案用到的数学小工具（GLSL 版，对应 Ch04/ProceduralLib.hlsl）。PI、TWO_PI 等常量来自自动包含的 Core.glsl。
#ifndef COOKBOOK_CH04_PROCEDURAL_LIB_INCLUDED
#define COOKBOOK_CH04_PROCEDURAL_LIB_INCLUDED

//#region remap
// ---------------------------------------------------------------- 重映射与插值
// 把 x 从 [inMin, inMax] 线性映射到 [outMin, outMax]（不夹取）
// 注：网页版的 Core.glsl 已经有一个完全相同的 Remap，GLSL 不允许重复定义，这里只留作对照
// float Remap(float x, float inMin, float inMax, float outMin, float outMax)
// {
//     return outMin + (x - inMin) * (outMax - outMin) / (inMax - inMin);
// }

// smoothstep 去掉两端 S 形：纯线性的 0→1 过渡（Unity core 里也有同名思路的 Remap01）
float LinearStep(float edge0, float edge1, float x)
{
    return saturate((x - edge0) / (edge1 - edge0));
}
//#endregion

//#region rotate
// ---------------------------------------------------------------- 旋转与极坐标
// 绕原点逆时针旋转 angle 弧度
vec2 Rotate2D(vec2 p, float angle)
{
    float s = sin(angle), c = cos(angle);
    // HLSL 的 float2x2(c, -s, s, c) 按行构造；GLSL 的 mat2 按列构造，所以写成 mat2(c, s, -s, c)
    return mat2(c, s, -s, c) * p;
}

// 笛卡尔 → 极坐标：x = 半径 r，y = 角度归一化到 [0,1)（从 +X 轴逆时针）
vec2 ToPolar(vec2 p)
{
    float r = length(p);
    float a = atan(p.y, p.x);               // (-PI, PI]
    return vec2(r, fract(a / TWO_PI + 1.0)); // 映射到 [0,1)
}
//#endregion

//#region hash
// ---------------------------------------------------------------- 哈希：坐标 → 伪随机数
// PCG 风格的整数哈希：输入相同输出必相同，相邻输入的输出看起来毫无关联
uint PcgHash(uint v)
{
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// 2D 整数格子 → [0,1) 浮点
float Hash21(vec2 cell)
{
    ivec2 i = ivec2(floor(cell));
    uint h = PcgHash(uint(i.x) + PcgHash(uint(i.y)));   // int → uint 保留位模式，负数格子也没问题
    return float(h) * (1.0 / 4294967296.0);
}

// 2D 整数格子 → 两个 [0,1) 浮点
vec2 Hash22(vec2 cell)
{
    ivec2 i = ivec2(floor(cell));
    uint h1 = PcgHash(uint(i.x) + PcgHash(uint(i.y)));
    uint h2 = PcgHash(h1 ^ 0x9E3779B9u);
    return vec2(float(h1), float(h2)) * (1.0 / 4294967296.0);
}
//#endregion

//#region noise
// ---------------------------------------------------------------- 噪声
// Value Noise：格点上放随机“值”，格内平滑插值。结果在 [0,1]
float ValueNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = Hash21(i);
    float b = Hash21(i + vec2(1, 0));
    float c = Hash21(i + vec2(0, 1));
    float d = Hash21(i + vec2(1, 1));
    vec2 u = f * f * (3.0 - 2.0 * f);        // smoothstep 曲线 3t²-2t³
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 格点上的随机单位梯度方向
vec2 RandomGradient(vec2 cell)
{
    float a = Hash21(cell) * TWO_PI;
    return vec2(cos(a), sin(a));
}

// Gradient Noise（Perlin 思路）：格点上放随机“方向”，每个格点贡献 dot(梯度, 到该点的偏移)。结果约在 [-1,1]
float GradientNoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);  // 五次曲线 6t⁵-15t⁴+10t³，二阶导连续
    float n00 = dot(RandomGradient(i),               f);
    float n10 = dot(RandomGradient(i + vec2(1, 0)), f - vec2(1, 0));
    float n01 = dot(RandomGradient(i + vec2(0, 1)), f - vec2(0, 1));
    float n11 = dot(RandomGradient(i + vec2(1, 1)), f - vec2(1, 1));
    return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y) * 1.41421356;
}

// Simplex Noise（2D）：把平面切成等边三角形，每个点只受所在三角形 3 个顶点影响。结果约在 [-1,1]
float SimplexNoise(vec2 p)
{
    const float F2 = 0.36602540378;   // (√3 - 1) / 2：把平面“斜切”成方格
    const float G2 = 0.21132486540;   // (3 - √3) / 6：再切回来
    vec2 i  = floor(p + (p.x + p.y) * F2);             // 所在斜切格
    vec2 x0 = p - i + (i.x + i.y) * G2;                // 到第 1 个顶点的偏移
    vec2 o  = (x0.x > x0.y) ? vec2(1, 0) : vec2(0, 1); // 在上三角还是下三角
    vec2 x1 = x0 - o + G2;
    vec2 x2 = x0 - 1.0 + 2.0 * G2;
    vec3 w = max(0.5 - vec3(dot(x0, x0), dot(x1, x1), dot(x2, x2)), 0.0);
    w = w * w; w = w * w;                               // (0.5 - r²)⁴ 的径向衰减核
    vec3 n = vec3(dot(RandomGradient(i), x0),
                  dot(RandomGradient(i + o), x1),
                  dot(RandomGradient(i + 1.0), x2));
    return dot(w, n) * 70.0;
}
//#endregion

//#region voronoi
// Worley / Voronoi：每格放一个随机特征点，求到最近（F1）和次近（F2）特征点的距离
// phase 让特征点在格子内绕圈移动，用来做动画
vec2 VoronoiPoint(vec2 cell, float phase)
{
    vec2 h = Hash22(cell);
    return 0.5 + 0.4 * sin(phase + TWO_PI * h);   // 特征点在格内的位置，始终留在 [0.1,0.9]
}

void Voronoi(vec2 p, float phase, out float f1, out float f2, out vec2 nearestCell)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f1 = 8.0; f2 = 8.0; nearestCell = i;
    // F1 用 3×3 邻域就够；F2（次近点）可能在更远的格子里，所以搜 5×5
    for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++)
    {
        vec2 g = vec2(x, y);                           // 邻居格子相对偏移
        float d = length(g + VoronoiPoint(i + g, phase) - f);
        if (d < f1)      { f2 = f1; f1 = d; nearestCell = i + g; }
        else if (d < f2) { f2 = d; }
    }
}

// 到细胞边界的“真实”距离：边界是两个特征点连线的中垂线，
// 点到中垂线的距离 = dot(两点中点 - 当前点, 两点连线方向)
float VoronoiBorder(vec2 p, float phase)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    // 第一遍：找最近点（相对当前点的向量 mr）
    vec2 mg = vec2(0.0), mr = vec2(0.0); float md = 8.0;
    for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++)
    {
        vec2 g = vec2(x, y);
        vec2 r = g + VoronoiPoint(i + g, phase) - f;
        float d = dot(r, r);
        if (d < md) { md = d; mr = r; mg = g; }
    }
    // 第二遍：以最近点所在格为中心，对其余每个点求到中垂线的距离，取最小
    md = 8.0;
    for (int y2 = -2; y2 <= 2; y2++)
    for (int x2 = -2; x2 <= 2; x2++)
    {
        vec2 g = mg + vec2(x2, y2);
        vec2 r = g + VoronoiPoint(i + g, phase) - f;
        vec2 diff = r - mr;
        if (dot(diff, diff) > 1e-5)
            md = min(md, dot(0.5 * (mr + r), normalize(diff)));
    }
    return md;
}
//#endregion

//#region fbm
// fBm（分形布朗运动）：把同一种噪声以“频率 ×lacunarity、振幅 ×gain”叠加 octaves 层。结果约在 [-1,1]
float Fbm(vec2 p, int octaves, float lacunarity, float gain)
{
    float sum = 0.0, amp = 0.5, norm = 0.0;
    for (int k = 0; k < 10; k++)
    {
        if (k >= octaves) break;
        sum  += amp * GradientNoise(p);
        norm += amp;
        // 每层旋转一点再平移，避免各层格子方向对齐出现“十字纹”
        p = Rotate2D(p, 0.6) * lacunarity + vec2(17.3, -9.1);
        amp *= gain;
    }
    return sum / norm;
}
//#endregion

//#region sdf
// ---------------------------------------------------------------- 2D 有向距离场（SDF）：外部为正、内部为负、边界为 0
float SdCircle(vec2 p, float r)
{
    return length(p) - r;
}

// 轴对齐矩形，b = 半宽高
float SdBox(vec2 p, vec2 b)
{
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 圆角矩形：先把矩形缩小 r，再整体“膨胀” r
float SdRoundBox(vec2 p, vec2 b, float r)
{
    return SdBox(p, b - r) - r;
}

// 线段 ab（无粗细）；减去半宽就是胶囊
float SdSegment(vec2 p, vec2 a, vec2 b)
{
    vec2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

float OpUnion(float a, float b)     { return min(a, b); }
float OpSubtract(float a, float b)  { return max(a, -b); }   // a 挖掉 b
float OpIntersect(float a, float b) { return max(a, b); }

// 平滑并集：k 是融合半径，两个形状在 k 范围内“长”到一起
float OpSmoothUnion(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 抗锯齿填充：d<0 为 1，d>0 为 0，在边界一个像素宽度内平滑过渡
// （GLSL 的 fwidth 只能在片元着色器里用，顶点阶段即使没调用也会编译报错，所以加 #ifdef FRAGMENT）
#ifdef FRAGMENT
float FillAA(float d)
{
    float w = fwidth(d);
    return saturate(0.5 - d / max(w, 1e-6));
}
#endif
//#endregion

//#region bayer
// ---------------------------------------------------------------- 有序抖动：Bayer 矩阵
// levels = 1 → 2×2，2 → 4×4，3 → 8×8。返回 (0,1) 内均匀分布的阈值
// 递推关系 M(2n) = [4M+0, 4M+2; 4M+3, 4M+1]：越低的位权重越大
float BayerThreshold(uvec2 pixel, uint levels)
{
    uint v = 0u;
    for (uint i = 0u; i < 3u; i++)
    {
        if (i >= levels) break;
        uint x = (pixel.x >> i) & 1u;
        uint y = (pixel.y >> i) & 1u;
        uint m2 = ((x ^ y) << 1u) | y;            // 2×2 矩阵 [0 2; 3 1]
        v |= m2 << (2u * (levels - 1u - i));
    }
    float n = float(1u << (2u * levels));       // 4^levels 个阈值
    return (float(v) + 0.5) / n;
}
//#endregion

#endif
