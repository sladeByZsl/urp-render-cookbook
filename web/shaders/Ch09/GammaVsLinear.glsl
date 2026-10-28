// 第 9 章：在 Gamma 空间做光照 vs 在线性空间做光照。（GLSL 版，对应 Ch09/GammaVsLinear.shader）
// 两盏灯：主光（场景里的方向光）+ 一盏由材质参数给出的“虚拟”方向光，方便控制颜色和方向。
// Linear：贴图解码后的线性值 × 线性灯光，最后由管线写入 sRGB 目标时统一编码 —— 正确做法。
// Gamma ：故意把颜色先编码回 sRGB 再做乘加（相当于老式 Gamma 工作流），
//         最后再解码一次，抵消管线的编码，让屏幕上看到的就是“在 Gamma 空间算出来的数”。
Shader "Cookbook/Ch09/GammaVsLinear"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            // LinearToSRGB / SRGBToLinear 在自动包含的 Core.glsl 里（HLSL 版来自 core 包的 Color.hlsl）
            uniform float _GammaSpace;
            uniform vec4 _BaseColor, _Light2Dir, _Light2Color;

            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                Light l1 = GetMainLight();
                vec3 L2 = normalize(_Light2Dir.xyz);

                // 材质颜色、灯光颜色在 Shader 里拿到的都已经是线性值
                vec3 albedo = _BaseColor.rgb;
                vec3 c1 = l1.color, c2 = _Light2Color.rgb;

                if (_GammaSpace > 0.5)
                {
                    // 错误示范：把它们变回 sRGB 编码值再去做乘法和加法
                    albedo = LinearToSRGB(albedo);
                    c1 = LinearToSRGB(c1);
                    c2 = LinearToSRGB(c2);
                }

                vec3 lit = albedo * (c1 * saturate(dot(N, l1.direction)) + c2 * saturate(dot(N, L2)));

                if (_GammaSpace > 0.5)
                    lit = SRGBToLinear(saturate(lit));  // 抵消管线最后的 sRGB 编码

                fragColor = vec4(lit, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
