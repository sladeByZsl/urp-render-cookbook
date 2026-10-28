// 把重心坐标烘焙进顶点色：拆开共享顶点（每个三角形独占 3 个顶点），
// 三个角分别写 (1,0,0)、(0,1,0)、(0,0,1)。可选地隐藏“四边形对角线”。
// 菜单：Tools › Cookbook › Ch15 › Bake Barycentric Mesh（对选中的网格资源/物体生效）
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch15
{
    public static class BarycentricBaker
    {
        //#region bake
        public static Mesh Bake(Mesh src, bool hideQuadDiagonals)
        {
            var srcV = src.vertices; var srcN = src.normals; var srcUV = src.uv;
            var tris = src.triangles;
            int triCount = tris.Length / 3;

            // 每个三角形里“最长边”的对面顶点（0/1/2）；对四边形拆出的三角形，最长边就是对角线
            var longestOpp = new int[triCount];
            var diagonalOf = new Dictionary<(Vector3, Vector3), List<int>>();
            for (int t = 0; t < triCount; t++)
            {
                float best = -1; int opp = 0;
                for (int k = 0; k < 3; k++)
                {
                    Vector3 a = srcV[tris[t * 3 + (k + 1) % 3]], b = srcV[tris[t * 3 + (k + 2) % 3]];
                    float len = (a - b).sqrMagnitude;
                    if (len > best) { best = len; opp = k; }
                }
                longestOpp[t] = opp;
                var key = EdgeKey(srcV[tris[t * 3 + (opp + 1) % 3]], srcV[tris[t * 3 + (opp + 2) % 3]]);
                if (!diagonalOf.TryGetValue(key, out var list)) diagonalOf[key] = list = new List<int>();
                list.Add(t);
            }

            var v = new Vector3[tris.Length]; var n = new Vector3[tris.Length];
            var uv = new Vector2[tris.Length]; var col = new Color[tris.Length];
            var idx = new int[tris.Length];
            for (int t = 0; t < triCount; t++)
            {
                // 两个相邻三角形的最长边是同一条边 → 它俩拼成一个四边形，这条边是对角线
                int opp = longestOpp[t];
                var key = EdgeKey(srcV[tris[t * 3 + (opp + 1) % 3]], srcV[tris[t * 3 + (opp + 2) % 3]]);
                bool hide = hideQuadDiagonals && diagonalOf[key].Count == 2;

                for (int k = 0; k < 3; k++)
                {
                    int i = t * 3 + k, s = tris[i];
                    v[i] = srcV[s];
                    n[i] = srcN.Length > 0 ? srcN[s] : Vector3.up;
                    uv[i] = srcUV.Length > 0 ? srcUV[s] : Vector2.zero;
                    var c = new Color(k == 0 ? 1 : 0, k == 1 ? 1 : 0, k == 2 ? 1 : 0, 1);
                    // 对角线上“对面顶点那一维”恒为 0；把这一维在三个顶点上都设成 1，它就永远不会接近 0
                    if (hide) c[opp] = 1;
                    col[i] = c;
                    idx[i] = i;
                }
            }
            var m = new Mesh { name = src.name + "_Bary", indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.normals = n; m.uv = uv; m.colors = col; m.triangles = idx;
            m.RecalculateBounds();
            return m;
        }

        // 无向边的键：用量化后的位置，避免硬边处“同位置不同顶点”导致找不到邻居
        static (Vector3, Vector3) EdgeKey(Vector3 a, Vector3 b)
        {
            a = Quant(a); b = Quant(b);
            return (a.x < b.x || (a.x == b.x && (a.y < b.y || (a.y == b.y && a.z < b.z)))) ? (a, b) : (b, a);
        }
        static Vector3 Quant(Vector3 p) => new Vector3(Mathf.Round(p.x * 1e4f), Mathf.Round(p.y * 1e4f), Mathf.Round(p.z * 1e4f));
        //#endregion

        [MenuItem("Tools/Cookbook/Ch15/Bake Barycentric Mesh")]
        static void BakeSelected()
        {
            var mesh = Selection.activeObject as Mesh;
            if (mesh == null && Selection.activeGameObject != null)
                mesh = Selection.activeGameObject.GetComponent<MeshFilter>()?.sharedMesh;
            if (mesh == null) { Debug.LogWarning("请先选中一个 Mesh 资源或带 MeshFilter 的物体"); return; }
            var baked = Bake(mesh, true);
            string path = EditorUtility.SaveFilePanelInProject("保存烘焙后的网格", baked.name, "asset", "");
            if (!string.IsNullOrEmpty(path)) AssetDatabase.CreateAsset(baked, path);
        }

        /// 二十面体细分球（配图用：三角形大小均匀，线框好看）
        public static Mesh Icosphere(int subdiv, float radius = 0.5f)
        {
            float t = (1f + Mathf.Sqrt(5f)) / 2f;
            var verts = new List<Vector3> {
                new(-1, t, 0), new(1, t, 0), new(-1, -t, 0), new(1, -t, 0),
                new(0, -1, t), new(0, 1, t), new(0, -1, -t), new(0, 1, -t),
                new(t, 0, -1), new(t, 0, 1), new(-t, 0, -1), new(-t, 0, 1) };
            for (int i = 0; i < verts.Count; i++) verts[i] = verts[i].normalized;
            var faces = new List<int> {
                0,11,5, 0,5,1, 0,1,7, 0,7,10, 0,10,11, 1,5,9, 5,11,4, 11,10,2, 10,7,6, 7,1,8,
                3,9,4, 3,4,2, 3,2,6, 3,6,8, 3,8,9, 4,9,5, 2,4,11, 6,2,10, 8,6,7, 9,8,1 };
            var cache = new Dictionary<long, int>();
            int Mid(int a, int b)
            {
                long key = a < b ? ((long)a << 32) | (uint)b : ((long)b << 32) | (uint)a;
                if (cache.TryGetValue(key, out int r)) return r;
                verts.Add(((verts[a] + verts[b]) * 0.5f).normalized);
                return cache[key] = verts.Count - 1;
            }
            for (int s = 0; s < subdiv; s++)
            {
                var nf = new List<int>();
                for (int i = 0; i < faces.Count; i += 3)
                {
                    int a = faces[i], b = faces[i + 1], c = faces[i + 2];
                    int ab = Mid(a, b), bc = Mid(b, c), ca = Mid(c, a);
                    nf.AddRange(new[] { a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca });
                }
                faces = nf;
            }
            var m = new Mesh { name = "Icosphere" };
            var pv = new Vector3[verts.Count];
            for (int i = 0; i < pv.Length; i++) pv[i] = verts[i] * radius;
            m.vertices = pv; m.normals = verts.ToArray(); m.triangles = faces.ToArray();
            m.RecalculateBounds();
            return m;
        }
    }
}
