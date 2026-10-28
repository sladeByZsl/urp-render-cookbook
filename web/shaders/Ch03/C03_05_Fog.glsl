// 第 5 步：接入 Lighting 窗口里的雾（Linear / Exponential / Exponential Squared）。
Shader "Cookbook/Ch03/Fog"
{
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            GLSLPROGRAM
            //#region pragma
            // 生成 无雾 / FOG_LINEAR / FOG_EXP / FOG_EXP2 四个变体，引擎按 Lighting 设置选用
            // （网页版：雾模式由 uniform unity_FogMode 在运行时选择，不需要变体，这一行留着只为和 HLSL 对照）
            #pragma multi_compile_fog
            //#endregion

            //#region varyings
            VARYING vec2 uv;
            VARYING vec4 vColor;
            VARYING float fogFactor;  // 每个顶点算一次雾因子，交给插值器
            //#endregion

            uniform sampler2D _BaseMap;
            uniform vec4  _BaseMap_ST;
            uniform vec4  _BaseColor;
            uniform float _Cutoff;

            //#region vertfrag
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                vColor = color;
                // 用裁剪空间 z 换算出“离相机多远”，再按雾模式算出因子
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec4 col = texture(_BaseMap, uv) * _BaseColor * vColor;
                if (col.a - _Cutoff < 0.0) discard;
                // 按因子把颜色往 unity_FogColor 方向混；没开雾时这一行什么都不做
                col.rgb = MixFog(col.rgb, fogFactor);
                fragColor = vec4(col.rgb, 1);
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
