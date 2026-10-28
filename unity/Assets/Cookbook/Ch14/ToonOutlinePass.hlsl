// 描边 Pass 的通用实现（ToonLit / ToonHair / ToonFace 共用）。
// 使用方需要在 UnityPerMaterial 里声明 _OutlineColor、_OutlineWidth，
// 并用 shader_feature_local_vertex 声明 _OUTLINENORMAL_MESH/_TANGENT/_VERTEXCOLOR 之一（不声明时用原始法线）。
#ifndef COOKBOOK_CH14_TOON_OUTLINE_PASS_INCLUDED
#define COOKBOOK_CH14_TOON_OUTLINE_PASS_INCLUDED

#include "Assets/Cookbook/Ch14/ToonCommon.hlsl"

struct OutlineVaryings
{
    float4 positionCS : SV_POSITION;
    float  fogFactor  : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

OutlineVaryings OutlineVert(ToonAttributes v)
{
    OutlineVaryings o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    float3 n = v.normalOS;
#if defined(_OUTLINENORMAL_TANGENT)
    n = v.tangentOS.xyz;                                   // 物体空间平滑法线
#elif defined(_OUTLINENORMAL_VERTEXCOLOR)
    float3 nTS = v.color.rgb * 2.0 - 1.0;                  // 切线空间平滑法线
    float3 bOS = cross(v.normalOS, v.tangentOS.xyz) * v.tangentOS.w;
    n = normalize(nTS.x * v.tangentOS.xyz + nTS.y * bOS + nTS.z * v.normalOS);
#endif
    o.positionCS = OutlinePositionCS(v.positionOS.xyz, n, _OutlineWidth);
    o.fogFactor = ComputeFogFactor(o.positionCS.z);
    return o;
}

half4 OutlineFrag(OutlineVaryings i) : SV_Target
{
    clip(_OutlineWidth - 0.01);   // 线宽为 0 时不输出（方便在同一个材质上关掉描边）
    return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1);
}

#endif
