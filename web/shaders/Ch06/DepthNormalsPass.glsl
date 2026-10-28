// DepthNormals Pass：同时写深度和世界空间法线到 _CameraNormalsTexture。（GLSL 版，对应 Ch06/DepthNormalsPass.hlsl）
// SSAO（Depth Normals 模式）、贴花、部分自定义屏幕空间效果都依赖它。

VARYING vec2 uv;
VARYING vec3 normalWS;

#ifdef VERTEX
void main()
{
    gl_Position = TransformObjectToHClip(positionOS.xyz);
    normalWS = TransformObjectToWorldNormal(normalOS);
    uv = texcoord0.xy;
#if defined(_ALPHATEST_ON)
    uv = TransformTex(texcoord0.xy, _BaseMap_ST);
#endif
}
#endif

#ifdef FRAGMENT
void main()
{
#if defined(_ALPHATEST_ON)
    if (texture(_BaseMap, uv).a * _BaseColor.a - _Cutoff < 0.0) discard;
#endif
    // URP 14 的 _CameraNormalsTexture 直接存归一化的世界空间法线（不做 0.5 偏移）
    // （网页版不支持“渲染层”贴图，_WRITE_RENDERING_LAYERS 那一路省略）
    fragColor = vec4(NormalizeNormalPerPixel(normalWS), 0.0);
}
#endif
