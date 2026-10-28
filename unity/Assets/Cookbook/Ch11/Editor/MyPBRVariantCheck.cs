// 菜单：Cookbook/Ch11/Check MyPBR Variants —— 用几组典型关键字组合强制编译 MyPBR 的每个 Pass，
// 提前发现“默认变体能编过、某个开关一开就报错”的问题（光照贴图、调试视图、逐顶点光等）。
using System.Linq;
using UnityEditor;
using UnityEditor.Rendering;
using UnityEngine;

namespace Cookbook.Ch11
{
    public static class MyPBRVariantCheck
    {
        static readonly string[][] Sets =
        {
            new[] { "_NORMALMAP", "_MASKMAP", "_EMISSION", "_DFG_LUT", "_ALPHATEST_ON" },
            new[] { "LIGHTMAP_ON", "DIRLIGHTMAP_COMBINED", "SHADOWS_SHADOWMASK", "LIGHTMAP_SHADOW_MIXING", "_MAIN_LIGHT_SHADOWS_CASCADE" },
            new[] { "_ADDITIONAL_LIGHTS_VERTEX", "EVALUATE_SH_VERTEX", "_MAIN_LIGHT_SHADOWS_SCREEN", "_NORMALMAP" },
            new[] { "DEBUG_DISPLAY", "_ADDITIONAL_LIGHTS", "_FORWARD_PLUS", "_REFLECTION_PROBE_BLENDING", "_REFLECTION_PROBE_BOX_PROJECTION" },
            new[] { "_ADDITIONAL_LIGHTS", "_ADDITIONAL_LIGHT_SHADOWS", "_SHADOWS_SOFT_HIGH", "_LIGHT_LAYERS", "_LIGHT_COOKIES", "_SCREEN_SPACE_OCCLUSION", "EVALUATE_SH_MIXED" },
            new[] { "_WRITE_RENDERING_LAYERS", "_CASTING_PUNCTUAL_LIGHT_SHADOW", "EDITOR_VISUALIZATION", "_MASKMAP", "_EMISSION" },
        };

        [MenuItem("Cookbook/Ch11/Check MyPBR Variants")]
        public static int Check()
        {
            var sh = Shader.Find("Cookbook/Ch11/MyPBR");
            int errors = 0;
            foreach (var set in Sets)
            {
                var m = new Material(sh);
                foreach (var k in set) m.EnableKeyword(k);
                for (int p = 0; p < m.passCount; p++) ShaderUtil.CompilePass(m, p, true);
                Object.DestroyImmediate(m);
            }
            foreach (var msg in ShaderUtil.GetShaderMessages(sh).Where(x => x.severity == ShaderCompilerMessageSeverity.Error))
            {
                Debug.LogError($"[MyPBR variant] {msg.message} {msg.messageDetails} line {msg.line}");
                errors++;
            }
            Debug.Log($"[MyPBR variant] checked {Sets.Length} keyword sets, errors = {errors}");
            return errors;
        }
    }
}
