// 第 2 章 案例 2.5：LightMode 标签决定“谁来画这个 Pass”
// 一个 Shader 三个 Pass：
//   Pass 1  LightMode = UniversalForward ：URP 的不透明/透明绘制 Pass 会画它（正常着色）
//   Pass 2  不写 LightMode               ：被当作 SRPDefaultUnlit，URP 也会在同一次绘制里画它（这里做外描边）
//   Pass 3  LightMode = CookbookXRay      ：URP 自己不认识，默认谁也不画；用 RenderObjects 这类 Feature 点名才会画（这里做 X 光透视）
Shader "Cookbook/Ch02/LightModeDemo"
{
    GLSLINCLUDE
    // 三个 Pass 共用同一份 UnityPerMaterial，SRP Batcher 才能兼容（GLSL 里就是普通 uniform）
    uniform vec4  _BaseColor;
    uniform vec4  _OutlineColor;
    uniform float _OutlineWidth;
    uniform vec4  _XRayColor;

    VARYING vec3 normalWS;

    #ifdef VERTEX
    void VertDefault()
    {
        gl_Position = TransformObjectToHClip(positionOS.xyz);
        normalWS = TransformObjectToWorldNormal(normalOS);
    }
    #endif
    ENDGLSL

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        //#region passes
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VertDefault(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                vec3 n = normalize(normalWS);
                Light light = GetMainLight();
                vec3 diffuse = light.color * saturate(dot(n, light.direction));
                vec3 ambient = SampleSH(n);
                fragColor = vec4(_BaseColor.rgb * (diffuse + ambient), 1);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Outline"
            // 没有 LightMode 标签 → URP 视为 "SRPDefaultUnlit"
            Cull Front

            GLSLPROGRAM
            #ifdef VERTEX
            void main()
            {
                // 沿法线把顶点往外推，只画背面，就得到一圈“外壳”描边（第 14 章细讲）
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 nWS = TransformObjectToWorldNormal(normalOS);
                gl_Position = TransformWorldToHClip(positionWS + nWS * _OutlineWidth);
                normalWS = nWS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = _OutlineColor; }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "XRay"
            Tags { "LightMode"="CookbookXRay" }
            // 只在“被挡住”的地方画：深度比已有深度更远才通过
            ZTest Greater
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VertDefault(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = _XRayColor; }
            #endif
            ENDGLSL
        }
        //#endregion
    }
}
