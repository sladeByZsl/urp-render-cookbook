// 案例 20.7–20.9：GPU Instancing 草——每实例颜色变化、交互压弯、距离淡出（GLSL 版，对应 Ch20/Grass.shader）
// WebGL2 版的实例化：GrassRenderer.js 用 drawElementsInstanced 一次画完所有草丛，
// 每实例的矩阵和 _Variation 打包进一张浮点贴图 _GrassInstanceData，顶点着色器按 gl_InstanceID 取出来。
Shader "Cookbook/Ch20/Grass"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Cull Off    // 草叶是单层面片，两面都要画

        GLSLINCLUDE
        uniform vec4 _RootColor, _TipColor, _DryColor;
        uniform float _DryAmount, _Translucency, _NormalUp;
        uniform vec4 _WindDir;
        uniform float _WindStrength, _WindSpeed, _WindPhase;
        uniform float _BendStrength, _PressDown;
        uniform float _FadeStart, _FadeEnd;

        //#region instanceProps
        // 每实例属性：C# 用 MaterialPropertyBlock.SetFloatArray("_Variation", ...) 按批传入 UNITY_INSTANCING_BUFFER；
        // WebGL 没有这套宏，每实例占贴图里连续 4 个像素：矩阵的前三行 + (_Variation, 0, 0, 0)
        uniform highp sampler2D _GrassInstanceData;
        #define GRASS_DATA_WIDTH 1024
        //#endregion

        //#region globals
        // 交互体：全局数组，xyz = 世界坐标，w = 影响半径。不放进材质参数，由 GrassRenderer.js 按全局变量设置（同 Shader.SetGlobal*）
        uniform vec4  _Ch20Interactors[8];
        uniform float _Ch20InteractorCount;
        //#endregion

        #ifdef VERTEX
        // 对应 UNITY_SETUP_INSTANCE_ID：取出这一实例的 unity_ObjectToWorld 和 _Variation
        mat4 instanceObjectToWorld;
        float instanceVariation;
        vec4 FetchInstanceTexel(int i) { return texelFetch(_GrassInstanceData, ivec2(i % GRASS_DATA_WIDTH, i / GRASS_DATA_WIDTH), 0); }
        void SetupGrassInstance()
        {
            int base = gl_InstanceID * 4;
            // 贴图里存的是矩阵的行，GLSL 的 mat4 按列构造，所以转置一下
            instanceObjectToWorld = transpose(mat4(FetchInstanceTexel(base), FetchInstanceTexel(base + 1), FetchInstanceTexel(base + 2), vec4(0, 0, 0, 1)));
            instanceVariation = FetchInstanceTexel(base + 3).x;
        }
        // 实例版的 TransformObjectToWorld / TransformObjectToWorldNormal（草丛只有旋转 + 等比缩放，法线直接用 3×3 部分）
        vec3 GrassObjectToWorld(vec3 p) { return (instanceObjectToWorld * vec4(p, 1.0)).xyz; }
        vec3 GrassObjectToWorldNormal(vec3 n) { return normalize(mat3(instanceObjectToWorld) * n); }

        //#region deform
        // 返回变形后的世界坐标；fade 为距离淡出系数（1 = 完全可见）
        // 顶点输入（GrassAttributes）：positionOS、normalOS、color、texcoord0
        vec3 GrassDeform(out float fade)
        {
            vec3 pivotWS = GrassObjectToWorld(vec3(0, 0, 0));     // 这一丛草的根部中心
            // 1) 距离淡出：先把整丛草“压矮”，再配合片元里的抖动裁剪
            float camDist = distance(pivotWS, GetCameraPositionWS());
            fade = saturate((_FadeEnd - camDist) / max(_FadeEnd - _FadeStart, 1e-3));
            vec3 posOS = positionOS.xyz;
            posOS.y *= mix(0.3, 1.0, fade);
            vec3 posWS = GrassObjectToWorld(posOS);

            float h = texcoord0.y;       // 0 根部 → 1 叶尖
            float bendW = h * h;         // 根部钉死、越往上越软（平方让弯曲更像弧线）

            // 2) 风：简化的行波（完整的风场做法见第 17 章）。_WindPhase 供静帧拍摄用
            float phase = _WindPhase + _Time.y * _WindSpeed;
            float wave = sin(dot(pivotWS.xz, vec2(0.35, 0.22)) + phase) * 0.5 + 0.5;
            wave += sin(dot(pivotWS.xz, vec2(-1.3, 0.9)) + phase * 2.3) * 0.15;
            posWS.xz += normalize(_WindDir.xz) * (wave * _WindStrength * bendW);

            // 3) 交互：每个交互体把附近的草沿水平方向推开，并往下压
            vec2 push = vec2(0.0);
            float press = 0.0;
            int count = int(_Ch20InteractorCount);
            for (int k = 0; k < count; k++)
            {
                vec4 it = _Ch20Interactors[k];
                vec2 d = posWS.xz - it.xz;
                float dist = length(d);
                float f = saturate(1.0 - dist / it.w);
                f = f * f * (3.0 - 2.0 * f);                         // smoothstep 形状，边缘不突变
                f *= saturate(1.0 - (pivotWS.y - it.y) / it.w);      // 交互体离地太高就不影响
                push += d / max(dist, 1e-3) * f;
                press = max(press, f);
            }
            // 水平推开量不超过顶点离地高度；再按“到根部的距离不变”把顶点压低：y' = √(h² − |o|²)
            float hy = max(posWS.y - pivotWS.y, 0.0);
            vec2 o = push * (_BendStrength * bendW);
            float ol = length(o);
            float maxO = hy * 0.95;
            o *= min(1.0, maxO / max(ol, 1e-4));
            ol = min(ol, maxO);
            posWS.xz += o;
            posWS.y = pivotWS.y + sqrt(max(hy * hy - ol * ol, 0.0)) * (1.0 - press * _PressDown);
            return posWS;
        }
        //#endregion
        #endif
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Ch20/TerrainCommon.glsl"

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 data;       // x = 高度 uv.y, y = 颜色随机值, z = 距离淡出, w = 雾

            #ifdef VERTEX
            void main()
            {
                SetupGrassInstance();
                float fade;
                vec3 posWS = GrassDeform(fade);
                positionWS = posWS;
                gl_Position = TransformWorldToHClip(posWS);
                normalWS = GrassObjectToWorldNormal(normalOS);
                // 每实例随机值 + 每片叶子的随机值，组合出颜色变化
                float variation = instanceVariation;
                data = vec4(texcoord0.y, fract(variation + color.r * 0.5), fade, ComputeFogFactor(gl_Position.z));
            }
            #endif

            #ifdef FRAGMENT
            //#region dither
            // 4×4 Bayer 抖动阈值（0..1）：按屏幕像素位置给出不同阈值，用 clip 做“半透明”
            float Bayer4x4(vec2 pixel)
            {
                const float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
                uvec2 p = uvec2(pixel) % 4u;
                return (m[p.y * 4u + p.x] + 0.5) / 16.0;
            }
            //#endregion

            //#region frag
            vec4 frag()
            {
                // 距离淡出的后半段：抖动裁剪，避免草在某个距离“啪”地整片消失
                if (data.z - Bayer4x4(gl_FragCoord.xy) < 0.0) discard;

                float h = data.x;
                vec3 albedo = mix(_RootColor.rgb, _TipColor.rgb, h);
                albedo = mix(albedo, _DryColor.rgb * mix(0.6, 1.0, h), smoothstep(1.0 - _DryAmount, 1.0, data.y));
                albedo *= mix(0.85, 1.15, fract(data.y * 7.31));

                // 双面：背面翻转法线；再往“上”方向拉，让整片草地的明暗更柔和统一
                vec3 n = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                n = normalize(mix(n, vec3(0, 1, 0), _NormalUp));
                float occlusion = mix(0.35, 1.0, h);    // 根部互相遮挡，压暗
                vec4 color = Ch20ShadePBR(positionWS, n, gl_FragCoord, albedo, 0.0, 0.2, occlusion, data.w);

                // 逆光透射：视线与光线方向接近相反时，叶尖透出亮绿色
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS));
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                float back = pow(saturate(dot(V, -mainLight.direction)), 4.0);
                color.rgb += albedo * mainLight.color * (mainLight.shadowAttenuation * back * _Translucency * h);
                return color;
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // _LightDirection / _LightPosition 由引擎的 Lighting.glsl 声明

            #ifdef VERTEX
            // 阴影 Pass 必须做同样的顶点变形，否则影子不跟着草动
            void main()
            {
                SetupGrassInstance();
                float fade;
                vec3 posWS = GrassDeform(fade);
                vec3 normalWS = GrassObjectToWorldNormal(normalOS);
                vec3 lightDir = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - posWS) : _LightDirection;
                vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, lightDir));
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);   // UNITY_REVERSED_Z = 0
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #ifdef VERTEX
            void main()
            {
                SetupGrassInstance();
                float fade;
                gl_Position = TransformWorldToHClip(GrassDeform(fade));
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
