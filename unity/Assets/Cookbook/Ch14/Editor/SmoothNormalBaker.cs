// 平滑法线烘焙工具：把“同一位置上所有顶点的法线平均值”写进切线或顶点色，供描边外扩使用。
// 用法：Project 窗口选中模型（或 Mesh），菜单 Cookbook › Ch14 › Bake Smooth Normals (...)，
// 会在原文件旁边生成一份 xxx_SmoothNormals.asset，原网格不受影响。
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

namespace Cookbook.Ch14
{
    public static class SmoothNormalBaker
    {
        public enum Target
        {
            Tangent,        // 物体空间平滑法线 → tangent.xyz（简单，但会占掉切线，法线贴图就不能用了）
            VertexColor,    // 切线空间平滑法线 → color.rgb（不占切线，蒙皮/形变后依然正确）
        }

        //#region bake
        public static void Bake(Mesh mesh, Target target)
        {
            var verts = mesh.vertices;
            var tris = mesh.triangles;
            var normals = mesh.normals;
            var tangents = mesh.tangents;
            if (tangents == null || tangents.Length != verts.Length)
            {
                mesh.RecalculateTangents();
                tangents = mesh.tangents;
            }

            // 1) 按位置分组：硬边处同一个位置有好几个顶点（各自带不同法线）
            var groups = new Dictionary<Vector3Int, Vector3>();
            Vector3Int Key(Vector3 p) => new Vector3Int(Mathf.RoundToInt(p.x * 1e4f), Mathf.RoundToInt(p.y * 1e4f), Mathf.RoundToInt(p.z * 1e4f));

            // 2) 累加每个三角形的面法线，用“顶点处的夹角”加权（比按面积加权更不受三角剖分影响）
            for (int t = 0; t < tris.Length; t += 3)
            {
                Vector3 p0 = verts[tris[t]], p1 = verts[tris[t + 1]], p2 = verts[tris[t + 2]];
                Vector3 fn = Vector3.Cross(p1 - p0, p2 - p0).normalized;
                for (int k = 0; k < 3; k++)
                {
                    Vector3 a = verts[tris[t + k]], b = verts[tris[t + (k + 1) % 3]], c = verts[tris[t + (k + 2) % 3]];
                    float angle = Vector3.Angle(b - a, c - a) * Mathf.Deg2Rad;
                    var key = Key(a);
                    groups.TryGetValue(key, out var sum);
                    groups[key] = sum + fn * angle;
                }
            }

            // 3) 写回
            var outTangents = new Vector4[verts.Length];
            var outColors = new Color[verts.Length];
            var oldColors = mesh.colors;
            for (int i = 0; i < verts.Length; i++)
            {
                Vector3 smooth = groups[Key(verts[i])].normalized;
                if (target == Target.Tangent)
                {
                    outTangents[i] = new Vector4(smooth.x, smooth.y, smooth.z, 1);
                }
                else
                {
                    // 物体空间 → 该顶点自己的切线空间（T, B, N）
                    Vector3 n = normals[i];
                    Vector3 tg = tangents[i];
                    Vector3 bt = Vector3.Cross(n, tg) * tangents[i].w;
                    var ts = new Vector3(Vector3.Dot(smooth, tg), Vector3.Dot(smooth, bt), Vector3.Dot(smooth, n));
                    float alpha = oldColors != null && oldColors.Length == verts.Length ? oldColors[i].a : 1f;  // A 通道留给线宽遮罩
                    outColors[i] = new Color(ts.x * 0.5f + 0.5f, ts.y * 0.5f + 0.5f, ts.z * 0.5f + 0.5f, alpha);
                }
            }
            if (target == Target.Tangent) mesh.tangents = outTangents;
            else mesh.colors = outColors;
        }
        //#endregion

        //#region menu
        [MenuItem("Cookbook/Ch14/Bake Smooth Normals (Tangent)")]
        static void BakeToTangent() => BakeSelection(Target.Tangent);

        [MenuItem("Cookbook/Ch14/Bake Smooth Normals (Vertex Color)")]
        static void BakeToColor() => BakeSelection(Target.VertexColor);

        static void BakeSelection(Target target)
        {
            foreach (var obj in Selection.objects)
            {
                string path = AssetDatabase.GetAssetPath(obj);
                var meshes = new List<Mesh>();
                if (obj is Mesh m) meshes.Add(m);
                else foreach (var a in AssetDatabase.LoadAllAssetsAtPath(path)) if (a is Mesh mm) meshes.Add(mm);

                foreach (var src in meshes)
                {
                    var copy = Object.Instantiate(src);   // 不改原始模型，另存一份
                    copy.name = src.name + "_SmoothNormals";
                    Bake(copy, target);
                    string dir = System.IO.Path.GetDirectoryName(path);
                    string outPath = AssetDatabase.GenerateUniqueAssetPath($"{dir}/{copy.name}.asset");
                    AssetDatabase.CreateAsset(copy, outPath);
                    Debug.Log($"[Ch14] 平滑法线已烘焙到 {target}：{outPath}");
                }
            }
            AssetDatabase.SaveAssets();
        }

        [MenuItem("Cookbook/Ch14/Bake Smooth Normals (Tangent)", true)]
        [MenuItem("Cookbook/Ch14/Bake Smooth Normals (Vertex Color)", true)]
        static bool Validate() => Selection.objects.Length > 0;
        //#endregion
    }
}
