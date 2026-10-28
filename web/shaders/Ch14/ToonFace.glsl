// 面部 SDF 阴影：脸上的明暗交界不再由法线决定，而是查一张“阈值图”——（GLSL 版，对应 Ch14/ToonFace.shader）
// 图里每个像素存的是“光从正面转到多少度时，这里开始进入阴影”。
Shader "Cookbook/Ch14/ToonFace"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4 _BaseColor, _ShadeColor;
        uniform float _SdfSoftness, _DrawFeatures;
        uniform vec4 _OutlineColor;
        uniform float _OutlineWidth;
        uniform sampler2D _FaceSdf;
        ENDGLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _FACESHADOW_NORMAL _FACESHADOW_SDF
            #define TOON_VARYINGS
            #include "Ch14/ToonCommon.glsl"

            #ifdef VERTEX
            void main() { ToonVert(); }
            #endif

            #ifdef FRAGMENT
            // 简笔五官（只为让球看起来像一张脸）：两只眼睛、腮红和嘴
            vec3 DrawFeatures(vec3 color, vec2 uv, float frontMask)
            {
                vec2 e1 = (uv - vec2(0.36, 0.56)) / vec2(0.045, 0.07);
                vec2 e2 = (uv - vec2(0.64, 0.56)) / vec2(0.045, 0.07);
                float eye = step(min(dot(e1, e1), dot(e2, e2)), 1.0);
                vec2 h1 = (uv - vec2(0.35, 0.58)) / 0.018, h2 = (uv - vec2(0.63, 0.58)) / 0.018;
                float hl = step(min(dot(h1, h1), dot(h2, h2)), 1.0);
                vec2 b1 = (uv - vec2(0.3, 0.45)) / vec2(0.07, 0.035), b2 = (uv - vec2(0.7, 0.45)) / vec2(0.07, 0.035);
                float blush = smoothstep(1.0, 0.3, min(dot(b1, b1), dot(b2, b2)));
                vec2 m = uv - vec2(0.5, 0.36);
                float mouth = step(abs(length(m / vec2(1, 0.7) + vec2(0, 0.05)) - 0.06), 0.006) * step(m.y, -0.005);
                color = mix(color, color * vec3(1.0, 0.75, 0.75), blush * 0.6 * frontMask);
                color = mix(color, vec3(0.18, 0.12, 0.2), max(eye, mouth) * frontMask);
                color = mix(color, vec3(1.0), hl * frontMask);
                return color;
            }

            //#region frag
            vec4 frag()
            {
                Light light = GetMainLight();
                vec2 faceUV = objectPositionOS.xy + 0.5;          // 正面投影：物体空间 xy → 0~1
                float lit;

            #if defined(_FACESHADOW_NORMAL)
                // 对照组：按法线做色阶，鼻子、眼窝的起伏会让阴影边缘碎成一块一块
                vec3 N = normalize(normalWS);
                lit = ToonBand(dot(N, light.direction) * 0.5 + 0.5, 0.5, 0.01);
            #else
                // 1) 头部的朝向（物体空间 -Z 是脸的正前方，+X 是画面右侧）
                vec3 F = normalize(TransformObjectToWorldDir(vec3(0, 0, -1)));
                vec3 R = normalize(TransformObjectToWorldDir(vec3(1, 0, 0)));
                vec3 U = normalize(TransformObjectToWorldDir(vec3(0, 1, 0)));
                // 2) 光方向投影到头部的水平面，只关心“从哪一侧、转了多少度”
                vec3 Lh = light.direction - U * dot(light.direction, U);
                Lh = normalize(Lh + 1e-5);
                float phi = acos(clamp(dot(F, Lh), -1.0, 1.0)) / PI;   // 0 = 正面光，1 = 正背光
                // 3) 阈值图是按“光从右边来”画的，光从左边来就把 U 镜像
                vec2 uv = faceUV;
                if (dot(R, Lh) < 0.0) uv.x = 1.0 - uv.x;
                float threshold = texture(_FaceSdf, uv).r;
                // 4) 当前角度小于该像素的阈值 → 亮
                lit = smoothstep(phi - _SdfSoftness, phi + _SdfSoftness, threshold);
            #endif

                vec3 color = mix(_ShadeColor.rgb, _BaseColor.rgb, lit) * light.color;
                color += SampleSH(vec3(0.0)) * _BaseColor.rgb * 0.25;
                if (_DrawFeatures > 0.5)
                    color = DrawFeatures(color, faceUV, step(objectPositionOS.z, 0.0));
                return vec4(MixFog(color, fogFactor), 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            GLSLPROGRAM
            #include "Ch14/ToonOutlinePass.glsl"
            ENDGLSL
        }

        UsePass "Cookbook/Common/SHADOWCASTER"
        UsePass "Cookbook/Common/DEPTHONLY"
        UsePass "Cookbook/Common/DEPTHNORMALS"
    }
}
