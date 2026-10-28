// 标准的切线空间法线贴图：顶点里准备 TBN，片元里解码法线贴图并变换到世界空间。（GLSL 版，对应 Ch07/NormalMap.shader）
Shader "Cookbook/Ch07/NormalMap"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _BumpScale;
        uniform float _Gloss;
        uniform float _SpecStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #include "Ch07/Ch07Common.glsl"

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
        #if defined(_NORMALMAP)
            VARYING vec4 tangentWS;   // xyz 切线，w 副切线符号
        #endif
            VARYING float fogFactor;

            //#region vert
            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = nrm.normalWS;
            #if defined(_NORMALMAP)
                // 与 URP Lit 相同：只传 T 和符号，B 在片元里用叉乘重建，省一个插值器
                float sign = tangentOS.w * GetOddNegativeScale();
                tangentWS = vec4(nrm.tangentWS, sign);
            #endif
                fogFactor = ComputeFogFactor(pos.positionCS.z);
            }
            #endif
            //#endregion

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                vec4 albedo = texture(_BaseMap, uv) * _BaseColor;

            #if defined(_NORMALMAP)
                // 1) 解码：Unity 的 UnpackNormalScale 自动处理 DXT5nm/BC5（AG/RG 两通道）与 RGB 三通道；网页版的法线贴图是 RGB
                vec3 normalTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
                // 2) 重建副切线并组装 TBN。HLSL 的 half3x3(T, B, N) 是按行放，GLSL 的 mat3(T, B, N) 按列放，
                //    TransformTangentToWorld 已按各自的约定写好：结果都是 x*T + y*B + z*N
                float sgn = tangentWS.w;
                vec3 bitangent = sgn * cross(normalWS, tangentWS.xyz);
                mat3 tangentToWorld = mat3(tangentWS.xyz, bitangent, normalWS);
                // 3) 切线空间 → 世界空间
                vec3 nWS = TransformTangentToWorld(normalTS, tangentToWorld);
            #else
                vec3 nWS = normalWS;
            #endif
                nWS = NormalizeNormalPerPixel(nWS);

                vec3 color = Ch07Shade(positionWS, nWS, albedo.rgb, _Gloss, _SpecStrength, 1.0);
                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            #endif
            //#endregion
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define CH07_SHADOW_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH07_DEPTH_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
    }
}
