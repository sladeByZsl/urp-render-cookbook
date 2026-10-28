// 案例 30.1：可切换输出的“调试视图” Shader。把中间量直接画成颜色，是 Shader 调试最快的手段。（GLSL 版，对应 Ch30/DebugView.shader）
// _DebugView：0 最终光照 1 世界法线 2 UV 3 N·L 4 主光阴影 5 切线空间法线贴图 6 世界坐标网格
Shader "Cookbook/Ch30/DebugView"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "ForwardDebug"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            // 主光阴影、软阴影关键字网页版引擎始终打开
            // 需要逐像素调试时：浏览器里没有 RenderDoc 单步，最常用的办法就是本 Shader 这样“把中间量画成颜色”
            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;
            uniform vec4  _BaseMap_ST;
            uniform float _BumpScale;
            uniform float _DebugView;

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
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region debug
            void main()
            {
                vec3 normalTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
                vec3 bitangentWS = tangentWS.w * cross(normalWS, tangentWS.xyz);
                vec3 nWS = normalize(TransformTangentToWorld(normalTS, mat3(tangentWS.xyz, bitangentWS, normalWS)));

                Light light = GetMainLight(TransformWorldToShadowCoord(positionWS));
                float ndl = saturate(dot(nWS, light.direction));
                int view = int(_DebugView);

                // 约定：方向向量 [-1,1] 映射到 [0,1] 再显示；标量直接显示为灰度
                if (view == 1) { fragColor = vec4(nWS * 0.5 + 0.5, 1.0); return; }
                if (view == 2) { fragColor = vec4(fract(uv), 0.0, 1.0); return; }
                if (view == 3) { fragColor = vec4(vec3(ndl), 1.0); return; }
                if (view == 4) { fragColor = vec4(vec3(light.shadowAttenuation), 1.0); return; }
                if (view == 5) { fragColor = vec4(normalTS * 0.5 + 0.5, 1.0); return; }
                if (view == 6)
                {
                    vec3 g = abs(fract(positionWS * 2.0 + 0.5) - 0.5) / fwidth(positionWS * 2.0);
                    float line01 = 1.0 - saturate(min(g.x, min(g.y, g.z)));
                    fragColor = vec4(mix(vec3(0.15, 0.15, 0.18), vec3(1, 0.6, 0.2), line01), 1.0);
                    return;
                }

                vec3 albedo = texture(_BaseMap, uv).rgb;
                vec3 color = albedo * (light.color * ndl * light.shadowAttenuation + SampleSH(nWS));
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
        // 投射阴影直接借用 URP Lit 的 ShadowCaster（会让本 Shader 不兼容 SRP Batcher，调试 Shader 无所谓）
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}
