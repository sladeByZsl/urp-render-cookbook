// 案例 29.3：自定义 Shader 变体剥离（IPreprocessShaders）。
// 打包时 Unity 对每个 Shader 的每个 Pass/阶段调用一次 OnProcessShader，data 里是即将编译的变体列表，
// 从列表里删掉的变体就不会被编译、也不会进包。
// 规则要根据项目实际情况写：剥掉“确定用不到”的，宁可少剥也不要错剥（错剥的变体运行时会退回到别的变体，表现出错）。
using System.Collections.Generic;
using System.Text;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.Rendering;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch29
{
    //#region rules
    class CookbookVariantStripper : IPreprocessShaders, IPreprocessBuildWithReport, IPostprocessBuildWithReport
    {
        // ---- 项目约定（示例）：根据你的项目改 ----
        const bool k_ProjectUsesLightmaps = false;          // 全实时光照，没有烘焙光照贴图
        const bool k_ProjectUsesScreenSpaceShadows = false; // 没有加 Screen Space Shadows Feature
        const bool k_ProjectUsesVertexAdditionalLights = false; // 附加光一律逐像素
        const string k_OnlyShadersWithPrefix = "";          // 只处理某些 Shader（空 = 全部）

        static readonly ShaderKeyword s_LightmapOn = new ShaderKeyword("LIGHTMAP_ON");
        static readonly ShaderKeyword s_DynLightmapOn = new ShaderKeyword("DYNAMICLIGHTMAP_ON");
        static readonly ShaderKeyword s_DirLightmap = new ShaderKeyword("DIRLIGHTMAP_COMBINED");
        static readonly ShaderKeyword s_ShadowsShadowmask = new ShaderKeyword("SHADOWS_SHADOWMASK");
        static readonly ShaderKeyword s_LightmapShadowMixing = new ShaderKeyword("LIGHTMAP_SHADOW_MIXING");
        static readonly ShaderKeyword s_ScreenShadows = new ShaderKeyword("_MAIN_LIGHT_SHADOWS_SCREEN");
        static readonly ShaderKeyword s_VertexLights = new ShaderKeyword("_ADDITIONAL_LIGHTS_VERTEX");
        static readonly ShaderKeyword s_DebugDisplay = new ShaderKeyword("DEBUG_DISPLAY");

        static int s_Before, s_After;
        static readonly Dictionary<string, int> s_RemovedPerShader = new Dictionary<string, int>();

        // 数字越小越早执行。URP 自己的剥离器也实现了这个接口，顺序不影响结果（都是从同一个列表里删）
        public int callbackOrder => 10;

        bool ShouldStrip(ShaderSnippetData snippet, ShaderCompilerData data)
        {
            var keys = data.shaderKeywordSet;
            if (!k_ProjectUsesLightmaps &&
                (keys.IsEnabled(s_LightmapOn) || keys.IsEnabled(s_DynLightmapOn) || keys.IsEnabled(s_DirLightmap) ||
                 keys.IsEnabled(s_ShadowsShadowmask) || keys.IsEnabled(s_LightmapShadowMixing)))
                return true;
            if (!k_ProjectUsesScreenSpaceShadows && keys.IsEnabled(s_ScreenShadows)) return true;
            if (!k_ProjectUsesVertexAdditionalLights && keys.IsEnabled(s_VertexLights)) return true;
            // 发布版不需要 Rendering Debugger 的调试变体
            if (!EditorUserBuildSettings.development && keys.IsEnabled(s_DebugDisplay)) return true;
            // Meta Pass 给光照烘焙/实时 GI 提取反照率和自发光用；项目完全不用 GI 时才剥
            if (!k_ProjectUsesLightmaps && snippet.passType == PassType.Meta) return true;
            return false;
        }
        //#endregion

        //#region process
        public void OnProcessShader(Shader shader, ShaderSnippetData snippet, IList<ShaderCompilerData> data)
        {
            if (k_OnlyShadersWithPrefix.Length > 0 && !shader.name.StartsWith(k_OnlyShadersWithPrefix)) return;
            int before = data.Count;
            // 倒序删除，避免下标错位
            for (int i = data.Count - 1; i >= 0; --i)
                if (ShouldStrip(snippet, data[i]))
                    data.RemoveAt(i);
            s_Before += before;
            s_After += data.Count;
            int removed = before - data.Count;
            if (removed > 0)
            {
                s_RemovedPerShader.TryGetValue(shader.name, out int n);
                s_RemovedPerShader[shader.name] = n + removed;
            }
        }
        //#endregion

        public void OnPreprocessBuild(BuildReport report)
        {
            s_Before = s_After = 0;
            s_RemovedPerShader.Clear();
        }

        public void OnPostprocessBuild(BuildReport report)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"[CookbookVariantStripper] 变体（按 Pass×阶段计）：{s_Before} → {s_After}");
            foreach (var kv in s_RemovedPerShader)
                sb.AppendLine($"  {kv.Key}: -{kv.Value}");
            Debug.Log(sb.ToString());
        }
    }
}
