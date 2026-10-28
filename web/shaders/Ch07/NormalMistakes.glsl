// 法线贴图的三种常见“写错/用错”，与正确写法放在一起对比。（GLSL 版，对应 Ch07/NormalMistakes.shader）
Shader "Cookbook/Ch07/NormalMistakes"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform float _BumpScale;
        uniform float _Mistake;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
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

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                vec4 packed = texture(_BumpMap, uv);
                vec3 normalTS;
                if (_Mistake > 0.5 && _Mistake < 1.5)
                {
                    // 错误 1：照搬“rgb*2-1”。桌面平台法线贴图默认压成 DXT5nm/BC5，
                    // 数据在 A/G（或 R/G）通道里，B 通道是 0，这样解出来的向量完全不对。
                    // （网页版的法线贴图是未压缩的 RGB，这里先把 B 清零，模拟 Unity 桌面平台 BC5 采样到的数据）
                    packed.b = 0.0;
                    normalTS = packed.rgb * 2.0 - 1.0;
                    normalTS.xy *= _BumpScale;
                }
                else
                {
                    normalTS = UnpackNormalScale(packed, _BumpScale);
                    // 错误 2：贴图按 DirectX 约定（Y 朝下）烘焙，却直接给 Unity（OpenGL 约定，Y 朝上）用
                    if (_Mistake > 1.5 && _Mistake < 2.5) normalTS.y = -normalTS.y;
                }

                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 nWS = TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangent, normalWS));
                // 错误 3：忘了归一化（插值后的 TBN 和缩放过的 normalTS 都不是单位长度）
                if (_Mistake < 2.5) nWS = normalize(nWS);

                vec3 albedo = texture(_BaseMap, uv).rgb;
                fragColor = vec4(Ch07Shade(positionWS, nWS, albedo, 0.45, 0.15, 1.0), 1.0);
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
