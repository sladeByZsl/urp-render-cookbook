// 网格没有切线数据时，用屏幕导数在像素里现算切线框架（per-pixel tangent frame）。（GLSL 版，对应 Ch07/DerivativeTBN.shader）
Shader "Cookbook/Ch07/DerivativeTBN"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _BumpScale;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #pragma shader_feature_local _DERIVATIVE_TBN
            #include "Ch07/Ch07Common.glsl"

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
            }
            #endif

            #ifdef FRAGMENT
            //#region frame
            // 由 dp = T·du + B·dv 在屏幕 x、y 两个方向各写一次，解出 T = ∂p/∂u、B = ∂p/∂v。
            // 乘 sign(det) 保证结果与屏幕 y 轴朝向（平台差异）无关，并自动处理镜像 UV。
            // （WebGL 的 dFdy 朝上、D3D 的 ddy 朝下，正好靠这个 sign 抵消）
            mat3 DerivativeTangentFrame(vec3 N, vec3 positionWS, vec2 uv)
            {
                vec3 dp1 = dFdx(positionWS), dp2 = dFdy(positionWS);
                vec2 duv1 = dFdx(uv),        duv2 = dFdy(uv);
                float det = duv1.x * duv2.y - duv1.y * duv2.x;
                float s = det < 0.0 ? -1.0 : 1.0;
                vec3 T = (dp1 * duv2.y - dp2 * duv1.y) * s;
                vec3 B = (dp2 * duv1.x - dp1 * duv2.x) * s;
                // Gram-Schmidt：去掉与插值法线平行的分量，避免三角形之间出现折痕
                T = normalize(T - N * dot(N, T));
                B = normalize(B - N * dot(N, B));
                return mat3(T, B, N);   // GLSL 按列放：列 = T、B、N（HLSL 的 half3x3(T, B, N) 按行放）
            }
            //#endregion

            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 normalTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
            #if defined(_DERIVATIVE_TBN)
                mat3 tbn = DerivativeTangentFrame(N, positionWS, uv);
            #else
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                mat3 tbn = mat3(tangentWS.xyz, bitangent, normalWS);
            #endif
                vec3 nWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tbn));
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                fragColor = vec4(Ch07Shade(positionWS, nWS, albedo, 0.45, 0.15, 1.0), 1.0);
            }
            #endif
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
