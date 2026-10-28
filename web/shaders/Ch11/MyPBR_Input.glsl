// MyPBR 的材质输入：属性 CBUFFER、贴图声明、从贴图读出“表面参数”。
// 这里只做“读数据”，不做任何光照计算。（GLSL 版，对应 Ch11/MyPBR_Input.hlsl）
#ifndef COOKBOOK_MYPBR_INPUT_INCLUDED
#define COOKBOOK_MYPBR_INPUT_INCLUDED

//#region cbuffer
// 所有材质属性（贴图除外）都放进 UnityPerMaterial，且每个 Pass 看到的布局完全一致，
// 这是 SRP Batcher 兼容的硬条件。贴图本身不进 CBUFFER，但 _ST 要进。
// （WebGL 没有 SRP Batcher，这里都是普通 uniform）
uniform vec4  _BaseMap_ST;
uniform vec4  _BaseColor;
uniform float _Metallic;
uniform float _Smoothness;
uniform float _OcclusionStrength;
uniform float _BumpScale;
uniform vec4  _EmissionColor;
uniform float _Cutoff;
uniform float _EnergyCompensation;   // 0 = 只算单次散射，1 = 加多次散射能量补偿
uniform float _SpecularOcclusion;    // 0 = 关，1 = 用 AO 推算镜面遮蔽

uniform sampler2D _BaseMap;
uniform sampler2D _MaskMap;      // R 金属度  G AO  A 光滑度（与配套贴图约定一致）
uniform sampler2D _BumpMap;
uniform sampler2D _EmissionMap;
uniform sampler2D _DFGLut;       // 程序生成的环境 BRDF 查找表（RG = A, B），贴图自身是双线性 + Clamp
// HLSL 版里 Mask 与自发光借用 _BaseMap 的采样器以节省采样器槽位；GLSL 的 sampler2D 自带采样状态，没有这个问题。
//#endregion

//#region surface
// 表面参数：全部在“线性空间、物理含义明确”的单位下
struct MySurface
{
    vec3  albedo;               // 基础色（金属时就是 F0 的颜色）
    float alpha;
    float metallic;
    float perceptualRoughness;  // 感知粗糙度 = 1 - smoothness，美术直接调的那个值
    float occlusion;            // 材质 AO（只影响间接光）
    vec3  normalTS;             // 切线空间法线
    vec3  emission;
};

#ifdef FRAGMENT
MySurface MySampleSurface(vec2 uv)
{
    MySurface s;
    vec4 base = texture(_BaseMap, uv) * _BaseColor;
    s.albedo = base.rgb;
    s.alpha  = base.a;
#if defined(_ALPHATEST_ON)
    if (s.alpha - _Cutoff < 0.0) discard;
#endif

#if defined(_MASKMAP)
    vec4 mask = texture(_MaskMap, uv);
    // （smooth 是 GLSL 的关键字（插值限定符），变量改名为 smoothness）
    s.metallic   = mask.r;                       // 有 Mask 时金属度完全由贴图决定（与 URP Lit 一致）
    float smoothness = mask.a * _Smoothness;         // 光滑度 = 贴图 × 滑条，滑条当总强度用
    s.occlusion  = LerpWhiteTo(mask.g, _OcclusionStrength);
#else
    s.metallic   = _Metallic;
    float smoothness = _Smoothness;
    s.occlusion  = 1.0;
#endif
    s.perceptualRoughness = 1.0 - smoothness;

#if defined(_NORMALMAP)
    s.normalTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
#else
    s.normalTS = vec3(0, 0, 1);
#endif

#if defined(_EMISSION)
    s.emission = texture(_EmissionMap, uv).rgb * _EmissionColor.rgb;
#else
    s.emission = vec3(0.0);
#endif
    return s;
}
#endif
//#endregion

#endif
