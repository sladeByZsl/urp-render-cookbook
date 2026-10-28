// 程序生成一张“可无缝平铺”的水面法线贴图。
// 要点：① 所有正弦波的波矢在贴图周期内都是整数圈；② 值噪声的格点按周期取模；③ 求导时坐标回绕（wrap）。
// 三条缺一条，平铺时就会在贴图边界出现一条细缝——水面上这种缝非常显眼。
using UnityEngine;

namespace Cookbook.Ch19
{
    public static class WaterNormalGenerator
    {
        static Texture2D s_Cached;

        //#region gen
        public static Texture2D Create(int size = 256, float strength = 3.5f)
        {
            if (s_Cached != null) return s_Cached;
            var h = new float[size, size];
            // 整数波矢 (kx, ky)：在一个贴图周期里正好走完整数个波长，左右/上下边界自然衔接。
            // 方向大致集中在“风向”附近，看起来才像被风吹出来的水纹
            int[,] k = { { 3, 1 }, { 2, 3 }, { 4, -1 }, { 5, 2 }, { 3, 5 }, { 6, -3 }, { 7, 4 }, { -2, 6 },
                         { 9, 2 }, { 8, 7 }, { 11, -4 }, { 5, 10 }, { 13, 3 }, { -7, 11 } };
            var rnd = new System.Random(19);
            var phase = new float[k.GetLength(0)];
            for (int i = 0; i < phase.Length; i++) phase[i] = (float)rnd.NextDouble() * Mathf.PI * 2;

            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    float u = (float)x / size, v = (float)y / size, sum = 0;
                    // 域扭曲：用周期噪声扰动相位，打破正弦叠加的“格子布”感（噪声是周期的，所以仍然无缝）
                    float warp = PeriodicNoise(u, v, 4, 7) * 2.2f + PeriodicNoise(u, v, 8, 8) * 1.1f;
                    for (int i = 0; i < phase.Length; i++)
                    {
                        float kx = k[i, 0], ky = k[i, 1];
                        float amp = 1f / Mathf.Sqrt(kx * kx + ky * ky);
                        sum += amp * Mathf.Sin(2 * Mathf.PI * (kx * u + ky * v) + phase[i] + warp);
                    }
                    // 再叠几层周期性值噪声（fBm）
                    sum += 0.3f * PeriodicNoise(u, v, 8, 1) + 0.15f * PeriodicNoise(u, v, 16, 2) + 0.08f * PeriodicNoise(u, v, 32, 3);
                    h[x, y] = sum;
                }

            var px = new Color[size * size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    // 中心差分，坐标按周期回绕
                    float dx = (h[(x + 1) % size, y] - h[(x - 1 + size) % size, y]) * 0.5f * strength;
                    float dy = (h[x, (y + 1) % size] - h[x, (y - 1 + size) % size]) * 0.5f * strength;
                    var n = new Vector3(-dx, -dy, 1).normalized;
                    // R=x、G=y、B=z、A=1。URP 的 UnpackNormalScale 在桌面平台走 UnpackNormalmapRGorAG：
                    // 先 a *= r 再取 (a, g)，A=1 时得到的正好是 (r, g)，所以这种未压缩的 RGBA 也能正确解码
                    px[y * size + x] = new Color(n.x * 0.5f + 0.5f, n.y * 0.5f + 0.5f, n.z * 0.5f + 0.5f, 1);
                }

            s_Cached = new Texture2D(size, size, TextureFormat.RGBA32, true, true)
            {
                name = "WaterNormal_Tileable", wrapMode = TextureWrapMode.Repeat,
                filterMode = FilterMode.Trilinear, anisoLevel = 4, hideFlags = HideFlags.DontSave
            };
            s_Cached.SetPixels(px);
            s_Cached.Apply(true);
            return s_Cached;
        }
        //#endregion

        // 周期为 cells 个格子的值噪声：格点索引对 cells 取模，所以 u=0 与 u=1 取到同一组格点
        static float PeriodicNoise(float u, float v, int cells, int seed)
        {
            float x = u * cells, y = v * cells;
            int x0 = Mathf.FloorToInt(x), y0 = Mathf.FloorToInt(y);
            float fx = x - x0, fy = y - y0;
            fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
            float a = Lattice(x0, y0, cells, seed), b = Lattice(x0 + 1, y0, cells, seed);
            float c = Lattice(x0, y0 + 1, cells, seed), d = Lattice(x0 + 1, y0 + 1, cells, seed);
            return Mathf.Lerp(Mathf.Lerp(a, b, fx), Mathf.Lerp(c, d, fx), fy) * 2 - 1;
        }

        static float Lattice(int x, int y, int cells, int seed)
        {
            x = ((x % cells) + cells) % cells; y = ((y % cells) + cells) % cells;
            uint hsh = (uint)(x * 374761393 + y * 668265263 + seed * 1442695041);
            hsh = (hsh ^ (hsh >> 13)) * 1274126177u;
            return (hsh ^ (hsh >> 16)) / (float)uint.MaxValue;
        }
    }
}
