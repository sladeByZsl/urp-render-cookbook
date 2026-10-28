// 案例 28.5：体积光（主光方向光的光束 / God Rays）。
// Pass 0：半分辨率光线步进，逐步采样主光阴影图；Pass 1/2：可分离模糊；Pass 3：合成到相机颜色；Pass 4：只看散射项
Shader "Cookbook/Ch28/VolumetricLight"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        GLSLINCLUDE
        #include "Ch28/ScreenSpaceCommon.glsl"
        #define FOUR_PI 12.5663706144
        #define INV_FOUR_PI 0.07957747155

        uniform float _Density, _Anisotropy, _MaxDistance, _Steps, _Intensity, _Jitter;
        uniform vec4 _Tint;
        uniform vec4 _VolTexelSize;           // 体积纹理的 (1/w, 1/h, w, h)
        uniform sampler2D _VolumetricResult;  // 合成时读取（r = 散射，g = 透射率）

        vec4 Blur9(vec2 uv, vec2 dir)
        {
            const float w[5] = float[5](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
            vec4 sum = texture(_BlitTexture, uv) * w[0];
            for (int i = 1; i < 5; i++)
            {
                sum += texture(_BlitTexture, uv + dir * float(i)) * w[i];
                sum += texture(_BlitTexture, uv - dir * float(i)) * w[i];
            }
            return sum;
        }
        ENDGLSL

        Pass
        {
            Name "RayMarch"
            GLSLPROGRAM
            //#region keywords
            // 主光阴影的关键字（_MAIN_LIGHT_SHADOWS 等）网页版始终开启，不用声明。
            // 不需要 _MAIN_LIGHT_SHADOWS_SCREEN：屏幕空间阴影只有“表面”上的结果，体积里的点用不上。
            //#endregion
            #ifdef FRAGMENT
            float InterleavedGradientNoise(vec2 pixCoord, int frameCount)
            {
                pixCoord += float(frameCount) * vec2(2.083, 4.867);
                return fract(52.9829189 * fract(dot(pixCoord, vec2(0.06711056, 0.00583715))));
            }

            //#region march
            // Henyey-Greenstein 相位函数：g>0 时向前散射为主，迎着光看最亮
            float PhaseHG(float cosTheta, float g)
            {
                float g2 = g * g;
                return INV_FOUR_PI * (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
            }

            vec4 FragMarch()
            {
                vec2 uv = texcoord;
                float depth = SampleDeviceDepth(uv);
                vec3 endWS = IsSkyDepth(depth)
                    ? ComputeWorldSpacePosition(uv, UNITY_RAW_FAR_CLIP_VALUE, UNITY_MATRIX_I_VP)
                    : ReconstructPositionWS(uv, depth);

                vec3 rayWS = endWS - _WorldSpaceCameraPos;
                float rayLength = min(length(rayWS), _MaxDistance);
                vec3 dir = rayWS / max(length(rayWS), 1e-4);

                Light mainLight = GetMainLight();
                float phase = PhaseHG(dot(dir, mainLight.direction), _Anisotropy);

                int steps = int(_Steps);
                float stepLength = rayLength / float(steps);
                // 抖动起点：把“条带”换成高频噪声，再交给模糊去掉
                float jitter = _Jitter > 0.5 ? InterleavedGradientNoise(gl_FragCoord.xy, 0) : 0.5;

                float scatter = 0.0;
                float transmittance = 1.0;
                float stepT = exp(-_Density * stepLength);    // 每步的透射率（均匀介质）
                for (int i = 0; i < steps; i++)
                {
                    float t = (float(i) + jitter) * stepLength;
                    vec3 p = _WorldSpaceCameraPos + dir * t;
                    // 关键两行：世界坐标 → 阴影坐标（自动选级联）→ 比较阴影图
                    vec4 shadowCoord = TransformWorldToShadowCoord(p);
                    float visibility = MainLightRealtimeShadow(shadowCoord);
                    // 这一小段介质散射到相机方向的光，再乘上它到相机之间的透射率
                    scatter += visibility * transmittance * (1.0 - stepT);
                    transmittance *= stepT;
                }
                scatter *= phase * _Intensity * FOUR_PI;  // ×4π 让 g=0 时的强度约为 1，便于调参
                return vec4(scatter, transmittance, 0.0, 1.0);
            }
            //#endregion
            void main() { fragColor = FragMarch(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "BlurH"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur9(texcoord, vec2(_VolTexelSize.x, 0.0)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "BlurV"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur9(texcoord, vec2(0.0, _VolTexelSize.y)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "Composite"
            GLSLPROGRAM
            #ifdef FRAGMENT
            //#region composite
            void main()
            {
                vec4 color = SamplePointClamp(_BlitTexture, texcoord);
                vec2 vol = texture(_VolumetricResult, texcoord).rg;
                vec3 lightColor = GetMainLight().color * _Tint.rgb;
                // 场景被介质衰减（×透射率），再加上介质散射进视线的光
                color.rgb = color.rgb * vol.g + lightColor * vol.r;
                fragColor = color;
            }
            //#endregion
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "ShowScatter"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                float s = texture(_VolumetricResult, texcoord).r;
                fragColor = vec4(vec3(s), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
