// 混合模式实验台：源/目标因子和混合运算都做成材质属性，同一个 Shader 切出所有常见模式。（GLSL 版）
// _Output 决定片元输出的形式：直通（rgb, a）/ 预乘（贴图已预乘）/ 乘法就绪（lerp(1, rgb, a)）。
Shader "Cookbook/Ch16/BlendModes"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Blend"
            Tags { "LightMode"="UniversalForward" }
            //#region state
            BlendOp [_BlendOp]
            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            Cull Off
            //#endregion

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _OUTPUT_STRAIGHT _OUTPUT_PREMULTIPLY _OUTPUT_MULTIPLYREADY

            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;
            uniform sampler2D _BaseMap;

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec4 tex = texture(_BaseMap, uv);
                vec3 rgb = tex.rgb * _BaseColor.rgb;
                float a  = tex.a * _BaseColor.a;
            #if defined(_OUTPUT_PREMULTIPLY)
                // 预乘：贴图的 rgb 已经乘过 alpha（导出时完成），这里只再乘上材质的不透明度。
                // 于是 rgb 可以“大于” alpha——alpha = 0 而 rgb > 0 的像素就是纯叠加的辉光
                return vec4(tex.rgb * _BaseColor.rgb * _BaseColor.a, a);
            #elif defined(_OUTPUT_MULTIPLYREADY)
                return vec4(mix(vec3(1.0), rgb, a), a);  // 乘法类：透明处输出白色（乘 1 不变）
            #else
                return vec4(rgb, a);                     // 直通
            #endif
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
