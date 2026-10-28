// 为碎裂效果预处理网格：拆开共享顶点（每个三角形独立成“碎片”），
// 把碎片的中心写进 uv1.xyz、随机数写进 uv1.w，面法线写进 uv2.xyz。
// Shader 只要知道“我属于哪块碎片、碎片中心在哪”，就能让三个顶点一起平移、旋转。
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch17
{
    public static class ShatterMesh
    {
        //#region build
        public static Mesh Build(Mesh src, int seed = 3, float boundsPadding = 3f)
        {
            var rnd = new System.Random(seed);
            var sv = src.vertices; var sn = src.normals; var suv = src.uv; var tris = src.triangles;
            int n = tris.Length;
            var v = new Vector3[n]; var nr = new Vector3[n]; var uv = new Vector2[n];
            var uv1 = new Vector4[n]; var uv2 = new Vector4[n]; var idx = new int[n];
            for (int t = 0; t < n; t += 3)
            {
                Vector3 a = sv[tris[t]], b = sv[tris[t + 1]], c = sv[tris[t + 2]];
                Vector3 center = (a + b + c) / 3f;
                Vector3 face = Vector3.Cross(b - a, c - a).normalized;     // Unity 的绕序下这就是朝外的面法线
                float r = (float)rnd.NextDouble();
                for (int k = 0; k < 3; k++)
                {
                    int i = t + k, s = tris[i];
                    v[i] = sv[s]; nr[i] = sn.Length > 0 ? sn[s] : face; uv[i] = suv.Length > 0 ? suv[s] : Vector2.zero;
                    uv1[i] = new Vector4(center.x, center.y, center.z, r);
                    uv2[i] = new Vector4(face.x, face.y, face.z, 0);
                    idx[i] = i;
                }
            }
            var m = new Mesh { name = src.name + "_Shatter", indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.normals = nr; m.uv = uv; m.SetUVs(1, uv1); m.SetUVs(2, uv2); m.triangles = idx;
            m.RecalculateBounds();
            var bounds = m.bounds; bounds.Expand(boundsPadding);   // 碎片会飞出原包围盒
            m.bounds = bounds;
            return m;
        }
        //#endregion
    }
}
