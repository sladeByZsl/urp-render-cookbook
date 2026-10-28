# 网页版：WebGL2“迷你 URP” + GLSL 移植

在线站点 https://gametech.byte888.com/urp/ 里的实时预览就是这套代码：按 URP 14 Forward 渲染器的顺序画一帧（主光源级联阴影 → 附加光源阴影 → 不透明 → 拷贝深度 → 天空盒 → 拷贝颜色 → 半透明 → 后处理），Renderer Feature 按 RenderPassEvent 插入。

| 目录 | 内容 |
|---|---|
| `engine/` | 渲染器（`pipeline.js`）、ShaderLab 外壳解析（`shaderlab.js`）、材质与变体（`shader.js`）、后处理与 Volume（`post.js`）、实时预览组件（`viewer.js`）；`glsl/Core.glsl`、`glsl/Lighting.glsl` 是与 URP 同名同算法的 GLSL 函数库 |
| `shaders/` | 全书 Shader 的 GLSL 版，路径与 `unity/Assets/Cookbook/` 一一对应（`ChNN/Xxx.shader` → `ChNN/Xxx.glsl`）；`URP/` 是 Lit / Unlit / SimpleLit / 后处理等 URP 自带 Shader 的移植 |
| `features/` | Renderer Feature 的 JS 版（文件名为 C# 类型全名） |
| `behaviours/` | 运行时脚本（平面反射、草地、粒子系统等）的 JS 版 |

GLSL 文件保留 ShaderLab 的结构，只是 `HLSLPROGRAM` 换成 `GLSLPROGRAM`：

```glsl
Shader "Cookbook/Ch05/Lambert"
{
    SubShader
    {
        Tags { "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            VARYING vec3 normalWS;
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); normalWS = TransformObjectToWorldNormal(normalOS); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(saturate(dot(normalize(normalWS), GetMainLight().direction)) * _MainLightColor.rgb, 1.0); }
            #endif
            ENDGLSL
        }
    }
}
```

场景数据（由 Unity 工程导出的网格、材质参数、灯光、相机，约 170 MB）没有放进仓库，在线站点上可以直接体验。
