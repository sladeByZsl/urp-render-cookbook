// 把切线空间的三根轴（T/B/N）和法线贴图扰动后的法线显示成颜色，用来检查网格切线是否正确。（GLSL 版，对应 Ch07/TBNDebug.shader）
Shader "Cookbook/Ch07/TBNDebug"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _Tiling;
        uniform float _Mode;
        uniform float _BumpScale;
        ENDGLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            uniform sampler2D _BumpMap;

            // 顶点输入：tangentOS 的 xyz = 切线，w = 副切线的朝向（±1）
            VARYING vec2 uv;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;   // w 保存 sign，副切线在片元里重建

            //#region vert
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy * _Tiling.xy + _Tiling.zw;
                // GetVertexNormalInputs 会：法线用逆转置矩阵变换、切线按方向变换、
                // 副切线 = cross(N, T) * tangentOS.w * GetOddNegativeScale()
                VertexNormalInputs n = GetVertexNormalInputs(normalOS, tangentOS);
                normalWS = n.normalWS;
                tangentWS = vec4(n.tangentWS, tangentOS.w * GetOddNegativeScale());
            }
            #endif
            //#endregion

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                // 插值之后长度不再为 1，先归一化（MikkTSpace 的约定是在像素里才归一化）
                vec3 N = normalize(normalWS);
                vec3 T = normalize(tangentWS.xyz);
                vec3 B = tangentWS.w * cross(N, T);
                vec3 c;
                if (_Mode < 0.5)      c = T;
                else if (_Mode < 1.5) c = B;
                else if (_Mode < 2.5) c = N;
                else
                {
                    vec3 nTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
                    // HLSL 的 half3x3(T, B, N) 按行放，mul(向量, 矩阵) = nTS.x*T + nTS.y*B + nTS.z*N；
                    // GLSL 的 mat3(T, B, N) 按列放，TransformTangentToWorld 里写成 矩阵 * 向量，结果相同
                    c = normalize(TransformTangentToWorld(nTS, mat3(T, B, N)));
                }
                fragColor = vec4(c * 0.5 + 0.5, 1.0);   // [-1,1] 映射到 [0,1] 才能当颜色看
            }
            #endif
            //#endregion
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
