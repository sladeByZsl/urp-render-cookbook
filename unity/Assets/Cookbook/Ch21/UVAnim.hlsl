// 第 21 章公共函数：序列帧 UV、Flowmap 双相位、极坐标
#ifndef COOKBOOK_CH21_UVANIM_INCLUDED
#define COOKBOOK_CH21_UVANIM_INCLUDED

//#region flipbookUV
// 第 frame 帧在图集中的 UV。约定：第 0 帧在左上角，从左到右、从上到下排列（与 Unity 粒子的 Texture Sheet Animation 一致）。
// 纹理坐标的 V 轴向上，所以“第 0 行”对应 V 最大的那一行。
float2 FlipbookUV(float2 uv, float frame, float2 grid)
{
    float total = grid.x * grid.y;
    frame = fmod(floor(frame), total);           // 播完从头循环
    float col = fmod(frame, grid.x);
    float row = floor(frame / grid.x);
    return (uv + float2(col, grid.y - 1.0 - row)) / grid;
}
//#endregion

//#region flowmap
// Flowmap 双相位采样：两套相位差半个周期的 UV，各自沿流向“漂”，权重呈三角波交替。
// 某一相位重置（跳回原位）的瞬间，它的权重恰好为 0，所以看不到跳变。
struct FlowSample
{
    float2 uv0, uv1;
    float  w0;           // 第一套的权重，第二套为 1 - w0
};

FlowSample FlowUV(float2 uv, float2 flow, float time)
{
    FlowSample s;
    float p0 = frac(time);
    float p1 = frac(time + 0.5);
    s.uv0 = uv - flow * p0;
    s.uv1 = uv - flow * p1 + float2(0.37, 0.21);  // 第二套错开一点，避免两层图案重合时出现“重影节拍”
    s.w0 = 1.0 - abs(1.0 - 2.0 * p0);             // p0 = 0 或 1（重置时）权重为 0，p0 = 0.5 时为 1
    return s;
}
//#endregion

//#region polar
// 直角坐标 → 极坐标：x = 角度（0..1，一圈），y = 半径（中心 0，四边中点 1）
float2 ToPolar(float2 uv, float2 center)
{
    float2 d = uv - center;
    float angle = atan2(d.y, d.x) * (0.5 * INV_PI) + 0.5;
    float radius = length(d) * 2.0;
    return float2(angle, radius);
}
//#endregion

#endif
