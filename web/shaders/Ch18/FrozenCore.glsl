// 冰冻覆盖的公共部分：材质参数、三平面噪声、覆盖遮罩、顶点加厚。Forward/Shadow/Depth 三个 Pass 共用。
// （GLSL 版，对应 FrozenCore.hlsl）
#ifndef COOKBOOK_CH18_FROZEN_CORE_INCLUDED
#define COOKBOOK_CH18_FROZEN_CORE_INCLUDED

uniform sampler2D _BaseMap;
uniform sampler2D _IceNoise;
uniform sampler2D _CrackMap;

uniform vec4  _BaseMap_ST;
uniform vec4  _BaseColor;
uniform float _Smoothness;
uniform float _Freeze;
uniform vec4  _IceColor;
uniform vec4  _IceDeepColor;
uniform float _IceNoiseScale;
uniform float _CrackScale;
uniform float _CrackStrength;
uniform float _Thickness;
uniform vec4  _IceRimColor;
uniform float _SparkleStrength;

//#region triplanar
// 极简三平面采样：按法线三个分量的权重，混合 YZ / XZ / XY 三个方向的投影
// （GLSL 没有 TEXTURE2D_PARAM，直接传 sampler2D）
float TriplanarNoise(sampler2D tex, vec3 positionWS, vec3 normalWS, float scale)
{
    vec3 w = pow(abs(normalWS), vec3(4.0));
    w /= (w.x + w.y + w.z);
    float x = textureLod(tex, positionWS.zy * scale, 0.0).r;
    float y = textureLod(tex, positionWS.xz * scale, 0.0).r;
    float z = textureLod(tex, positionWS.xy * scale, 0.0).r;
    return x * w.x + y * w.y + z * w.z;
}
//#endregion

//#region mask
// 覆盖遮罩：法线越朝上越先结冰，噪声把分界线打散。_Freeze 0→1，阈值从“只有正上方”一路降到“全覆盖”
float FrostMask(vec3 positionWS, vec3 normalWS)
{
    float n = TriplanarNoise(_IceNoise, positionWS, normalWS, _IceNoiseScale);
    float up = normalWS.y + (n - 0.5) * 0.8;          // -1.4 ~ 1.4
    float threshold = mix(1.5, -1.5, _Freeze);
    return smoothstep(threshold - 0.1, threshold + 0.1, up);
}
//#endregion

//#region thicken
// 冰层有厚度：被覆盖的顶点沿法线外推。阴影和深度 Pass 也要做同样的外推，否则阴影对不上
vec3 ThickenIce(vec3 positionWS, vec3 normalWS)
{
    return positionWS + normalWS * FrostMask(positionWS, normalWS) * _Thickness;
}
//#endregion

#endif
