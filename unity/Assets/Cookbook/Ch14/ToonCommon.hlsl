// 第 14 章卡通渲染的公共代码：顶点结构、色阶、边缘光、风格化高光、描边顶点外扩。
// 各个案例 Shader 与最终的 ToonLit 都 include 它。
#ifndef COOKBOOK_CH14_TOON_COMMON_INCLUDED
#define COOKBOOK_CH14_TOON_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct ToonAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
    float4 color      : COLOR;
    float2 uv         : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct ToonVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS   : TEXCOORD2;
    float4 tangentWS  : TEXCOORD3;
    float3 positionOS : TEXCOORD4;   // 脸部 SDF 用物体空间坐标做投影 UV
    float  fogFactor  : TEXCOORD5;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

ToonVaryings ToonVert(ToonAttributes input)
{
    ToonVaryings o = (ToonVaryings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);
    VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
    VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    o.positionCS = pos.positionCS;
    o.positionWS = pos.positionWS;
    o.positionOS = input.positionOS.xyz;
    o.normalWS = nrm.normalWS;
    o.tangentWS = float4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
    o.uv = input.uv;
    o.fogFactor = ComputeFogFactor(pos.positionCS.z);
    return o;
}

//#region band
// 色阶：把连续的 0~1 明暗压成“亮 / 暗”两档，softness 控制交界的宽度（0 = 硬边）
half ToonBand(half x, half threshold, half softness)
{
    return smoothstep(threshold - softness, threshold + softness, x);
}
//#endregion

//#region rim
// 菲涅尔边缘光：越靠近轮廓（N·V → 0）越亮，再做一次色阶得到“一条线”
half FresnelRim(half3 N, half3 V, half width, half softness)
{
    half f = 1.0 - saturate(dot(N, V));
    return ToonBand(f, 1.0 - width, softness);
}
//#endregion

//#region spec
// 风格化高光（思路来自 Anjyo & Hiramitsu 2003）：在切线空间里对半角向量 H 做平移、缩放、分裂，
// 最后用“高光区域的形状”切出硬边。T/B 是表面的切线与副切线。
half StylizedSpecular(half3 N, half3 T, half3 B, half3 H, half4 shiftScale, half2 split, half square, half threshold, half softness)
{
    H = normalize(H + shiftScale.x * T + shiftScale.y * B);                 // 平移：整体挪动高光
    H = normalize(H - shiftScale.z * dot(H, T) * T - shiftScale.w * dot(H, B) * B);   // 方向缩放：拉长/压扁
    H = normalize(H - split.x * sign(dot(H, T)) * T - split.y * sign(dot(H, B)) * B); // 分裂：一分为二/四
    // 方形化：H 在切平面上的分量 (x, y) 的长度就是 sin(N,H)。“N·H ≥ 阈值”等价于“长度 ≤ sin(阈值角)”。
    // 把长度换成 Lp 范数，p = 2 是圆，p 越大越接近正方形
    half2 xy = abs(half2(dot(H, T), dot(H, B)));
    half p = lerp(2.0, 10.0, square);
    half d = pow(pow(xy.x, p) + pow(xy.y, p), 1.0 / p);
    half sinTh = sqrt(saturate(1.0 - threshold * threshold));
    return smoothstep(-softness, softness, sinTh - d) * step(0.0, dot(N, H));
}
//#endregion

//#region strand
// 发丝高光的核心（Kajiya-Kay）：沿发丝方向 T 的“圆柱”高光，sin(T,H) 越接近 1 越亮
half StrandSpecular(half3 T, half3 N, half3 H, half shift, half exponent)
{
    T = normalize(T + shift * N);              // 沿法线挪动切线 = 让高光带上下移动
    half ToH = dot(T, H);
    half sinTH = sqrt(saturate(1.0 - ToH * ToH));
    return smoothstep(-1.0, 0.0, ToH) * pow(sinTH, exponent);
}
//#endregion

//#region outline
// 描边外扩：在裁剪空间沿法线方向推开固定的像素宽度。
//   normalOS：用于外扩的法线（可以是平滑后的法线）；widthPx：线宽（像素）
float4 OutlinePositionCS(float3 positionOS, float3 normalOS, float widthPx)
{
    float4 positionCS = TransformObjectToHClip(positionOS);
    float3 normalWS = TransformObjectToWorldNormal(normalOS);
    float3 normalCS = TransformWorldToHClipDir(normalWS, true);   // 方向向量只受 VP 的 3×3 部分影响
    // 先把方向换到“像素空间”再归一化：NDC 的 x、y 一个单位对应的像素数不同（宽高比），
    // 直接 normalize(normalCS.xy) 会让横向和纵向的线宽不一致
    float2 dirPx = normalize(normalCS.xy * _ScreenParams.xy + 1e-6);
    // NDC 的 [-1,1] 对应整个屏幕，所以 1 像素 = 2 / 屏幕尺寸；乘 w 是为了抵消之后的透视除法
    float2 offset = dirPx * widthPx * 2.0 / _ScreenParams.xy;
    positionCS.xy += offset * positionCS.w;
    return positionCS;
}

// 对照组：物体空间外扩（线宽随距离变化，近粗远细）
float4 OutlinePositionCS_ObjectSpace(float3 positionOS, float3 normalOS, float width)
{
    return TransformObjectToHClip(positionOS + normalize(normalOS) * width);
}
//#endregion

#endif
