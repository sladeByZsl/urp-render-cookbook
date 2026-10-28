// 网页版模拟 Rendering Debugger 时，给 URP Lit 材质用的替换着色器（Unity 里这部分在 Lit.shader 的 DEBUG_DISPLAY 分支）。
// 读取 Lit 的同名材质属性（InitializeStandardLitSurfaceData），把表面参数交给 Ch11/DebugDisplay.glsl 的 CanDebugOverrideOutputColor。
// 自己写的着色器（如 MyPBR）有 DEBUG_DISPLAY 分支，就不需要它。
Shader "Hidden/Cookbook/Ch11/LitDebugReplacement"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        Pass
        {
            Name "DebugMaterial"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #include "URP/LitInput.glsl"
            #include "Ch11/DebugDisplay.glsl"

            VARYING vec2 uv;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;

            #ifdef VERTEX
            void main()
            {
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                SurfaceData s = InitializeStandardLitSurfaceData(uv);
            #ifdef _NORMALMAP
                vec3 b = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 n = normalize(mat3(tangentWS.xyz, b, normalWS) * s.normalTS);
            #else
                vec3 n = normalize(normalWS);
            #endif
                vec3 specular = mix(kDielectricSpec.rgb, s.albedo, s.metallic);
            #ifdef _SPECULAR_SETUP
                specular = s.specular;
            #endif
                vec4 debugColor;
                if (!CanDebugOverrideOutputColor(s.albedo, s.alpha, specular, s.metallic, s.smoothness, s.occlusion, s.emission, n, debugColor))
                    debugColor = vec4(s.albedo, 1.0);
                fragColor = debugColor;
            }
            #endif
            ENDGLSL
        }
    }
}
