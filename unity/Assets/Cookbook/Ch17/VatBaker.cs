// VAT（Vertex Animation Texture，顶点动画贴图）烘焙器：
// 把“每一帧每个顶点的位置/法线”写进两张浮点贴图——横向 = 顶点编号，纵向 = 帧号。
// 运行时 Shader 用顶点编号和帧号去采样，就能回放任意复杂的动画（布料、破碎、流体模拟……），
// CPU 端不需要骨骼、不需要每帧上传网格。这里用一个程序化的“触手”动画做演示。
using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch17
{
    public static class VatBaker
    {
        public struct Result
        {
            public Mesh mesh;              // uv1.x = 该顶点在贴图里的 u 坐标
            public Texture2D position;     // RGBAHalf，rgb = 物体空间位置
            public Texture2D normal;       // RGBAHalf，rgb = 物体空间法线
        }

        //#region bake
        public static Result Bake(Mesh baseMesh, int frameCount, Func<int, Vector3[]> framePositions)
        {
            int vc = baseMesh.vertexCount;
            var posTex = new Texture2D(vc, frameCount, TextureFormat.RGBAHalf, false, true)
            { name = "VAT_Position", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            var nrmTex = new Texture2D(vc, frameCount, TextureFormat.RGBAHalf, false, true)
            { name = "VAT_Normal", filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };

            var tmp = UnityEngine.Object.Instantiate(baseMesh);        // 只用来逐帧重算法线
            var pos = new Color[vc * frameCount]; var nrm = new Color[vc * frameCount];
            var bounds = new Bounds(baseMesh.bounds.center, Vector3.zero);
            for (int f = 0; f < frameCount; f++)
            {
                var p = framePositions(f);
                tmp.vertices = p;
                tmp.RecalculateNormals();
                var n = tmp.normals;
                for (int i = 0; i < vc; i++)
                {
                    pos[f * vc + i] = new Color(p[i].x, p[i].y, p[i].z, 1);   // 行 = 帧，列 = 顶点
                    nrm[f * vc + i] = new Color(n[i].x, n[i].y, n[i].z, 0);
                    bounds.Encapsulate(p[i]);
                }
            }
            UnityEngine.Object.DestroyImmediate(tmp);
            posTex.SetPixels(pos); posTex.Apply(false);
            nrmTex.SetPixels(nrm); nrmTex.Apply(false);

            // 网格：拓扑不变，额外写入顶点编号对应的 u 坐标（采样纹素中心，所以 +0.5）
            var mesh = UnityEngine.Object.Instantiate(baseMesh);
            mesh.name = baseMesh.name + "_VAT";
            var uv1 = new Vector2[vc];
            for (int i = 0; i < vc; i++) uv1[i] = new Vector2((i + 0.5f) / vc, 0);
            mesh.uv2 = uv1;                                                // uv2 即 TEXCOORD1
            mesh.bounds = bounds;                                          // 包围盒要覆盖所有帧
            return new Result { mesh = mesh, position = posTex, normal = nrmTex };
        }
        //#endregion

        // ---------- 演示用：程序化的触手 ----------
        /// 竖直的圆管：rings 段高、segs 段周长，高 2 米，底部半径 0.22
        public static Mesh Tentacle(int rings = 40, int segs = 20)
        {
            var v = new Vector3[(rings + 1) * (segs + 1)]; var uv = new Vector2[v.Length];
            for (int r = 0; r <= rings; r++)
                for (int s = 0; s <= segs; s++)
                {
                    float h = (float)r / rings, a = (float)s / segs * Mathf.PI * 2f;
                    float rad = 0.22f * (1f - 0.8f * h);
                    v[r * (segs + 1) + s] = new Vector3(Mathf.Cos(a) * rad, h * 2f, Mathf.Sin(a) * rad);
                    uv[r * (segs + 1) + s] = new Vector2((float)s / segs, h);
                }
            var idx = new int[rings * segs * 6]; int k = 0;
            for (int r = 0; r < rings; r++)
                for (int s = 0; s < segs; s++)
                {
                    int a = r * (segs + 1) + s, b = a + segs + 1;
                    idx[k++] = a; idx[k++] = b; idx[k++] = a + 1;
                    idx[k++] = a + 1; idx[k++] = b; idx[k++] = b + 1;
                }
            var m = new Mesh { name = "Tentacle", indexFormat = IndexFormat.UInt32 };
            m.vertices = v; m.uv = uv; m.triangles = idx; m.RecalculateNormals(); m.RecalculateBounds();
            return m;
        }

        /// 第 f 帧（共 frames 帧，循环）的顶点位置：沿高度传播的弯曲 + 扭转。
        /// 实际项目里这一步来自 Houdini/Blender 的模拟或动画，这里用公式代替。
        public static Vector3[] TentacleFrame(Vector3[] rest, int f, int frames)
        {
            float t = (float)f / frames * Mathf.PI * 2f;
            var p = new Vector3[rest.Length];
            for (int i = 0; i < rest.Length; i++)
            {
                var v = rest[i];
                float h = v.y / 2f;                                        // 0..1
                float bendX = Mathf.Sin(t - h * 3.5f) * 0.9f * h * h;      // 弯曲波从根部传向尖端
                float bendZ = Mathf.Cos(t * 1 - h * 2.5f) * 0.4f * h * h;
                float twist = Mathf.Sin(t) * 1.2f * h;                     // 绕自身轴的扭转
                float cs = Mathf.Cos(twist), sn = Mathf.Sin(twist);
                var local = new Vector3(v.x * cs - v.z * sn, 0, v.x * sn + v.z * cs);
                // 弯曲后高度略降，近似保持长度
                float y = v.y - (bendX * bendX + bendZ * bendZ) * 0.5f;
                p[i] = new Vector3(local.x + bendX, y, local.z + bendZ);
            }
            return p;
        }
    }
}
