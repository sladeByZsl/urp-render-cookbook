// MyPBR 的 Meta Pass：只在烘焙光照贴图时使用。（GLSL 版，对应 Ch11/MyPBR_MetaPass.hlsl）
// 烘焙器把物体按 lightmap UV 摊平渲染，读两样东西：反照率（决定反弹光颜色）和自发光（作为光源参与烘焙）
// 网页版没有光照烘焙，这个 Pass 不会被调用，移植出来只为和 HLSL 对照。
#ifndef COOKBOOK_MYPBR_META_PASS_INCLUDED
#define COOKBOOK_MYPBR_META_PASS_INCLUDED

#include "Ch11/MyPBR_BRDF.glsl"

// URP MetaInput.hlsl 里的烘焙控制变量
uniform vec4 unity_LightmapST;
uniform vec4 unity_DynamicLightmapST;
uniform vec4 unity_MetaVertexControl;     // x = 用静态光照贴图 UV，y = 用动态光照贴图 UV
uniform vec4 unity_MetaFragmentControl;   // x = 输出反照率，y = 输出自发光

VARYING vec2 uv;

//#region meta
#ifdef VERTEX
// UnityMetaVertexPosition：用光照贴图 UV 当“屏幕位置”，把网格摊平到贴图空间
void MyMetaVert()
{
    vec2 p = unity_MetaVertexControl.y > 0.5 ? texcoord2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw
                                            : texcoord1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);
}
#endif

#ifdef FRAGMENT
vec4 MyMetaFrag()
{
    MySurface s = MySampleSurface(uv);
    MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);

    // 反弹光的颜色：漫反射色为主；粗糙金属的镜面反射在烘焙器看来也像“漫反射”，
    // 按粗糙度加一部分 F0 进去（与 URP Lit 的经验做法相同）
    vec3 albedo = m.diffuseColor + m.f0 * (m.perceptualRoughness * m.perceptualRoughness) * 0.5;
    vec3 emission = s.emission;
    // UnityMetaFragment：按烘焙器的请求输出反照率或自发光
    if (unity_MetaFragmentControl.x > 0.5) return vec4(saturate(albedo), 1.0);
    if (unity_MetaFragmentControl.y > 0.5) return vec4(emission, 1.0);
    return vec4(0.0);
}
#endif
//#endregion

#endif
