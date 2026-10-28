// 第一步：只有主光、没有阴影、没有环境光的最小 PBR。（GLSL 版，对应 Ch11/Step1_DirectPBR.shader）
// 目的：先单独验证 BRDF（D、V、F、Lambert 与 π 的约定）是否正确，再往上加东西。
Shader "Cookbook/Ch11/Step1_DirectPBR"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform vec4  _BaseColor;
            uniform float _Metallic;
            uniform float _Smoothness;
            // MyPBR_BRDF.glsl 里的 LUT 分支要用到这张贴图的声明（本步不启用）
            uniform sampler2D _DFGLut;
            #include "Ch11/MyPBR_BRDF.glsl"

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                positionWS  = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS    = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light light = GetMainLight();

                MyMaterial m = MyInitMaterial(_BaseColor.rgb, _Metallic, 1.0 - _Smoothness);
                vec3 fd, fs; float NoL;
                MyDirectBRDF(m, N, V, light.direction, fd, fs, NoL);

                // 渲染方程只剩一项：Lo = f(l,v) · E⊥ · NoL，E⊥ = π · light.color
                vec3 Lo = (fd + fs) * PI * light.color * NoL;
                fragColor = vec4(Lo, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
