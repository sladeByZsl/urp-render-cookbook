// 案例 25.5：DrawRenderers 的 Override Material——把物体画成纯白剪影，写进遮罩 RT。
Shader "Cookbook/Ch25/LayerMaskSolid"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "Mask"
            ZWrite Off      // 绝不改动相机深度；深度比较方式由 C# 的 RenderStateBlock 决定
            Cull Back

            GLSLPROGRAM
            #ifdef VERTEX
            void main()
            {
                // 对应 HLSL 的 TransformObjectToHClip。这里拆成“物体→世界→裁剪”两步，和 Lit 的顶点着色器
                // （GetVertexPositionInputs）运算顺序一致，保证算出的深度逐位相同，LEqual 测试不会闪烁
                gl_Position = TransformWorldToHClip(TransformObjectToWorld(positionOS.xyz));
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(1.0); }
            #endif
            ENDGLSL
        }
    }
}
