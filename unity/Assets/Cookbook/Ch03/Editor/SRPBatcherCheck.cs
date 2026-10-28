// 小工具：批量检查 Shader 是否兼容 SRP Batcher（与 Shader Inspector 里那一行提示同源）。
// 用法：在 Project 窗口选中若干 Shader（或一个文件夹），菜单 Cookbook › Ch03 › Check SRP Batcher Compatibility。
using System.Linq;
using System.Reflection;
using UnityEditor;
using UnityEngine;

namespace Cookbook.Ch03
{
    public static class SRPBatcherCheck
    {
        //#region check
        // Unity 没有公开这两个函数，Shader Inspector 内部就是调用它们显示 “SRP Batcher: compatible / not compatible”
        static readonly MethodInfo s_GetCode = typeof(ShaderUtil).GetMethod("GetSRPBatcherCompatibilityCode",
            BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public);
        static readonly MethodInfo s_GetReason = typeof(ShaderUtil).GetMethod("GetSRPBatcherCompatibilityIssueReason",
            BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public);

        /// 返回 null 表示兼容，否则返回不兼容的原因
        public static string Check(Shader shader, int subShader = 0)
        {
            if (s_GetCode == null || s_GetReason == null) return "(当前 Unity 版本找不到内部 API)";
            int code = (int)s_GetCode.Invoke(null, new object[] { shader, subShader });
            if (code == 0) return null;
            return (string)s_GetReason.Invoke(null, new object[] { shader, subShader, code });
        }
        //#endregion

        [MenuItem("Cookbook/Ch03/Check SRP Batcher Compatibility")]
        static void CheckSelection()
        {
            var shaders = Selection.GetFiltered<Shader>(SelectionMode.DeepAssets);
            if (shaders.Length == 0) { Debug.Log("[SRP Batcher] 请先在 Project 窗口选中 Shader 或文件夹"); return; }
            foreach (var s in shaders.OrderBy(s => s.name)) Log(s);
        }

        public static void Log(Shader s)
        {
            var reason = Check(s);
            Debug.Log(reason == null ? $"[SRP Batcher] {s.name}: compatible" : $"[SRP Batcher] {s.name}: NOT compatible — {reason}");
        }

        /// 检查本章全部 Shader，给出书中表格用的结果
        public static void LogChapter()
        {
            foreach (var guid in AssetDatabase.FindAssets("t:Shader", new[] { "Assets/Cookbook/Ch03" }))
            {
                var s = AssetDatabase.LoadAssetAtPath<Shader>(AssetDatabase.GUIDToAssetPath(guid));
                if (s != null) Log(s);
            }
        }
    }
}
