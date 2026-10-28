// URP 贴花（Decal Projector）的投影 Pass，GLSL 版。对应 URP 的 ShaderPassDecal.hlsl（DBufferProjector / DecalScreenSpaceProjector）。
// 用法：贴花 Shader 先定义
//     void DecalGraph(vec2 uv, out vec3 baseColor, out float alpha, out vec3 normalTS, out float normalAlpha)
// （= Shader Graph 里 Decal Master Stack 的 Base Color / Alpha / Normal (Tangent Space) / Normal Alpha），
// 再在 Pass 里 #include 本文件。需要角度衰减的图（Graph Settings 勾了 Angle Fade）先 #define DECAL_ANGLE_FADE。
//
// 网页版简化：DBuffer 和 Screen Space 两种技术都在不透明物体之后“画一个投影盒、按深度重建位置、直接混合出最终颜色”。
//   DBUFFER_PROJECTOR：表面法线取自 DepthNormals 预渲染（含表面自己的法线贴图），与 URP DBuffer 一样能和表面法线混合；
//   SCREEN_SPACE_PROJECTOR：表面法线由深度图重建（URP Screen Space 技术的 Normal Blend = Medium，5 次采样）。
// 两者都用贴花颜色 + 表面法线重新算一遍 PBR 光照（金属度 0，光滑度取 _DecalSmoothness），再按 Alpha 叠在场景上。

uniform vec4 _DecalParams;        // x: 不透明度（Fade Factor × 距离淡出）  y,z: 角度衰减系数  w: 1 = 开启角度衰减
uniform vec4 _DecalUVScaleBias;   // xy: UV 缩放  zw: UV 偏移
uniform float _DecalSmoothness;

#ifdef VERTEX
void main()
{
    // 物体矩阵就是投影盒：本地 [-0.5, 0.5]³，沿本地 +Z 投影
    gl_Position = TransformObjectToHClip(positionOS.xyz);
}
#endif

#ifdef FRAGMENT
vec3 DecalLoadPositionWS(ivec2 pix)
{
    pix = clamp(pix, ivec2(0), ivec2(_ScreenParams.xy) - 1);
    float depth = texelFetch(_CameraDepthTexture, pix, 0).r;
    return ComputeWorldSpacePosition((vec2(pix) + 0.5) / _ScreenParams.xy, depth, UNITY_MATRIX_I_VP);
}

// 由深度重建法线：左右、上下各取离中心更近的那一侧做差，减少物体轮廓处的错误法线
vec3 DecalReconstructNormal(ivec2 pix, vec3 c)
{
    vec3 l = DecalLoadPositionWS(pix - ivec2(1, 0)), r = DecalLoadPositionWS(pix + ivec2(1, 0));
    vec3 d = DecalLoadPositionWS(pix - ivec2(0, 1)), u = DecalLoadPositionWS(pix + ivec2(0, 1));
    vec3 h = dot(r - c, r - c) < dot(c - l, c - l) ? r - c : c - l;
    vec3 v = dot(u - c, u - c) < dot(c - d, c - d) ? u - c : c - d;
    vec3 n = normalize(cross(h, v));
    return n * sign(dot(n, GetWorldSpaceViewDir(c)));
}

void main()
{
    ivec2 pix = ivec2(gl_FragCoord.xy);
    vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
    float depth = texelFetch(_CameraDepthTexture, pix, 0).r;
    if (depth >= 1.0) discard;
    vec3 positionWS = ComputeWorldSpacePosition(screenUV, depth, UNITY_MATRIX_I_VP);

    // 世界坐标 → 贴花盒子空间；盒子外的像素丢掉
    vec3 positionDS = TransformWorldToObject(positionWS);
    if (any(greaterThan(abs(positionDS), vec3(0.5)))) discard;
    vec2 uv = (positionDS.xy + 0.5) * _DecalUVScaleBias.xy + _DecalUVScaleBias.zw;

    // 投影器的三个轴：T = 本地 X，B = 本地 Y，投影方向 = 本地 +Z（贴花的“正面法线”是 -Z）
    vec3 T = normalize(TransformObjectToWorldDir(vec3(1, 0, 0)));
    vec3 B = normalize(TransformObjectToWorldDir(vec3(0, 1, 0)));
    vec3 decalFacing = -normalize(TransformObjectToWorldDir(vec3(0, 0, 1)));

#ifdef DBUFFER_PROJECTOR
    vec3 surfaceN = texture(_CameraNormalsTexture, screenUV).xyz;
    // 没有 DepthNormals Pass 的物体在法线图里是 0：退回到由深度重建
    surfaceN = dot(surfaceN, surfaceN) > 0.25 ? normalize(surfaceN) : DecalReconstructNormal(pix, positionWS);
#else
    vec3 surfaceN = DecalReconstructNormal(pix, positionWS);
#endif

    vec3 baseColor, normalTS; float alpha, normalAlpha;
    DecalGraph(uv, baseColor, alpha, normalTS, normalAlpha);

    float fade = _DecalParams.x;
#ifdef DECAL_ANGLE_FADE
    // 角度衰减（URP DecalSystem 的公式：把 dot 化成 madd，再线性映射到 [起始角, 结束角]）
    if (_DecalParams.w > 0.5)
    {
        float dotAngle = dot(surfaceN, decalFacing);
        fade *= saturate(_DecalParams.y + _DecalParams.z * (dotAngle * (dotAngle - 2.0)));
    }
#endif
    alpha = saturate(alpha * fade);
    normalAlpha = saturate(normalAlpha * fade);
    if (alpha <= 0.0) discard;

    // 贴花法线（切线空间 = 投影器的 X/Y 轴）与表面法线按 Normal Alpha 混合
    vec3 decalN = T * normalTS.x + B * normalTS.y + decalFacing * normalTS.z;
    decalN = dot(decalN, decalN) > 1e-6 ? normalize(decalN) : surfaceN;
    vec3 n = normalize(mix(surfaceN, decalN, normalAlpha));

    InputData inputData = InitInputData();
    inputData.positionWS = positionWS;
    inputData.normalWS = n;
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
    inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
    inputData.bakedGI = SampleSH(n);
    inputData.normalizedScreenSpaceUV = screenUV;
    SurfaceData surface = InitSurfaceData();
    surface.albedo = baseColor;
    surface.metallic = 0.0;
    surface.smoothness = _DecalSmoothness;
    surface.occlusion = 1.0;
    surface.alpha = alpha;
    vec3 color = UniversalFragmentPBR(inputData, surface).rgb;
    fragColor = vec4(color, alpha);
}
#endif
