// 案例 6.9 ClassicLit 的材质输入：所有 Pass 共享同一组材质参数（GLSL 版，对应 Ch06/ClassicLitInput.hlsl）
// HLSL 版把它们放进 CBUFFER_START(UnityPerMaterial) 以兼容 SRP Batcher；GLSL 里就是普通 uniform。

uniform vec4  _BaseMap_ST;
uniform vec4  _BaseColor;
uniform vec4  _SpecColor;
uniform float _Smoothness;
uniform vec4  _EmissionColor;
uniform float _Cutoff;

uniform sampler2D _BaseMap;
