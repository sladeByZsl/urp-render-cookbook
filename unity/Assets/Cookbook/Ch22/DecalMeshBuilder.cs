// 案例 22.9：生成网格贴花——把目标网格落在“贴花盒子”里的三角形裁出来，生成一块贴合表面的新网格。
// 盒子约定与 URP Decal Projector 相同：本地空间 [-0.5, 0.5]³，沿 +Z 投影，UV = 本地 xy + 0.5。
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch22
{
    public static class DecalMeshBuilder
    {
        struct Vert
        {
            public Vector3 pos;      // 盒子本地空间
            public Vector3 normal;   // 世界空间
            public Vert(Vector3 p, Vector3 n) { pos = p; normal = n; }
            public static Vert Lerp(Vert a, Vert b, float t) => new Vert(Vector3.Lerp(a.pos, b.pos, t), Vector3.Lerp(a.normal, b.normal, t));
        }

        //#region build
        /// <param name="box">贴花盒子（用它的 Transform 的位置/旋转/缩放）</param>
        /// <param name="targets">要贴上去的网格</param>
        /// <param name="maxAngle">表面法线与“逆投影方向”的夹角超过它就不贴（避免侧壁拉伸）</param>
        /// <param name="pushOut">沿法线外推的距离（米），配合 Shader 的 Offset 进一步防止 Z-Fighting</param>
        /// <returns>世界空间网格（挂到一个位于原点、无旋转缩放的物体上）</returns>
        public static Mesh Build(Transform box, IEnumerable<MeshFilter> targets, float maxAngle = 80f, float pushOut = 0.002f)
        {
            var worldToBox = box.worldToLocalMatrix;
            var boxToWorld = box.localToWorldMatrix;
            Vector3 backDir = -box.forward;                  // “逆投影方向”，正对投影器的表面法线与它一致
            float minFacing = Mathf.Cos(maxAngle * Mathf.Deg2Rad);

            var outPos = new List<Vector3>(); var outNrm = new List<Vector3>();
            var outUV = new List<Vector2>(); var outIdx = new List<int>();
            var poly = new List<Vert>(9); var tmp = new List<Vert>(9);

            foreach (var mf in targets)
            {
                var mesh = mf.sharedMesh;
                var l2w = mf.transform.localToWorldMatrix;
                var nrmMat = l2w.inverse.transpose;          // 法线用逆转置矩阵变换
                var verts = mesh.vertices; var normals = mesh.normals; var tris = mesh.triangles;
                for (int t = 0; t < tris.Length; t += 3)
                {
                    Vector3 w0 = l2w.MultiplyPoint3x4(verts[tris[t]]);
                    Vector3 w1 = l2w.MultiplyPoint3x4(verts[tris[t + 1]]);
                    Vector3 w2 = l2w.MultiplyPoint3x4(verts[tris[t + 2]]);
                    // 1) 背向投影器（或太斜）的三角形不要
                    Vector3 faceN = Vector3.Cross(w1 - w0, w2 - w0).normalized;
                    if (Vector3.Dot(faceN, backDir) < minFacing) continue;

                    poly.Clear();
                    for (int k = 0; k < 3; k++)
                    {
                        int vi = tris[t + k];
                        Vector3 w = k == 0 ? w0 : (k == 1 ? w1 : w2);
                        Vector3 n = nrmMat.MultiplyVector(normals[vi]).normalized;
                        poly.Add(new Vert(worldToBox.MultiplyPoint3x4(w), n));
                    }
                    // 2) 依次用盒子的 6 个面裁剪（Sutherland–Hodgman）
                    for (int axis = 0; axis < 3 && poly.Count >= 3; axis++)
                    {
                        ClipAgainstPlane(poly, tmp, axis, +1f);
                        ClipAgainstPlane(tmp, poly, axis, -1f);
                    }
                    if (poly.Count < 3) continue;

                    // 3) 剩下的凸多边形扇形三角化，输出世界坐标 + 盒子 UV
                    int baseIdx = outPos.Count;
                    foreach (var v in poly)
                    {
                        Vector3 n = v.normal.normalized;
                        outPos.Add(boxToWorld.MultiplyPoint3x4(v.pos) + n * pushOut);
                        outNrm.Add(n);
                        outUV.Add(new Vector2(v.pos.x + 0.5f, v.pos.y + 0.5f));
                    }
                    for (int k = 1; k < poly.Count - 1; k++)
                    {
                        outIdx.Add(baseIdx); outIdx.Add(baseIdx + k); outIdx.Add(baseIdx + k + 1);
                    }
                }
            }
            var m = new Mesh { name = "DecalMesh", indexFormat = IndexFormat.UInt32 };
            m.SetVertices(outPos); m.SetNormals(outNrm); m.SetUVs(0, outUV); m.SetTriangles(outIdx, 0);
            m.RecalculateTangents();   // 有了 UV 才能算切线，供法线贴图使用
            m.RecalculateBounds();
            return m;
        }
        //#endregion

        //#region clip
        /// 保留 sign × pos[axis] ≤ 0.5 的部分。src → dst
        static void ClipAgainstPlane(List<Vert> src, List<Vert> dst, int axis, float sign)
        {
            dst.Clear();
            int n = src.Count;
            for (int i = 0; i < n; i++)
            {
                Vert a = src[i], b = src[(i + 1) % n];
                float da = 0.5f - sign * a.pos[axis];      // ≥ 0 表示在盒子这一侧
                float db = 0.5f - sign * b.pos[axis];
                if (da >= 0) dst.Add(a);
                if ((da >= 0) != (db >= 0))                 // 跨过平面：插入交点
                    dst.Add(Vert.Lerp(a, b, da / (da - db)));
            }
        }
        //#endregion
    }
}
