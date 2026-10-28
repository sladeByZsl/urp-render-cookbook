// 只显示球谐环境光（间接漫反射），可以选择只用 L0、L0+L1、或完整的 L0+L1+L2。（GLSL 版，对应 Ch08/AmbientSH.shader）
Shader "Cookbook/Ch08/AmbientSH"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Bands;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region bands
            // unity_SHAr/Ag/Ab：xyz = L1 三个系数，w = L0 系数“减去”L2 里 Y20 的常数部分；
            // unity_SHBr/Bg/Bb：L2 中 xy、yz、zz、zx 四项；unity_SHC：L2 中 x²-y² 一项（rgb 三通道）。
            // 这些系数已经乘上了“余弦卷积”因子并除以 π，所以直接算出来的就是 URP 约定下的间接漫反射。
            vec3 EvaluateSHBands(vec3 N, int bands)
            {
                // L2 在整个球面上积分为 0，但 zz 项的平均值是 1/3。Unity 把 Y20 的常数部分挪进了 w，
                // 想要“纯 L0”，就把 zz 项的平均值 SHB.z/3 加回去。
                vec3 L0 = vec3(unity_SHAr.w + unity_SHBr.z / 3.0,
                               unity_SHAg.w + unity_SHBg.z / 3.0,
                               unity_SHAb.w + unity_SHBb.z / 3.0);
                if (bands == 0) return L0;

                vec3 L1 = vec3(dot(unity_SHAr.xyz, N), dot(unity_SHAg.xyz, N), dot(unity_SHAb.xyz, N));
                if (bands == 1) return max(vec3(0.0), L0 + L1);

                // 完整三阶：与 URP 的 SampleSH(N) 完全相同（SHEvalLinearL0L1 + SHEvalLinearL2）
                return SampleSH(N);
            }
            //#endregion

            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 irradiance = EvaluateSHBands(N, int(round(_Bands)));
                fragColor = vec4(irradiance * _BaseColor.rgb, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
