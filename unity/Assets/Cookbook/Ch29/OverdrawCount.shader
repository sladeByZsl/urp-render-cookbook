// 案例 29.5：Overdraw 计数。作为 overrideMaterial 替换场景里所有物体的材质，
// 每画一层片元就往 R 通道加 1（加法混合），最后得到“每个像素被着色了几次”。
Shader "Cookbook/Ch29/OverdrawCount"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest ("ZTest", Float) = 8   // 8 = Always：统计所有光栅化出的片元
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "Count"
            //#region state
            Blend One One          // 累加
            ZWrite Off
            ZTest [_ZTest]
            Cull [_Cull]
            //#endregion
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return o;
            }
            half4 frag(Varyings i) : SV_Target { return half4(1, 0, 0, 0); }
            ENDHLSL
        }
    }
}
