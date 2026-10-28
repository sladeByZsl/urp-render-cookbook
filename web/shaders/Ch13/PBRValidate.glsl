// PBR 校验视图：读取 URP Lit 材质的属性（同名），把“超出合理范围”的像素用斜条纹高亮。（GLSL 版，对应 Ch13/PBRValidate.shader）
//   红：电介质 Albedo 过暗      蓝：电介质 Albedo 过亮
//   黄：金属度处在 0~1 之间的灰区（通常只该出现在过渡边缘）
//   品红：金属的 Albedo（即 F0）过暗
// 用法一：在材质上临时把 Shader 换成它（同名属性与关键字会保留），看完再换回 Lit。
// 用法二：RenderObjects 的 Override Mode = Shader，一键对整个场景生效（见 PBRValidateFeature 的配置代码）。
Shader "Cookbook/Ch13/PBRValidate"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Validate"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP

            uniform vec4  _BaseMap_ST;
            uniform vec4  _BaseColor;
            uniform float _Metallic;
            uniform float _Smoothness;
            uniform sampler2D _BaseMap;
            uniform sampler2D _MetallicGlossMap;

            //#region thresholds
            // 阈值用 sRGB 0~1 表示（美术在取色器里看到的数值 / 255）。
            // 全局变量，由 C# 用 Shader.SetGlobalVector 设置；w <= 0 时使用下面的默认值。
            uniform vec4 _PBRValidateRange;   // x 电介质最暗  y 电介质最亮  z 金属最暗
            #define DEFAULT_RANGE vec3(30.0 / 255.0, 240.0 / 255.0, 180.0 / 255.0)
            #define METAL_GRAY_LOW  0.1
            #define METAL_GRAY_HIGH 0.9
            //#endregion

            VARYING vec2 uv;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region validate
            void main()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;   // 线性
            #if defined(_METALLICSPECGLOSSMAP)
                float metallic = texture(_MetallicGlossMap, uv).r;
            #else
                float metallic = _Metallic;
            #endif

                vec3 range = _PBRValidateRange.w > 0.0 ? _PBRValidateRange.xyz : DEFAULT_RANGE;
                // 回到 sRGB 再比较，和美术在 Photoshop/Substance 里看到的数值一致
                float lumS = LinearToSRGB(vec3(Luminance(albedo))).x;
                float maxS = LinearToSRGB(vec3(max(albedo.r, max(albedo.g, albedo.b)))).x;

                vec3 flag = vec3(0.0); float bad = 0.0;
                if (metallic > METAL_GRAY_LOW && metallic < METAL_GRAY_HIGH) { flag = vec3(1, 0.85, 0); bad = 1.0; }   // 黄
                else if (metallic >= METAL_GRAY_HIGH)
                {
                    if (maxS < range.z) { flag = vec3(1, 0, 1); bad = 1.0; }                                          // 品红
                }
                else
                {
                    if (lumS < range.x)      { flag = vec3(1, 0.1, 0.1); bad = 1.0; }                                // 红
                    else if (lumS > range.y) { flag = vec3(0.15, 0.35, 1); bad = 1.0; }                              // 蓝
                }

                // 底图：Albedo 亮度 × 简单的半兰伯特，保留形体，又不让光照干扰“材质值”的判断
                float ndl = dot(normalize(normalWS), GetMainLight().direction) * 0.5 + 0.5;
                vec3 baseCol = vec3(Luminance(albedo)) * (0.35 + 0.65 * ndl);

                // 屏幕空间斜条纹：一眼能和“本来就是这个颜色的材质”区分开
                float stripe = fract((gl_FragCoord.x + gl_FragCoord.y) / 14.0) < 0.5 ? 1.0 : 0.0;
                vec3 c = mix(baseCol, flag, bad * mix(0.35, 0.9, stripe));
                fragColor = vec4(c, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
