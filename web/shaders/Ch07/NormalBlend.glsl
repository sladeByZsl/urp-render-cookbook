// 两张切线空间法线的混合方法。n1 = 基础法线，n2 = 细节法线，都已解码（z 朝外）。（GLSL 版，对应 Ch07/NormalBlend.hlsl）

// core 的 CommonMaterial.hlsl 里的 BlendNormalRNM（GLSL 版没有这个库，照抄过来）
vec3 BlendNormalRNM(vec3 n1, vec3 n2)
{
    vec3 t = n1.xyz + vec3(0.0, 0.0, 1.0);
    vec3 u = n2.xyz * vec3(-1.0, -1.0, 1.0);
    vec3 r = (t / t.z) * dot(t, u) - u;
    return r;
}

//#region blend
// ① 线性平均：把两个方向直接相加再归一化。最直觉、也最不对——两张图会互相“抹平”。
vec3 BlendNormalLinear(vec3 n1, vec3 n2)
{
    return normalize(n1 + n2);
}

// ② UDN（Unreal Developer Network 流传的写法）：只叠加 xy，z 用基础法线的。
//    便宜，但细节在陡坡上会被压扁。
vec3 BlendNormalUDN(vec3 n1, vec3 n2)
{
    return normalize(vec3(n1.xy + n2.xy, n1.z));
}

// ③ Whiteout：xy 相加，z 相乘。相当于把两个“斜率”相加，平地和斜坡上的细节都比较可信。
vec3 BlendNormalWhiteout(vec3 n1, vec3 n2)
{
    return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
}

// ④ RNM（Reoriented Normal Mapping）：把细节法线当成“相对 +Z 的旋转”，
//    再把这个旋转施加到基础法线上。URP 的 Lit 细节法线用的就是它：
//    BlendNormalRNM(n1, n2)，要求两个输入都已归一化。
vec3 BlendNormalReoriented(vec3 n1, vec3 n2)
{
    return normalize(BlendNormalRNM(normalize(n1), normalize(n2)));
}
//#endregion
