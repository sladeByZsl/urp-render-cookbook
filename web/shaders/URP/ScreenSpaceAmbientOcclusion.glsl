// URP 14 自带 SSAO（Shaders/Utils/ScreenSpaceAmbientOcclusion.shader + ShaderLibrary/SSAO.hlsl）的 GLSL 版。
// Pass 顺序与 URP 相同（C# 里按下标调用）：
//   0 遮蔽  1~3 双边模糊（横/竖/最终）  4 双边最终（AfterOpaque）  5~6 高斯（横/竖）  7 高斯（AfterOpaque）  8 Kawase  9 Kawase（AfterOpaque）
// URP 用关键字切换的选项（采样数、噪声、法线来源、正交相机）这里改成 uniform。
// 深度约定：WebGL 不反转深度（近 0 远 1），所以“天空”的判断改成 rawDepth > 1 - SKY_DEPTH_VALUE。
Shader "Hidden/Universal Render Pipeline/ScreenSpaceAmbientOcclusion"
{
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        GLSLINCLUDE
        VARYING vec2 uv;
        #ifdef VERTEX
        void main()
        {
            vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
            uv = p;
            gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        }
        #endif
        uniform sampler2D _BlueNoiseTexture;
        uniform vec4 _CameraDepthTexture_TexelSize;
        uniform float _KawaseBlurIteration;
        uniform float _LastKawasePass;
        uniform vec4 _SSAOParams;               // (强度, 半径, 1/降采样, 衰减距离)
        uniform vec4 _SSAOBlueNoiseParams;      // (缩放 xy, 偏移 zw)
        uniform vec4 _CameraViewTopLeftCorner;  // 以下 4 个：相机相对世界空间里近平面的角点与跨度
        uniform vec4 _CameraViewXExtent;
        uniform vec4 _CameraViewYExtent;
        uniform vec4 _CameraViewZExtent;
        uniform mat4 _CameraViewProjections;
        uniform vec4 _SourceSize;
        uniform vec4 _ProjectionParams2;        // (1/near, 0, 0, 0)
        // 代替 URP 的关键字
        uniform float _SSAOBlueNoise;           // 1 = _BLUE_NOISE，0 = _INTERLEAVED_GRADIENT
        uniform float _SSAOSampleCount;         // 4 / 8 / 12
        uniform float _SSAONormalSource;        // 0 _SOURCE_DEPTH_LOW，1 MEDIUM，2 HIGH，3 _SOURCE_DEPTH_NORMALS
        uniform float _SSAOOrthographic;

        #define INTENSITY _SSAOParams.x
        #define RADIUS _SSAOParams.y
        #define DOWNSAMPLE _SSAOParams.z
        #define FALLOFF _SSAOParams.w
        #define BlueNoiseScale _SSAOBlueNoiseParams.xy
        #define BlueNoiseOffset _SSAOBlueNoiseParams.zw

        const float SSAORandomUV[40] = float[40](
            0.00000000, 0.33984375, 0.75390625, 0.56640625, 0.98437500, 0.07421875, 0.23828125, 0.64062500, 0.35937500, 0.50781250,
            0.38281250, 0.98437500, 0.17578125, 0.53906250, 0.28515625, 0.23137260, 0.45882360, 0.54117650, 0.12941180, 0.64313730,
            0.92968750, 0.76171875, 0.13333330, 0.01562500, 0.00000000, 0.10546875, 0.64062500, 0.74609375, 0.67968750, 0.35156250,
            0.49218750, 0.12500000, 0.26562500, 0.62500000, 0.44531250, 0.17647060, 0.44705890, 0.93333340, 0.87058830, 0.56862750);

        const float kContrast = 0.6;
        const float kGeometryCoeff = 0.8;
        const float kBeta = 0.004;
        const float kEpsilon = 0.0001;
        const float SKY_DEPTH_VALUE = 0.00001;

        #ifdef FRAGMENT
        vec4 SAMPLE_BASEMAP(vec2 p) { return texture(_BlitTexture, p); }
        float SAMPLE_BASEMAP_R(vec2 p) { return texture(_BlitTexture, p).r; }

        vec4 PackAONormal(float ao, vec3 n) { return vec4(ao, n * 0.5 + 0.5); }
        vec3 GetPackedNormal(vec4 p) { return p.gba * 2.0 - 1.0; }
        float GetPackedAO(vec4 p) { return p.r; }
        float CompareNormal(vec3 d1, vec3 d2) { return smoothstep(kGeometryCoeff, 1.0, dot(d1, d2)); }
        vec2 GetScreenSpacePosition(vec2 p) { return p * _ScaledScreenParams.xy * DOWNSAMPLE; }
        float GetRandomVal(float u, float sampleIndex) { return SSAORandomUV[int(u * 20.0 + sampleIndex)]; }

        // Random.hlsl 的 InterleavedGradientNoise
        float IGN(vec2 pixCoord, int frameCount)
        {
            pixCoord += float(frameCount) * vec2(2.083, 4.867);
            return fract(52.9829189 * fract(dot(pixCoord, vec2(0.06711056, 0.00583715))));
        }

        // 蓝噪声贴图：点采样 + 重复（贴图的 alpha 来自灰度，等于 r）
        float SampleBlueNoise(vec2 p)
        {
            ivec2 sz = textureSize(_BlueNoiseTexture, 0);
            ivec2 c = ivec2(floor(p * vec2(sz)));
            c = ((c % sz) + sz) % sz;
            return texelFetch(_BlueNoiseTexture, c, 0).r;
        }

        vec3 PickSamplePoint(vec2 uv, int sampleIndex, float sampleIndexHalf, float rcpSampleCount, vec3 normal_o)
        {
            vec3 v;
            if (_SSAOBlueNoise > 0.5)
            {
                float lerpVal = sampleIndexHalf * rcpSampleCount;
                float noise = SampleBlueNoise(((uv + BlueNoiseOffset) * BlueNoiseScale) + lerpVal);
                float u = fract(GetRandomVal(0.0, sampleIndexHalf) + noise) * 2.0 - 1.0;
                float theta = (GetRandomVal(1.0, sampleIndexHalf) + noise) * TWO_PI * 100.0;
                float u2 = sqrt(1.0 - u * u);
                v = vec3(u2 * cos(theta), u2 * sin(theta), u);
                v *= (dot(normal_o, v) >= 0.0 ? 1.0 : 0.0) * 2.0 - 1.0;
                v *= mix(0.1, 1.0, lerpVal * lerpVal);
            }
            else
            {
                vec2 positionSS = GetScreenSpacePosition(uv);
                float noise = IGN(positionSS, sampleIndex);
                float u = fract(GetRandomVal(0.0, float(sampleIndex)) + noise) * 2.0 - 1.0;
                float theta = (GetRandomVal(1.0, float(sampleIndex)) + noise) * TWO_PI;
                float u2 = sqrt(1.0 - u * u);
                v = vec3(u2 * cos(theta), u2 * sin(theta), u);
                v *= sqrt((sampleIndexHalf + 1.0) * rcpSampleCount);
                v = faceforward(v, -normal_o, v);
            }
            v *= RADIUS;
            return v;
        }

        float SampleDepth(vec2 p)
        {
            p += (_CameraDepthTexture_TexelSize.xy * 0.5) * (1.0 - (DOWNSAMPLE - 0.5) * 2.0);
            return SampleSceneDepth(p);
        }
        float GetLinearEyeDepth(float rawDepth)
        {
            if (_SSAOOrthographic > 0.5) return _ProjectionParams.y + (_ProjectionParams.z - _ProjectionParams.y) * rawDepth;
            return LinearEyeDepth(rawDepth, _ZBufferParams);
        }
        float SampleAndGetLinearEyeDepth(vec2 p) { return GetLinearEyeDepth(SampleDepth(p)); }

        // 由屏幕 UV + 线性深度重建（相机相对的）世界坐标：近平面角点插值后按深度缩放
        vec3 ReconstructViewPos(vec2 p, float linearDepth)
        {
            p.y = 1.0 - p.y;   // 角点从“左上”开始
            if (_SSAOOrthographic > 0.5)
            {
                float zScale = linearDepth * _ProjectionParams.w;
                return _CameraViewTopLeftCorner.xyz + _CameraViewXExtent.xyz * p.x + _CameraViewYExtent.xyz * p.y + _CameraViewZExtent.xyz * zScale;
            }
            float zScale = linearDepth * _ProjectionParams2.x;
            vec3 viewPos = _CameraViewTopLeftCorner.xyz + _CameraViewXExtent.xyz * p.x + _CameraViewYExtent.xyz * p.y;
            return viewPos * zScale;
        }

        vec3 ReconstructNormal(vec2 p, float linearDepth, vec3 vpos)
        {
            if (_SSAONormalSource < 0.5) return normalize(cross(dFdy(vpos), dFdx(vpos)));
            vec2 delta = _SourceSize.zw * 2.0;
            vec2 lUV = vec2(-delta.x, 0.0), rUV = vec2(delta.x, 0.0), uUV = vec2(0.0, delta.y), dUV = vec2(0.0, -delta.y);
            vec3 l1 = vec3(p + lUV, 0.0); l1.z = SampleAndGetLinearEyeDepth(l1.xy);
            vec3 r1 = vec3(p + rUV, 0.0); r1.z = SampleAndGetLinearEyeDepth(r1.xy);
            vec3 u1 = vec3(p + uUV, 0.0); u1.z = SampleAndGetLinearEyeDepth(u1.xy);
            vec3 d1 = vec3(p + dUV, 0.0); d1.z = SampleAndGetLinearEyeDepth(d1.xy);
            int closest_horizontal, closest_vertical;
            if (_SSAONormalSource < 1.5)
            {
                closest_horizontal = l1.z > r1.z ? 0 : 1;
                closest_vertical = d1.z > u1.z ? 0 : 1;
            }
            else
            {
                vec3 l2 = vec3(p + lUV * 2.0, 0.0); l2.z = SampleAndGetLinearEyeDepth(l2.xy);
                vec3 r2 = vec3(p + rUV * 2.0, 0.0); r2.z = SampleAndGetLinearEyeDepth(r2.xy);
                vec3 u2 = vec3(p + uUV * 2.0, 0.0); u2.z = SampleAndGetLinearEyeDepth(u2.xy);
                vec3 d2 = vec3(p + dUV * 2.0, 0.0); d2.z = SampleAndGetLinearEyeDepth(d2.xy);
                closest_horizontal = abs((2.0 * l1.z - l2.z) - linearDepth) < abs((2.0 * r1.z - r2.z) - linearDepth) ? 0 : 1;
                closest_vertical = abs((2.0 * d1.z - d2.z) - linearDepth) < abs((2.0 * u1.z - u2.z) - linearDepth) ? 0 : 1;
            }
            vec3 P1, P2;
            if (closest_vertical == 0) { P1 = closest_horizontal == 0 ? l1 : d1; P2 = closest_horizontal == 0 ? d1 : r1; }
            else { P1 = closest_horizontal == 0 ? u1 : r1; P2 = closest_horizontal == 0 ? l1 : u1; }
            return normalize(cross(ReconstructViewPos(P2.xy, P2.z) - vpos, ReconstructViewPos(P1.xy, P1.z) - vpos));
        }

        vec3 SampleNormal(vec2 p, float linearDepth)
        {
            if (_SSAONormalSource > 2.5) return SampleSceneNormals(p);
            return ReconstructNormal(p, linearDepth, ReconstructViewPos(p, linearDepth));
        }

        vec4 SSAO()
        {
            float rawDepth_o = SampleDepth(uv);
            if (rawDepth_o > 1.0 - SKY_DEPTH_VALUE) return PackAONormal(0.0, vec3(0.0));
            float linearDepth_o = GetLinearEyeDepth(rawDepth_o);
            if (linearDepth_o > FALLOFF) return PackAONormal(0.0, vec3(0.0));

            vec3 normal_o = SampleNormal(uv, linearDepth_o);
            vec3 vpos_o = ReconstructViewPos(uv, linearDepth_o);
            // HLSL 的 _m00/_m01/_m02（第 0 行）与 _m10/_m11/_m12（第 1 行）
            vec3 camTransform000102 = vec3(_CameraViewProjections[0][0], _CameraViewProjections[1][0], _CameraViewProjections[2][0]);
            vec3 camTransform101112 = vec3(_CameraViewProjections[0][1], _CameraViewProjections[1][1], _CameraViewProjections[2][1]);
            vec3 viewRow2 = vec3(unity_MatrixV[0][2], unity_MatrixV[1][2], unity_MatrixV[2][2]);

            int count = int(_SSAOSampleCount);
            float rcpSampleCount = 1.0 / float(count);
            float ao = 0.0;
            float sHalf = -1.0;
            for (int s = 0; s < 12; s++)
            {
                if (s >= count) break;
                sHalf += 1.0;
                vec3 v_s1 = PickSamplePoint(uv, s, sHalf, rcpSampleCount, normal_o);
                vec3 vpos_s1 = vpos_o + v_s1;
                vec2 spos_s1 = vec2(dot(camTransform000102, vpos_s1), dot(camTransform101112, vpos_s1));
                float zDist;
                vec2 uv_s1_01;
                if (_SSAOOrthographic > 0.5) { zDist = linearDepth_o; uv_s1_01 = saturate((spos_s1 + 1.0) * 0.5); }
                else { zDist = -dot(viewRow2, vpos_s1); uv_s1_01 = saturate((spos_s1 / zDist + 1.0) * 0.5); }

                float rawDepth_s = SampleDepth(uv_s1_01);
                float linearDepth_s = GetLinearEyeDepth(rawDepth_s);
                float isInsideRadius = abs(zDist - linearDepth_s) < RADIUS ? 1.0 : 0.0;
                isInsideRadius *= rawDepth_s < 1.0 - SKY_DEPTH_VALUE ? 1.0 : 0.0;

                vec3 v_s2 = ReconstructViewPos(uv_s1_01, linearDepth_s) - vpos_o;
                float dotVal = dot(v_s2, normal_o) - kBeta * linearDepth_o;
                float a1 = max(dotVal, 0.0);
                float a2 = dot(v_s2, v_s2) + kEpsilon;
                ao += a1 / a2 * isInsideRadius;
            }
            ao *= RADIUS;
            float falloff = 1.0 - linearDepth_o / FALLOFF;
            falloff = falloff * falloff;
            ao = PositivePow(saturate(ao * INTENSITY * falloff * rcpSampleCount), kContrast);
            return PackAONormal(ao, normal_o);
        }

        vec4 Blur(vec2 p, vec2 delta)
        {
            vec4 p0 = SAMPLE_BASEMAP(p);
            vec4 p1a = SAMPLE_BASEMAP(p - delta * 1.3846153846);
            vec4 p1b = SAMPLE_BASEMAP(p + delta * 1.3846153846);
            vec4 p2a = SAMPLE_BASEMAP(p - delta * 3.2307692308);
            vec4 p2b = SAMPLE_BASEMAP(p + delta * 3.2307692308);
            vec3 n0 = GetPackedNormal(p0);
            float w0 = 0.2270270270;
            float w1a = CompareNormal(n0, GetPackedNormal(p1a)) * 0.3162162162;
            float w1b = CompareNormal(n0, GetPackedNormal(p1b)) * 0.3162162162;
            float w2a = CompareNormal(n0, GetPackedNormal(p2a)) * 0.0702702703;
            float w2b = CompareNormal(n0, GetPackedNormal(p2b)) * 0.0702702703;
            float s = GetPackedAO(p0) * w0 + GetPackedAO(p1a) * w1a + GetPackedAO(p1b) * w1b + GetPackedAO(p2a) * w2a + GetPackedAO(p2b) * w2b;
            s /= w0 + w1a + w1b + w2a + w2b;
            return PackAONormal(s, n0);
        }

        float BlurSmall(vec2 p, vec2 delta)
        {
            vec4 p0 = SAMPLE_BASEMAP(p);
            vec4 p1 = SAMPLE_BASEMAP(p + vec2(-delta.x, -delta.y));
            vec4 p2 = SAMPLE_BASEMAP(p + vec2( delta.x, -delta.y));
            vec4 p3 = SAMPLE_BASEMAP(p + vec2(-delta.x,  delta.y));
            vec4 p4 = SAMPLE_BASEMAP(p + vec2( delta.x,  delta.y));
            vec3 n0 = GetPackedNormal(p0);
            float w0 = 1.0;
            float w1 = CompareNormal(n0, GetPackedNormal(p1));
            float w2 = CompareNormal(n0, GetPackedNormal(p2));
            float w3 = CompareNormal(n0, GetPackedNormal(p3));
            float w4 = CompareNormal(n0, GetPackedNormal(p4));
            float s = GetPackedAO(p0) * w0 + GetPackedAO(p1) * w1 + GetPackedAO(p2) * w2 + GetPackedAO(p3) * w3 + GetPackedAO(p4) * w4;
            return s / (w0 + w1 + w2 + w3 + w4);
        }
        float FinalBlur() { return 1.0 - BlurSmall(uv, _SourceSize.zw / DOWNSAMPLE); }

        float GaussianBlur(vec2 p, vec2 pixelOffset)
        {
            const float gWeights[2] = float[2](0.44908, 0.05092);
            const float gOffsets[2] = float[2](0.53805, 2.06278);
            float colOut = 0.0;
            for (int i = 0; i < 2; i++)
            {
                vec2 o = gOffsets[i] * pixelOffset;
                colOut += gWeights[i] * (SAMPLE_BASEMAP(p + o).r + SAMPLE_BASEMAP(p - o).r);
            }
            return colOut;
        }

        float KawaseBlurFilter(vec2 texCoord, vec2 pixelSize, float iteration)
        {
            vec2 dUV = pixelSize * iteration + pixelSize * 0.5;
            float c = SAMPLE_BASEMAP_R(vec2(texCoord.x - dUV.x, texCoord.y + dUV.y));
            c += SAMPLE_BASEMAP_R(vec2(texCoord.x + dUV.x, texCoord.y + dUV.y));
            c += SAMPLE_BASEMAP_R(vec2(texCoord.x + dUV.x, texCoord.y - dUV.y));
            c += SAMPLE_BASEMAP_R(vec2(texCoord.x - dUV.x, texCoord.y - dUV.y));
            return c * 0.25;
        }
        float KawaseBlur()
        {
            float col = KawaseBlurFilter(uv, _SourceSize.zw / DOWNSAMPLE, _KawaseBlurIteration);
            if (_LastKawasePass > 0.5) col = 1.0 - col;
            return col;
        }
        #endif
        ENDGLSL

        Pass
        {
            Name "SSAO_Occlusion"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = SSAO(); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Bilateral_HorizontalBlur"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur(uv, vec2(_SourceSize.z / DOWNSAMPLE, 0.0)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Bilateral_VerticalBlur"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = Blur(uv, vec2(0.0, _SourceSize.w / DOWNSAMPLE)); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Bilateral_FinalBlur"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(FinalBlur()); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Bilateral_FinalBlur_AfterOpaque"
            Blend One SrcAlpha, Zero One
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0, 0.0, 0.0, FinalBlur()); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Gaussian_HorizontalBlur"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(GaussianBlur(uv, vec2(_SourceSize.z / DOWNSAMPLE, 0.0))); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Gaussian_VerticalBlur"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(1.0 - GaussianBlur(uv, vec2(0.0, _SourceSize.w / DOWNSAMPLE))); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Gaussian_VerticalBlur_AfterOpaque"
            Blend One SrcAlpha, Zero One
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0, 0.0, 0.0, 1.0 - GaussianBlur(uv, vec2(0.0, _SourceSize.w / DOWNSAMPLE))); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Kawase"
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(KawaseBlur()); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "SSAO_Kawase_AfterOpaque"
            Blend One SrcAlpha, Zero One
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0, 0.0, 0.0, KawaseBlur()); }
            #endif
            ENDGLSL
        }
    }
}
