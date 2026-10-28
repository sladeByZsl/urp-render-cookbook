// 案例 18.6~18.7：能量护盾。深度交接高亮 + 六边形网格 + 菲涅尔 + 受击涟漪。
// 透明队列读取 _CameraDepthTexture（URP Asset 需开启 Depth Texture）。（GLSL 版，对应 Ch18/Shield.shader）
Shader "Cookbook/Ch18/Shield"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Shield"
            Tags { "LightMode"="UniversalForward" }
            Blend One One
            ZWrite Off
            Cull Off            // 双面：从外面也能看到球的内壁，更有“罩子”的体积感

            GLSLPROGRAM
            #include "Ch18/Ch18Common.glsl"
            // _CameraDepthTexture / SampleSceneDepth 在 Core.glsl 里（对应 DeclareDepthTexture.hlsl）

            uniform vec4  _ShieldColor;
            uniform float _BaseAlpha;
            uniform float _RimPower;
            uniform float _IntersectWidth;
            uniform float _IntersectStrength;
            uniform float _HexScale;
            uniform float _HexLine;
            uniform float _HexStrength;
            uniform vec4  _HitPos;
            uniform float _HitProgress;
            uniform float _HitRadius;
            uniform float _HitStrength;
            uniform float _HitDisplace;
            uniform float _AutoPlay;
            uniform float _Phase;

            VARYING vec3  positionWS;
            VARYING vec3  normalWS;
            VARYING vec2  uv;
            VARYING float eyeDepth;   // 本片元到相机的观察空间深度（米）
            VARYING float poleFade;

            float ShieldTime() { return _AutoPlay > 0.5 ? _Time.y : _Phase; }

            //#region hit
            // 受击涟漪：以命中点为圆心向外扩散的一圈环，越往外越淡
            float HitRing(vec3 pWS)
            {
                float d = distance(pWS, _HitPos.xyz);
                float r = _HitProgress * _HitRadius;
                float width = 0.12 + 0.25 * _HitProgress;
                float ring = saturate(1.0 - abs(d - r) / width);
                float fade = (1.0 - _HitProgress) * step(0.001, _HitProgress);
                // 命中点本身还有一个快速消退的亮斑
                float spot = saturate(1.0 - d / (0.4 + r * 0.3)) * (1.0 - _HitProgress) * (1.0 - _HitProgress);
                return (ring * ring + spot) * fade;
            }
            //#endregion

            #ifdef VERTEX
            void main()
            {
                vec3 pWS = TransformObjectToWorld(positionOS.xyz);
                vec3 nWS = TransformObjectToWorldNormal(normalOS);
                // 涟漪经过的地方顶点沿法线鼓起一点点
                pWS += nWS * HitRing(pWS) * _HitDisplace;
                positionWS = pWS;
                gl_Position = TransformWorldToHClip(pWS);
                normalWS = nWS;
                uv = texcoord0.xy;
                eyeDepth = -TransformWorldToView(pWS).z;   // 观察空间看向 -Z，取负得正的深度
                poleFade = 1.0 - pow(abs(normalOS.y), 6.0); // 球面 UV 在两极挤成一点，六边形淡出
            }
            #endif

            #ifdef FRAGMENT
            //#region hex
            // 六边形网格：返回到最近六边形中心的局部坐标(xy)与格子 id(zw)
            vec4 HexGrid(vec2 p)
            {
                const vec2 s = vec2(1.0, 1.7320508);           // (1, √3)
                vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
                vec4 h = vec4(p - c.xy * s, p - (c.zw + 0.5) * s);
                return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy) : vec4(h.zw, c.zw + 0.5);
            }

            // 六边形的“距离”：中心为 0，边上为 0.5
            float HexDist(vec2 p)
            {
                p = abs(p);
                return max(dot(p, vec2(0.5, 0.8660254)), p.x);
            }
            //#endregion

            //#region frag
            void main()
            {
                float t = ShieldTime();
                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);

                // 1) 深度交接：场景深度 - 自身深度 越小，说明越贴近别的物体表面
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                float sceneEye = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
                float gap = sceneEye - eyeDepth;
                float intersect = 1.0 - saturate(gap / max(_IntersectWidth, 1e-4));
                intersect = intersect * intersect * _IntersectStrength;

                // 2) 菲涅尔轮廓（背面也算，球的内壁边缘同样会亮）
                float rim = FresnelRim(N, viewWS, _RimPower);

                // 3) 六边形：球面 U 绕一圈（2πR），V 从南极到北极（πR），
                //    所以 V 方向只铺 U 的一半，格子才不被拉伸；_HexScale 取整数，U 的接缝处就能无缝衔接
                vec2 hp = uv * vec2(_HexScale, _HexScale * 0.5);
                vec4 hex = HexGrid(hp);
                float edge = smoothstep(0.5 - _HexLine, 0.5, HexDist(hex.xy));
                // 每个格子一个随机相位，缓慢呼吸明暗
                float cellPulse = 0.5 + 0.5 * sin(t * 2.0 + Hash21(hex.zw) * 6.2831);
                float hexMask = (edge + cellPulse * 0.15) * _HexStrength * poleFade;

                // 4) 受击：环经过的地方六边形整体点亮
                float hit = HitRing(positionWS);
                float hitHex = hit * (0.35 + edge) * _HitStrength;

                float back = gl_FrontFacing ? 1.0 : 0.45;    // 内壁暗一些，前后有层次
                float intensity = (_BaseAlpha + rim + hexMask * (0.3 + rim)) * back + intersect + hitHex;
                fragColor = vec4(_ShieldColor.rgb * intensity, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
