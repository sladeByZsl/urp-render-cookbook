// DepthOnly Pass：只写深度。URP 做深度预渲染（Depth Prepass）、生成 _CameraDepthTexture 时会用到它。（GLSL 版，对应 Ch06/DepthOnlyPass.hlsl）

#if defined(_ALPHATEST_ON)
VARYING vec2 uv;
#endif

#ifdef VERTEX
void main()
{
    gl_Position = TransformObjectToHClip(positionOS.xyz);
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
    // 深度由硬件写入；某些路径会把深度作为颜色写进 R 通道（Pass 里 ColorMask R），所以照 URP 的做法返回 z
    fragColor = vec4(gl_FragCoord.z);
}
#endif
