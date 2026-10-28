// 第 3 步：读取网格的顶点色，和贴图、颜色相乘。
Shader "Cookbook/Ch03/VertexColor"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            //#region io
            // 顶点输入 color：顶点色 Mesh.colors，没有顶点色的网格读到 (1,1,1,1)
            VARYING vec2 uv;
            VARYING vec4 vColor;      // 光栅化时在三角形内部线性插值
            //#endregion

            uniform sampler2D _BaseMap;
            uniform vec4  _BaseMap_ST;
            uniform vec4  _BaseColor;
            uniform float _VertexColorStrength;

            //#region vertfrag
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                vColor = color;     // 原样传下去，插值交给硬件
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec4 tex = texture(_BaseMap, uv);
                // lerp(1, 顶点色, 强度)：强度为 0 时乘以白色，等于不起作用
                vec4 vc = mix(vec4(1, 1, 1, 1), vColor, _VertexColorStrength);
                fragColor = tex * _BaseColor * vc;
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
