// 草地风动：风场是一张在世界 XZ 上平移的噪声图（阵风），再叠加每根草相位不同的小幅摆动。（GLSL 版）
// 弯曲量按高度权重的平方分配：根部不动、越靠上越弯；同时略微压低高度，近似保持草叶长度。
Shader "Cookbook/Ch17/Grass"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _RootColor, _TipColor, _GustColor;
        uniform vec4 _WindDir;
        uniform float _WindStrength, _WindScale, _WindSpeed, _Sway, _Phase;
        uniform sampler2D _WindNoise;
        #include "Ch17/VertexAnimCommon.glsl"

        //#region deform
        void Deform(inout VAAttributes v)
        {
            float h = v.color.r;                 // 0 根 → 1 尖
            float rnd = v.color.g;
            float bladeHeight = v.uv1.w;
            vec3 rootWS = TransformObjectToWorld(v.uv1.xyz);
            vec2 wind = normalize(_WindDir.xy);
            float t = _Time.y * _WindSpeed + _Phase;

            // 1) 阵风：噪声图沿风向平移，用根部的世界坐标采样 → 整根草取同一个值，相邻的草相近
            vec2 nuv = rootWS.xz * _WindScale - wind * t * 0.15;
            float gust = textureLod(_WindNoise, nuv, 0.0).r;
            gust = smoothstep(0.3, 0.75, gust);

            // 2) 摆动：每根草相位不同的小幅正弦，避免整齐划一
            float sway = sin(t * 3.0 + rnd * TWO_PI + dot(rootWS.xz, wind) * 2.0) * _Sway;

            // 3) 弯曲：根部不动，按 h² 分配；水平位移 d 时高度大约降低 d²/2（保持叶长）
            float bend = (_WindStrength * (0.2 + gust) + sway) * h * h;
            vec3 dirOS = mat3(unity_WorldToObject) * vec3(wind.x, 0.0, wind.y);   // HLSL：mul((float3x3)GetWorldToObjectMatrix(), dir)
            v.positionOS.xyz += dirOS * bend * bladeHeight;
            v.positionOS.y   -= 0.5 * bend * bend * bladeHeight;

            v.uv2 = vec4(gust, 0.0, 0.0, 0.0);   // 把阵风强度交给片元，用来提亮被风压弯的草尖
        }
        //#endregion

        #include "Ch17/VertexAnimPasses.glsl"
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VAForwardVert(); }
            #endif
            #ifdef FRAGMENT
            void main()
            {
                float h = vertColor.r, rnd = vertColor.g;
                // 细长的草叶法线意义不大：往“上”方向偏，整片草地的明暗更柔和
                vec3 N = normalize(normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0) + vec3(0.0, 1.5, 0.0));
                vec3 albedo = mix(_RootColor.rgb, _TipColor.rgb, h) * (0.8 + 0.4 * rnd);
                albedo = mix(albedo, _GustColor.rgb, extra.x * h * h * 0.6);
                float ao = mix(0.45, 1.0, h);   // 草根互相遮挡，简单压暗
                fragColor = vec4(VALighting(albedo, N, positionWS, 0.1, 16.0) * ao, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VAShadowVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { VANullFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Off
            GLSLPROGRAM
            #ifdef VERTEX
            void main() { VADepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { VANullFrag(); }
            #endif
            ENDGLSL
        }
    }
}
