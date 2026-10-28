// 第 14 章卡通渲染的公共代码：顶点结构、色阶、边缘光、风格化高光、描边顶点外扩。
// 各个案例 Shader 与最终的 ToonLit 都 include 它。（GLSL 版，对应 Ch14/ToonCommon.hlsl）
// GLSL 版的用法：着色 Pass 先 #define TOON_VARYINGS 再 include，得到 ToonVaryings 对应的 varying 变量和 ToonVert()；
// 描边 Pass 不定义它，只用下面的函数。
#ifndef COOKBOOK_CH14_TOON_COMMON_INCLUDED
#define COOKBOOK_CH14_TOON_COMMON_INCLUDED

#ifdef TOON_VARYINGS
// ToonVaryings（WebGL 不允许结构体做 varying，拆成单独的变量）
VARYING vec2  uv;
VARYING vec3  positionWS;
VARYING vec3  normalWS;
VARYING vec4  tangentWS;
VARYING vec3  objectPositionOS;   // 脸部 SDF 用物体空间坐标做投影 UV（顶点输入已占用 positionOS 这个名字）
VARYING float fogFactor;

#ifdef VERTEX
void ToonVert()
{
    VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
    VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
    gl_Position = pos.positionCS;
    positionWS = pos.positionWS;
    objectPositionOS = positionOS.xyz;
    normalWS = nrm.normalWS;
    tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
    uv = texcoord0.xy;
    fogFactor = ComputeFogFactor(pos.positionCS.z);
}
#endif
#endif

//#region band
// 色阶：把连续的 0~1 明暗压成“亮 / 暗”两档，softness 控制交界的宽度（0 = 硬边）
float ToonBand(float x, float threshold, float softness)
{
    return smoothstep(threshold - softness, threshold + softness, x);
}
//#endregion

//#region rim
// 菲涅尔边缘光：越靠近轮廓（N·V → 0）越亮，再做一次色阶得到“一条线”
float FresnelRim(vec3 N, vec3 V, float width, float softness)
{
    float f = 1.0 - saturate(dot(N, V));
    return ToonBand(f, 1.0 - width, softness);
}
//#endregion

//#region spec
// 风格化高光（思路来自 Anjyo & Hiramitsu 2003）：在切线空间里对半角向量 H 做平移、缩放、分裂，
// 最后用“高光区域的形状”切出硬边。T/B 是表面的切线与副切线。
float StylizedSpecular(vec3 N, vec3 T, vec3 B, vec3 H, vec4 shiftScale, vec2 split, float square, float threshold, float softness)
{
    H = normalize(H + shiftScale.x * T + shiftScale.y * B);                 // 平移：整体挪动高光
    H = normalize(H - shiftScale.z * dot(H, T) * T - shiftScale.w * dot(H, B) * B);   // 方向缩放：拉长/压扁
    H = normalize(H - split.x * sign(dot(H, T)) * T - split.y * sign(dot(H, B)) * B); // 分裂：一分为二/四
    // 方形化：H 在切平面上的分量 (x, y) 的长度就是 sin(N,H)。“N·H ≥ 阈值”等价于“长度 ≤ sin(阈值角)”。
    // 把长度换成 Lp 范数，p = 2 是圆，p 越大越接近正方形
    vec2 xy = abs(vec2(dot(H, T), dot(H, B)));
    float p = mix(2.0, 10.0, square);
    float d = pow(pow(xy.x, p) + pow(xy.y, p), 1.0 / p);
    float sinTh = sqrt(saturate(1.0 - threshold * threshold));
    return smoothstep(-softness, softness, sinTh - d) * step(0.0, dot(N, H));
}
//#endregion

//#region strand
// 发丝高光的核心（Kajiya-Kay）：沿发丝方向 T 的“圆柱”高光，sin(T,H) 越接近 1 越亮
float StrandSpecular(vec3 T, vec3 N, vec3 H, float shift, float exponent)
{
    T = normalize(T + shift * N);              // 沿法线挪动切线 = 让高光带上下移动
    float ToH = dot(T, H);
    float sinTH = sqrt(saturate(1.0 - ToH * ToH));
    return smoothstep(-1.0, 0.0, ToH) * pow(sinTH, exponent);
}
//#endregion

//#region outline
// 描边外扩：在裁剪空间沿法线方向推开固定的像素宽度。
//   normalOS：用于外扩的法线（可以是平滑后的法线）；widthPx：线宽（像素）
vec4 OutlinePositionCS(vec3 posOS, vec3 nrmOS, float widthPx)
{
    vec4 positionCS = TransformObjectToHClip(posOS);
    vec3 nWS = TransformObjectToWorldNormal(nrmOS);
    vec3 normalCS = mat3(unity_MatrixVP) * nWS;   // 方向向量只受 VP 的 3×3 部分影响（= TransformWorldToHClipDir）
    // 先把方向换到“像素空间”再归一化：NDC 的 x、y 一个单位对应的像素数不同（宽高比），
    // 直接 normalize(normalCS.xy) 会让横向和纵向的线宽不一致
    vec2 dirPx = normalize(normalCS.xy * _ScreenParams.xy + 1e-6);
    // NDC 的 [-1,1] 对应整个屏幕，所以 1 像素 = 2 / 屏幕尺寸；乘 w 是为了抵消之后的透视除法
    vec2 offset = dirPx * widthPx * 2.0 / _ScreenParams.xy;
    positionCS.xy += offset * positionCS.w;
    return positionCS;
}

// 对照组：物体空间外扩（线宽随距离变化，近粗远细）
vec4 OutlinePositionCS_ObjectSpace(vec3 posOS, vec3 nrmOS, float width)
{
    return TransformObjectToHClip(posOS + normalize(nrmOS) * width);
}
//#endregion

#endif
