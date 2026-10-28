// 网页版对 URP Rendering Debugger（Window › Analysis › Rendering Debugger）“材质”页的模拟。
// HLSL 版里这部分由 URP 的 Debugging3D.hlsl 提供（CanDebugOverrideOutputColor），网页版没有，在这里写一个精简版：
//   材质视图（Material Debug Mode）：Albedo / Specular / Alpha / Smoothness / AO / Emission / 世界法线 / Metallic
//   材质校验（Material Validation）：Albedo 亮度过暗标红、过亮标蓝；Metallic 超出范围标红/蓝
// 由 web/features/UnityEngine.Rendering.Universal.UniversalRenderPipelineDebugDisplaySettings.js 打开 DEBUG_DISPLAY 并设置下面的全局变量。
#ifndef COOKBOOK_DEBUG_DISPLAY_INCLUDED
#define COOKBOOK_DEBUG_DISPLAY_INCLUDED

uniform float _DebugMaterialMode;             // URP 的 DebugMaterialMode 枚举值
uniform float _DebugMaterialValidationMode;   // 0 None  1 Albedo  2 Metallic
uniform vec4  _DebugValidateAlbedoParams;     // x 最暗亮度  y 最亮亮度（线性）
uniform vec4  _DebugValidateMetallicParams;   // x 最小金属度  y 最大金属度
#define DEBUG_BELOW_MIN_COLOR vec4(1.0, 0.0, 0.0, 1.0)   // 低于下限：红
#define DEBUG_ABOVE_MAX_COLOR vec4(0.0, 0.0, 1.0, 1.0)   // 高于上限：蓝

// 返回 true 表示调试器接管了这个像素的颜色
bool CanDebugOverrideOutputColor(vec3 albedo, float alpha, vec3 specular, float metallic, float smoothness,
                                 float occlusion, vec3 emission, vec3 normalWS, out vec4 debugColor)
{
    debugColor = vec4(0.0);
    int mode = int(_DebugMaterialMode + 0.5);
    if (mode == 1)  { debugColor = vec4(albedo, 1.0); return true; }                    // Albedo
    if (mode == 2)  { debugColor = vec4(specular, 1.0); return true; }                  // Specular
    if (mode == 3)  { debugColor = vec4(vec3(alpha), 1.0); return true; }               // Alpha
    if (mode == 4)  { debugColor = vec4(vec3(smoothness), 1.0); return true; }          // Smoothness
    if (mode == 5)  { debugColor = vec4(vec3(occlusion), 1.0); return true; }           // Ambient Occlusion
    if (mode == 6)  { debugColor = vec4(emission, 1.0); return true; }                  // Emission
    if (mode == 7)  { debugColor = vec4(normalWS * 0.5 + 0.5, 1.0); return true; }      // Normal World Space
    if (mode == 10) { debugColor = vec4(vec3(metallic), 1.0); return true; }            // Metallic

    int validation = int(_DebugMaterialValidationMode + 0.5);
    if (validation == 1)   // Albedo：亮度（线性）不在 [min, max] 里就标色，否则显示亮度
    {
        float luminance = Luminance(albedo);
        if (luminance < _DebugValidateAlbedoParams.x) debugColor = DEBUG_BELOW_MIN_COLOR;
        else if (luminance > _DebugValidateAlbedoParams.y) debugColor = DEBUG_ABOVE_MAX_COLOR;
        else debugColor = vec4(vec3(luminance), 1.0);
        return true;
    }
    if (validation == 2)   // Metallic
    {
        if (metallic < _DebugValidateMetallicParams.x) debugColor = DEBUG_BELOW_MIN_COLOR;
        else if (metallic > _DebugValidateMetallicParams.y) debugColor = DEBUG_ABOVE_MAX_COLOR;
        else debugColor = vec4(vec3(Luminance(albedo)), 1.0);
        return true;
    }
    return false;
}

#endif
