// 两张切线空间法线的混合方法。n1 = 基础法线，n2 = 细节法线，都已解码（z 朝外）。
#ifndef COOKBOOK_CH07_NORMAL_BLEND_INCLUDED
#define COOKBOOK_CH07_NORMAL_BLEND_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"   // BlendNormalRNM

//#region blend
// ① 线性平均：把两个方向直接相加再归一化。最直觉、也最不对——两张图会互相“抹平”。
half3 BlendNormalLinear(half3 n1, half3 n2)
{
    return normalize(n1 + n2);
}

// ② UDN（Unreal Developer Network 流传的写法）：只叠加 xy，z 用基础法线的。
//    便宜，但细节在陡坡上会被压扁。
half3 BlendNormalUDN(half3 n1, half3 n2)
{
    return normalize(half3(n1.xy + n2.xy, n1.z));
}

// ③ Whiteout：xy 相加，z 相乘。相当于把两个“斜率”相加，平地和斜坡上的细节都比较可信。
half3 BlendNormalWhiteout(half3 n1, half3 n2)
{
    return normalize(half3(n1.xy + n2.xy, n1.z * n2.z));
}

// ④ RNM（Reoriented Normal Mapping）：把细节法线当成“相对 +Z 的旋转”，
//    再把这个旋转施加到基础法线上。URP 的 Lit 细节法线用的就是它：
//    BlendNormalRNM(n1, n2)，定义在 core 的 CommonMaterial.hlsl，要求两个输入都已归一化。
half3 BlendNormalReoriented(half3 n1, half3 n2)
{
    return normalize(BlendNormalRNM(normalize(n1), normalize(n2)));
}
//#endregion

#endif
