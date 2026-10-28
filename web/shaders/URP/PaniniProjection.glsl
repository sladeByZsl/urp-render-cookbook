// URP 14 PaniniProjection.shader 的 GLSL 版：把超广角的直线透视重新投影到圆柱面上，减轻边缘拉伸。
Shader "Hidden/Universal Render Pipeline/PaniniProjection"
{
    SubShader
    {
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "Panini Projection"
            GLSLPROGRAM
            uniform vec4 _Params;   // (视野范围 x, 视野范围 y, 距离 d, 缩放)
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                uv = p;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            vec2 Panini_UnitDistance(vec2 view_pos)
            {
                const float d = 1.0;
                const float view_dist = 2.0;
                const float view_dist_sq = 4.0;
                float view_hyp = sqrt(view_pos.x * view_pos.x + view_dist_sq);
                float cyl_hyp = view_hyp - (view_pos.x * view_pos.x) / view_hyp;
                float cyl_hyp_frac = cyl_hyp / view_hyp;
                float cyl_dist = view_dist * cyl_hyp_frac;
                vec2 cyl_pos = view_pos * cyl_hyp_frac;
                return cyl_pos / (cyl_dist - d);
            }

            vec2 Panini_Generic(vec2 view_pos, float d)
            {
                float view_dist = 1.0 + d;
                float view_hyp_sq = view_pos.x * view_pos.x + view_dist * view_dist;
                float isect_D = view_pos.x * d;
                float isect_discrim = view_hyp_sq - isect_D * isect_D;
                float cyl_dist_minus_d = (-isect_D * view_pos.x + view_dist * sqrt(isect_discrim)) / view_hyp_sq;
                float cyl_dist = cyl_dist_minus_d + d;
                vec2 cyl_pos = view_pos * (cyl_dist / view_dist);
                return cyl_pos / (cyl_dist - d);
            }

            #ifdef FRAGMENT
            void main()
            {
                vec2 view_pos = (2.0 * uv - 1.0) * _Params.xy * _Params.w;
                // URP 用关键字 _GENERIC / _UNIT_DISTANCE 选择，这里按 d 是否为 1 分支
                vec2 proj_pos = 1.0 - abs(_Params.z) > 1.192092896e-07 ? Panini_Generic(view_pos, _Params.z) : Panini_UnitDistance(view_pos);
                vec2 proj_ndc = proj_pos / _Params.xy;
                vec2 coords = proj_ndc * 0.5 + 0.5;
                fragColor = texture(_BlitTexture, coords);
            }
            #endif
            ENDGLSL
        }
    }
}
