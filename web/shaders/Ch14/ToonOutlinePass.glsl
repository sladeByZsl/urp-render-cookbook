// 描边 Pass 的通用实现（ToonLit / ToonHair / ToonFace 共用）。（GLSL 版，对应 Ch14/ToonOutlinePass.hlsl）
// 使用方需要声明 uniform _OutlineColor、_OutlineWidth，
// 并用 shader_feature_local_vertex 声明 _OUTLINENORMAL_MESH/_TANGENT/_VERTEXCOLOR 之一（不声明时用原始法线）。
#ifndef COOKBOOK_CH14_TOON_OUTLINE_PASS_INCLUDED
#define COOKBOOK_CH14_TOON_OUTLINE_PASS_INCLUDED

#include "Ch14/ToonCommon.glsl"

VARYING float fogFactor;

#ifdef VERTEX
void OutlineVert()
{
    vec3 n = normalOS;
#if defined(_OUTLINENORMAL_TANGENT)
    n = tangentOS.xyz;                                   // 物体空间平滑法线
#elif defined(_OUTLINENORMAL_VERTEXCOLOR)
    vec3 nTS = color.rgb * 2.0 - 1.0;                    // 切线空间平滑法线
    vec3 bOS = cross(normalOS, tangentOS.xyz) * tangentOS.w;
    n = normalize(nTS.x * tangentOS.xyz + nTS.y * bOS + nTS.z * normalOS);
#endif
    gl_Position = OutlinePositionCS(positionOS.xyz, n, _OutlineWidth);
    fogFactor = ComputeFogFactor(gl_Position.z);
}
void main() { OutlineVert(); }
#endif

#ifdef FRAGMENT
vec4 OutlineFrag()
{
    if (_OutlineWidth - 0.01 < 0.0) discard;   // 线宽为 0 时不输出（方便在同一个材质上关掉描边）
    return vec4(MixFog(_OutlineColor.rgb, fogFactor), 1.0);
}
void main() { fragColor = OutlineFrag(); }
#endif

#endif
