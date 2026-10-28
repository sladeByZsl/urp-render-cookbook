// 程序生成面部阴影阈值图（俗称“脸部 SDF 图”）。
// 真实项目里，美术会针对若干个光照角度手绘“这一角度下脸上哪里亮”的二值图；
// 这里用一条带鼻子凸起的解析曲线代替手绘，后面的步骤（逐张算 SDF、相邻两张之间插值）与真实流程一致。
using System.Collections.Generic;
using UnityEngine;

namespace Cookbook.Ch14
{
    public static class FaceSdfGenerator
    {
        //#region mask
        // 光从画面右侧、与脸正前方成 phi（弧度，0~π）时，第 y 行的明暗交界线在哪（X ∈ [-1, 1]）
        static float Boundary(float phi, float y)
        {
            // 鼻子：交界线在鼻子高度处向暗侧“凸出”一块（鼻子挡光，留下鼻影）
            float nose = Mathf.Exp(-Mathf.Pow((y - 0.47f) / 0.07f, 2));
            // 眼窝与下巴：上下两端各稍微内收，交界线不再是一条竖直线
            float shape = 0.18f * Mathf.Exp(-Mathf.Pow((y - 0.6f) / 0.12f, 2)) - 0.25f * Mathf.Pow(Mathf.Max(0, 0.35f - y) / 0.35f, 2);
            // 把起伏乘上 sin(phi)：正面光和背光时没有影子形状可言；系数 < 1 保证随 phi 单调
            float p = phi + (0.55f * nose + shape) * Mathf.Sin(phi);
            return -Mathf.Cos(Mathf.Clamp(p, 0, Mathf.PI));
        }

        // 第 k 张二值图：1 = 亮，0 = 暗
        public static bool[] Mask(int size, float phi)
        {
            var m = new bool[size * size];
            for (int y = 0; y < size; y++)
            {
                float b = Boundary(phi, (y + 0.5f) / size);
                for (int x = 0; x < size; x++)
                    m[y * size + x] = ((x + 0.5f) / size * 2f - 1f) > b;
            }
            return m;
        }
        //#endregion

        //#region sdf
        // 有符号距离场：亮区为正、暗区为负，单位是像素。
        // 这里用最直白的做法：先找出所有边界像素，再对每个像素求到它们的最近距离。
        // 256² 的图足够快；更大的图请用 8SSEDT 或 Jump Flooding。
        public static float[] SignedDistance(bool[] mask, int size)
        {
            var edge = new List<Vector2>();
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    bool v = mask[y * size + x];
                    bool diff = (x + 1 < size && mask[y * size + x + 1] != v) || (y + 1 < size && mask[(y + 1) * size + x] != v);
                    if (diff) edge.Add(new Vector2(x + 0.5f, y + 0.5f));
                }
            var d = new float[size * size];
            if (edge.Count == 0)
            {
                // 全亮（phi = 0）或全暗（phi = π）的图没有边界：把交界线视为在图的左缘 / 右缘
                for (int y = 0; y < size; y++)
                    for (int x = 0; x < size; x++)
                        d[y * size + x] = mask[y * size + x] ? x + 0.5f : -(size - x - 0.5f);
                return d;
            }
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float best = float.MaxValue;
                    foreach (var e in edge)
                    {
                        float dx = e.x - x, dy = e.y - y;
                        float dd = dx * dx + dy * dy;
                        if (dd < best) best = dd;
                    }
                    float dist = Mathf.Sqrt(best);
                    d[y * size + x] = mask[y * size + x] ? dist : -dist;
                }
            return d;
        }
        //#endregion

        //#region blend
        // 合成阈值图：对每个像素，找到它“从亮变暗”的那两张相邻图 k、k+1，
        // 用两张图的 SDF 线性插值求出过零点的位置 t，阈值 = (k + t) / (N - 1)
        public static Texture2D Generate(int size, int count, out Texture2D maskViz, out Texture2D sdfViz, int vizIndex = 3)
        {
            var masks = new bool[count][];
            var sdfs = new float[count][];
            for (int k = 0; k < count; k++)
            {
                float phi = Mathf.PI * k / (count - 1);
                masks[k] = Mask(size, phi);
                sdfs[k] = SignedDistance(masks[k], size);
            }

            var outPx = new Color[size * size];
            for (int i = 0; i < size * size; i++)
            {
                float th = 0;
                for (int k = 0; k < count - 1; k++)
                {
                    float a = sdfs[k][i], b = sdfs[k + 1][i];
                    if (a >= 0 && b < 0)
                    {
                        float t = a / (a - b);
                        th = (k + t) / (count - 1);
                        break;
                    }
                    if (a >= 0 && b >= 0) th = (k + 1f) / (count - 1);   // 这一段一直是亮的
                }
                outPx[i] = new Color(th, th, th, 1);
            }

            maskViz = ToTex(size, i => masks[vizIndex][i] ? 1f : 0f);
            sdfViz = ToTex(size, i => Mathf.Clamp01(0.5f + sdfs[vizIndex][i] / (size * 0.5f)));
            var tex = new Texture2D(size, size, TextureFormat.RGBAHalf, false, true)
            { name = "FaceThreshold", wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            tex.SetPixels(outPx); tex.Apply();
            return tex;
        }
        //#endregion

        static Texture2D ToTex(int size, System.Func<int, float> f)
        {
            var px = new Color[size * size];
            for (int i = 0; i < px.Length; i++) { float v = f(i); px[i] = new Color(v, v, v, 1); }
            var t = new Texture2D(size, size, TextureFormat.RGBA32, false, true) { wrapMode = TextureWrapMode.Clamp };
            t.SetPixels(px); t.Apply();
            return t;
        }
    }
}
