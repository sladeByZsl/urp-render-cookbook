// 案例 4.7：fBm 云纹 —— 叠加多层噪声，加上覆盖率和软边，就是一片天空。（GLSL 版）
Shader "Cookbook/Ch04/FbmClouds"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #include "Ch04/ProceduralCommon.glsl"

            uniform float _Octaves, _Scale, _Lacunarity, _Gain, _Cover, _Softness;
            uniform vec4  _Wind, _Offset;
            uniform vec4  _SkyTop, _SkyBottom, _CloudLit, _CloudShade;

            #ifdef FRAGMENT
            void main()
            {
                vec2 p = uv * _Scale + _Offset.xy + _Wind.xy * _Time.y;
                int oct = int(_Octaves);
                //#region clouds
                float n = Fbm(p, oct, _Lacunarity, _Gain) * 0.5 + 0.5;          // → [0,1]
                // 覆盖率：把阈值往下推，云就变多；smoothstep 的宽度决定边缘软硬
                float density = smoothstep(1.0 - _Cover, 1.0 - _Cover + _Softness, n);
                // 简单的“自阴影”：朝光源方向（左上）偏移一点再采一次，差值当作明暗
                float n2 = Fbm(p + vec2(-0.06, 0.06), oct, _Lacunarity, _Gain) * 0.5 + 0.5;
                float lit = saturate(0.5 + (n - n2) * 6.0);
                //#endregion
                vec3 sky = mix(_SkyBottom.rgb, _SkyTop.rgb, uv.y);
                vec3 cloud = mix(_CloudShade.rgb, _CloudLit.rgb, lit);
                fragColor = vec4(mix(sky, cloud, density), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
