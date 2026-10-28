// Cookbook GLSL 核心库：对应 URP 的 Core.hlsl。
// 函数名、变量名尽量与 URP 保持一致，方便和书里的 HLSL 逐行对照。
// 每个 Shader 编译时都会自动带上本文件和 Lighting.glsl，不需要 #include。

// ---------------- 类型与常用函数（HLSL → GLSL 对照） ----------------
// float2/3/4 → vec2/3/4，half → float，lerp → mix，frac → fract，mul(M, v) → M * v，tex2D → texture
#define PI 3.14159265359
#define TWO_PI 6.28318530718
#define INV_PI 0.31830988618
#define HALF_MIN 6.103515625e-5
#define FLT_EPS 5.960464478e-8
#define FLT_MIN 1.175494351e-38
#define FLT_MAX 3.402823466e+38

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
vec4 saturate(vec4 x) { return clamp(x, 0.0, 1.0); }
float Pow4(float x) { return (x * x) * (x * x); }
float PositivePow(float b, float e) { return pow(max(abs(b), FLT_EPS), e); }
vec3 PositivePow(vec3 b, float e) { return pow(max(abs(b), vec3(FLT_EPS)), vec3(e)); }
vec3 SafeNormalize(vec3 v) { float d = max(FLT_MIN, dot(v, v)); return v * inversesqrt(d); }
float Luminance(vec3 c) { return dot(c, vec3(0.2126729, 0.7151522, 0.0721750)); }
float LerpWhiteTo(float b, float t) { return (1.0 - t) + b * t; }
vec3 LerpWhiteTo(vec3 b, float t) { return vec3(1.0 - t) + b * t; }
float Remap(float x, float a, float b, float c, float d) { return c + (x - a) * (d - c) / (b - a); }

vec3 SRGBToLinear(vec3 c) {
    vec3 lo = c / 12.92, hi = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(lo, hi, step(vec3(0.04045), c));
}
vec3 LinearToSRGB(vec3 c) {
    vec3 lo = c * 12.92, hi = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(vec3(0.0031308), c));
}

// ---------------- 引擎每帧/每物体设置的全局变量（与 URP 同名） ----------------
uniform mat4 unity_ObjectToWorld;
uniform mat4 unity_WorldToObject;
uniform mat4 unity_MatrixV;          // = UNITY_MATRIX_V
uniform mat4 unity_MatrixP;          // = UNITY_MATRIX_P
uniform mat4 unity_MatrixVP;         // = UNITY_MATRIX_VP
uniform mat4 unity_MatrixInvV;
uniform mat4 unity_MatrixInvP;
uniform mat4 unity_MatrixInvVP;
uniform mat4 unity_PrevMatrixVP;
#define UNITY_MATRIX_M unity_ObjectToWorld
#define UNITY_MATRIX_I_M unity_WorldToObject
#define UNITY_MATRIX_V unity_MatrixV
#define UNITY_MATRIX_P unity_MatrixP
#define UNITY_MATRIX_VP unity_MatrixVP
#define UNITY_MATRIX_I_V unity_MatrixInvV
#define UNITY_MATRIX_I_P unity_MatrixInvP
#define UNITY_MATRIX_I_VP unity_MatrixInvVP

uniform vec3 _WorldSpaceCameraPos;
uniform vec4 _Time;                  // (t/20, t, 2t, 3t)
uniform vec4 _SinTime;               // (sin t/8, sin t/4, sin t/2, sin t)
uniform vec4 _CosTime;
uniform vec4 unity_DeltaTime;        // (dt, 1/dt, smoothDt, 1/smoothDt)
uniform vec4 _ScreenParams;          // (宽, 高, 1+1/宽, 1+1/高)
uniform vec4 _ProjectionParams;      // (1, near, far, 1/far)  WebGL 不翻转 y，x 恒为 1
uniform vec4 _ZBufferParams;         // OpenGL 约定：(1-far/near, far/near, x/far, y/far)
uniform vec4 unity_OrthoParams;      // (宽/2, 高/2, 0, 正交?1:0)
uniform vec4 unity_WorldTransformParams; // w = 奇数次负缩放时为 -1
uniform vec4 _ScaledScreenParams;

// ---------------- 空间变换（ShaderVariablesFunctions.hlsl） ----------------
vec3 TransformObjectToWorld(vec3 p) { return (unity_ObjectToWorld * vec4(p, 1.0)).xyz; }
vec3 TransformWorldToObject(vec3 p) { return (unity_WorldToObject * vec4(p, 1.0)).xyz; }
vec3 TransformWorldToView(vec3 p) { return (unity_MatrixV * vec4(p, 1.0)).xyz; }
vec4 TransformWorldToHClip(vec3 p) { return unity_MatrixVP * vec4(p, 1.0); }
vec4 TransformObjectToHClip(vec3 p) { return unity_MatrixVP * (unity_ObjectToWorld * vec4(p, 1.0)); }
vec4 TransformWViewToHClip(vec3 p) { return unity_MatrixP * vec4(p, 1.0); }
vec3 TransformObjectToWorldDir(vec3 d) { return normalize(mat3(unity_ObjectToWorld) * d); }
vec3 TransformWorldToObjectDir(vec3 d) { return normalize(mat3(unity_WorldToObject) * d); }
vec3 TransformWorldToViewDir(vec3 d) { return normalize(mat3(unity_MatrixV) * d); }
// 法线用逆转置：n_world = n_object * M^-1（行向量写法），等价于 transpose(M^-1) * n
vec3 TransformObjectToWorldNormal(vec3 n) { return normalize(n * mat3(unity_WorldToObject)); }
vec3 TransformWorldToObjectNormal(vec3 n) { return normalize(n * mat3(unity_ObjectToWorld)); }
float GetOddNegativeScale() { return unity_WorldTransformParams.w >= 0.0 ? 1.0 : -1.0; }

bool IsPerspectiveProjection() { return unity_OrthoParams.w == 0.0; }
vec3 GetCameraPositionWS() { return _WorldSpaceCameraPos; }
vec3 GetViewForwardDir() { return -vec3(unity_MatrixV[0][2], unity_MatrixV[1][2], unity_MatrixV[2][2]); }
vec3 GetWorldSpaceViewDir(vec3 positionWS) {
    if (IsPerspectiveProjection()) return _WorldSpaceCameraPos - positionWS;
    return -GetViewForwardDir();
}
vec3 GetWorldSpaceNormalizeViewDir(vec3 positionWS) { return normalize(GetWorldSpaceViewDir(positionWS)); }

// VertexPositionInputs / VertexNormalInputs（URP 的 GetVertexPositionInputs）
struct VertexPositionInputs { vec3 positionWS; vec3 positionVS; vec4 positionCS; vec4 positionNDC; };
struct VertexNormalInputs { vec3 tangentWS; vec3 bitangentWS; vec3 normalWS; };
VertexPositionInputs GetVertexPositionInputs(vec3 positionOS) {
    VertexPositionInputs o;
    o.positionWS = TransformObjectToWorld(positionOS);
    o.positionVS = TransformWorldToView(o.positionWS);
    o.positionCS = TransformWorldToHClip(o.positionWS);
    vec4 ndc = o.positionCS * 0.5;
    o.positionNDC = vec4(ndc.x + ndc.w, ndc.y * _ProjectionParams.x + ndc.w, o.positionCS.zw);
    return o;
}
VertexNormalInputs GetVertexNormalInputs(vec3 normalOS) {
    VertexNormalInputs o;
    o.tangentWS = vec3(1, 0, 0); o.bitangentWS = vec3(0, 1, 0);
    o.normalWS = TransformObjectToWorldNormal(normalOS);
    return o;
}
VertexNormalInputs GetVertexNormalInputs(vec3 normalOS, vec4 tangentOS) {
    VertexNormalInputs o;
    float sign = tangentOS.w * GetOddNegativeScale();
    o.normalWS = TransformObjectToWorldNormal(normalOS);
    o.tangentWS = TransformObjectToWorldDir(tangentOS.xyz);
    o.bitangentWS = cross(o.normalWS, o.tangentWS) * sign;
    return o;
}

// 屏幕坐标：ComputeScreenPos 的结果在片元里 .xy/.w 得到 0~1 的屏幕 UV
vec4 ComputeScreenPos(vec4 positionCS) {
    vec4 o = positionCS * 0.5;
    o.xy = vec2(o.x, o.y * _ProjectionParams.x) + o.w;
    o.zw = positionCS.zw;
    return o;
}
// 片元里直接用 gl_FragCoord 求屏幕 UV（等价于 URP 的 GetNormalizedScreenSpaceUV(input.positionCS)）
vec2 GetNormalizedScreenSpaceUV(vec4 fragCoord) { return fragCoord.xy / _ScaledScreenParams.xy; }

// ---------------- 深度 ----------------
#define UNITY_REVERSED_Z 0
#define UNITY_NEAR_CLIP_VALUE (-1.0)
#define UNITY_RAW_FAR_CLIP_VALUE (1.0)
// WebGL（OpenGL）的深度缓冲：近 0 远 1，不反转。
float Linear01Depth(float d, vec4 zb) { return 1.0 / (zb.x * d + zb.y); }
float LinearEyeDepth(float d, vec4 zb) { return 1.0 / (zb.z * d + zb.w); }
// 由屏幕 UV + 深度重建世界坐标（GL 的 NDC z 在 -1~1）
vec3 ComputeWorldSpacePosition(vec2 uv, float deviceDepth, mat4 invVP) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, deviceDepth * 2.0 - 1.0, 1.0);
    vec4 p = invVP * ndc;
    return p.xyz / p.w;
}

// ---------------- 贴图 ----------------
// HLSL 的 TRANSFORM_TEX(uv, _MainTex) 用了宏拼接（##），GLSL ES 不支持，写成 TransformTex(uv, _MainTex_ST)
vec2 TransformTex(vec2 uv, vec4 st) { return uv * st.xy + st.zw; }

// 与 Unity 桌面平台一致：UnpackNormalmapRGorAG。普通 RGB 法线图（A=1）和 DXT5nm 布局（R=1，A=x）都能正确解码，z 由 xy 重建
vec3 UnpackNormalAG(vec4 packed, float scale) {
    vec3 n;
    n.xy = packed.ag * 2.0 - 1.0;
    n.z = max(1.0e-16, sqrt(1.0 - saturate(dot(n.xy, n.xy))));
    n.xy *= scale;
    return n;
}
vec3 UnpackNormalmapRGorAG(vec4 packed, float scale) { packed.a *= packed.r; return UnpackNormalAG(packed, scale); }
vec3 UnpackNormalScale(vec4 packed, float scale) { return UnpackNormalmapRGorAG(packed, scale); }
vec3 UnpackNormal(vec4 packed) { return UnpackNormalmapRGorAG(packed, 1.0); }
vec3 UnpackNormalRGB(vec4 packed, float scale) { vec3 n = packed.rgb * 2.0 - 1.0; n.xy *= scale; return normalize(n); }

mat3 CreateTangentToWorld(vec3 normal, vec3 tangent, float flipSign) {
    vec3 bitangent = cross(normal, tangent) * flipSign;
    return mat3(tangent, bitangent, normal);
}
// URP 的 TransformTangentToWorld(n, half3x3(T, B, N))：GLSL 里 mat3(T, B, N) 的列就是 T/B/N
vec3 TransformTangentToWorld(vec3 v, mat3 tbnColumns) { return tbnColumns * v; }
vec3 TransformWorldToTangent(vec3 v, mat3 tbnColumns) { return v * tbnColumns; }
vec3 NormalizeNormalPerPixel(vec3 n) { return normalize(n); }

// ---------------- 相机贴图（需要 URP Asset 打开 Depth/Opaque Texture） ----------------
uniform highp sampler2D _CameraDepthTexture;
uniform sampler2D _CameraOpaqueTexture;
uniform sampler2D _CameraNormalsTexture;
float SampleSceneDepth(vec2 uv) { return texture(_CameraDepthTexture, uv).r; }
vec3 SampleSceneColor(vec2 uv) { return texture(_CameraOpaqueTexture, uv).rgb; }
// 与 URP 14 DeclareNormalsTexture.hlsl 一致：点采样、不归一化
vec3 SampleSceneNormals(vec2 uv) { ivec2 sz = textureSize(_CameraNormalsTexture, 0); return texelFetch(_CameraNormalsTexture, clamp(ivec2(uv * vec2(sz)), ivec2(0), sz - 1), 0).xyz; }

// ---------------- 雾（URP ShaderVariablesFunctions） ----------------
uniform vec4 unity_FogParams;   // (density/sqrt(ln2), density/ln2, -1/(end-start), end/(end-start))
uniform vec4 unity_FogColor;
uniform vec4 unity_FogMode;     // x: 0 关 1 线性 2 指数 3 指数平方
float ComputeFogFactor(float zPositionCS) {
    // GL 的裁剪空间 z 在 -near~far 之间，先映射到 0~far（Unity 的 UNITY_Z_0_FAR_FROM_CLIPSPACE）
    float clipZ01 = max((zPositionCS + _ProjectionParams.y) * (_ProjectionParams.z / (_ProjectionParams.z + _ProjectionParams.y)), 0.0);
    if (unity_FogMode.x == 1.0) return saturate(clipZ01 * unity_FogParams.z + unity_FogParams.w);
    if (unity_FogMode.x == 2.0) return clipZ01 * unity_FogParams.y;
    if (unity_FogMode.x == 3.0) return clipZ01 * unity_FogParams.x;
    return 0.0;
}
float ComputeFogIntensity(float fogFactor) {
    if (unity_FogMode.x == 1.0) return fogFactor;
    if (unity_FogMode.x == 2.0) return saturate(exp2(-fogFactor));
    if (unity_FogMode.x == 3.0) return saturate(exp2(-fogFactor * fogFactor));
    return 1.0;
}
vec3 MixFogColor(vec3 c, vec3 fogColor, float fogFactor) {
    if (unity_FogMode.x == 0.0) return c;
    return mix(fogColor, c, ComputeFogIntensity(fogFactor));
}
vec3 MixFog(vec3 c, float fogFactor) { return MixFogColor(c, unity_FogColor.rgb, fogFactor); }

// ---------------- 全屏 Blit（Blit.hlsl 的 Vert / _BlitTexture） ----------------
uniform sampler2D _BlitTexture;
uniform vec4 _BlitTexture_TexelSize;   // (1/宽, 1/高, 宽, 高)
uniform vec4 _BlitScaleBias;
uniform float _BlitMipLevel;
