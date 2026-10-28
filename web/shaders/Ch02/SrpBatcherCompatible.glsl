// 第 2 章 2.10 节 / 案例 2.6：兼容 SRP Batcher 的最小 Shader
// 关键：所有材质属性（Properties 里声明的）都放进同一个名为 UnityPerMaterial 的 CBUFFER，
// 并且每个 Pass 里这个 CBUFFER 的内容和顺序完全一致。
// （GLSL 版）WebGL 没有 CBUFFER，材质属性写成普通 uniform 即可。
Shader "Cookbook/Ch02/SrpBatcherCompatible"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            //#region cbuffer
            // 纹理对象本身不进 CBUFFER，但它的 _ST（缩放平移）是数值，要进
            uniform sampler2D _BaseMap;
            // CBUFFER_START(UnityPerMaterial)
            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;
            // CBUFFER_END
            //#endregion

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                fragColor = texture(_BaseMap, uv) * _BaseColor;
            }
            #endif
            ENDGLSL
        }
    }
}
