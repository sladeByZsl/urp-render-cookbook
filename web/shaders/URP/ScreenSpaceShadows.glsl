// URP 的屏幕空间阴影解析 Pass（Shaders/Utils/ScreenSpaceShadows.shader）的 GLSL 版：
// 读深度图重建世界坐标 → 照常求级联阴影坐标并采样阴影图 → 写进 _ScreenSpaceShadowmapTexture。
Shader "Hidden/Universal Render Pipeline/ScreenSpaceShadows"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "ScreenSpaceShadows"
            ZTest Always ZWrite Off Cull Off
            GLSLPROGRAM
            VARYING vec2 texcoord;
            #ifdef VERTEX
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                // 用点采样读深度（URP 用 sampler_PointClamp）
                float deviceDepth = texelFetch(_CameraDepthTexture, ivec2(texcoord * _ScreenParams.xy), 0).r;
                vec3 wpos = ComputeWorldSpacePosition(texcoord, deviceDepth, unity_MatrixInvVP);
                // 取级联阴影坐标（这个 Pass 执行时 _MainLightShadowsScreen 被临时设为 0，走普通阴影图路径）
                vec4 coords = TransformWorldToShadowCoord(wpos);
                // 屏幕空间阴影只用于方向光（正交投影）
                float realtimeShadow = MainLightRealtimeShadow(coords);
                fragColor = vec4(realtimeShadow);
            }
            #endif
            ENDGLSL
        }
    }
}
