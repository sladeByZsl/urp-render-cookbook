// 程序化生成色调艺术贴图（Tonal Art Map，TAM）：6 个色阶的笔触贴图，
// 并打包成两张 RGB 贴图（Hatch0 = 第 1~3 级，Hatch1 = 第 4~6 级）。
// 关键性质是“嵌套”：深一级的贴图包含浅一级的全部笔触，再额外加笔触，
// 这样色阶之间混合时笔触不会凭空跳动。
using UnityEngine;

namespace Cookbook.Ch15
{
    public static class HatchTextures
    {
        public const int Levels = 6;

        //#region tam
        /// 返回 6 张单通道色阶（1 = 纸白，0 = 墨黑），每张 size×size，可无缝平铺
        public static float[][] BuildLevels(int size = 256, int seed = 1234)
        {
            var rnd = new System.Random(seed);
            var levels = new float[Levels][];
            var ink = new float[size * size];                 // 当前累计的“墨量”
            for (int i = 0; i < ink.Length; i++) ink[i] = 0f;

            // 每一级新增的笔触：数量、主方向（度）。前三级只有横向排线，后三级加交叉线
            int[] count = { 45, 55, 70, 50, 80, 130 };
            float[] angle = { 8, 10, 12, 98, 52, -40 };

            for (int lv = 0; lv < Levels; lv++)
            {
                for (int k = 0; k < count[lv]; k++)
                {
                    float cx = (float)rnd.NextDouble() * size, cy = (float)rnd.NextDouble() * size;
                    float len = size * (0.18f + 0.22f * (float)rnd.NextDouble());
                    float a = (angle[lv] + ((float)rnd.NextDouble() - 0.5f) * 10f) * Mathf.Deg2Rad;
                    float width = 0.9f + 0.6f * (float)rnd.NextDouble();
                    float dark = 0.55f + 0.35f * (float)rnd.NextDouble();
                    Stroke(ink, size, cx, cy, Mathf.Cos(a), Mathf.Sin(a), len, width, dark);
                }
                var tone = new float[size * size];
                for (int i = 0; i < tone.Length; i++) tone[i] = Mathf.Clamp01(1f - ink[i]);
                levels[lv] = tone;                             // 拷贝当前累计结果：天然嵌套
            }
            return levels;
        }

        // 画一条两端渐细的软边线段；坐标对 size 取模，所以贴图可以无缝平铺
        static void Stroke(float[] ink, int size, float cx, float cy, float dx, float dy, float len, float width, float dark)
        {
            int steps = Mathf.CeilToInt(len * 2f);
            for (int s = 0; s <= steps; s++)
            {
                float t = (float)s / steps - 0.5f;             // -0.5..0.5
                float taper = 1f - Mathf.Pow(Mathf.Abs(t) * 2f, 4f);   // 笔触两头变细、变淡
                float px = cx + dx * t * len, py = cy + dy * t * len;
                int r = Mathf.CeilToInt(width + 1);
                for (int oy = -r; oy <= r; oy++)
                    for (int ox = -r; ox <= r; ox++)
                    {
                        int x = Mathf.FloorToInt(px) + ox, y = Mathf.FloorToInt(py) + oy;
                        float d = Mathf.Sqrt((x + 0.5f - px) * (x + 0.5f - px) + (y + 0.5f - py) * (y + 0.5f - py));
                        float cover = Mathf.Clamp01(width * taper - d + 0.5f);
                        if (cover <= 0) continue;
                        int idx = ((y % size + size) % size) * size + ((x % size + size) % size);
                        // 用 max 而不是累加：同一条线的相邻采样点不会越叠越黑
                        ink[idx] = Mathf.Max(ink[idx], Mathf.Min(1f, ink[idx] * 0.35f + cover * dark));
                    }
            }
        }
        //#endregion

        /// 把 6 级打包成两张 RGB 贴图，开启 mipmap（远处笔触由 mip 平均，平均灰度保持不变）
        public static void Pack(float[][] levels, int size, out Texture2D hatch0, out Texture2D hatch1)
        {
            hatch0 = new Texture2D(size, size, TextureFormat.RGBA32, true, true) { name = "Hatch0", wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4 };
            hatch1 = new Texture2D(size, size, TextureFormat.RGBA32, true, true) { name = "Hatch1", wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 4 };
            var c0 = new Color[size * size]; var c1 = new Color[size * size];
            for (int i = 0; i < c0.Length; i++)
            {
                c0[i] = new Color(levels[0][i], levels[1][i], levels[2][i], 1);
                c1[i] = new Color(levels[3][i], levels[4][i], levels[5][i], 1);
            }
            hatch0.SetPixels(c0); hatch0.Apply(true);
            hatch1.SetPixels(c1); hatch1.Apply(true);
        }

        /// 6 级并排的预览图（配图用）
        public static Texture2D Preview(float[][] levels, int size)
        {
            int gap = size / 16;
            int w = size * Levels + gap * (Levels - 1);
            var tex = new Texture2D(w, size, TextureFormat.RGBA32, false, false) { filterMode = FilterMode.Bilinear };
            var px = new Color[w * size];
            for (int i = 0; i < px.Length; i++) px[i] = Color.white;
            for (int lv = 0; lv < Levels; lv++)
                for (int y = 0; y < size; y++)
                    for (int x = 0; x < size; x++)
                    {
                        float v = levels[lv][y * size + x];
                        px[y * w + lv * (size + gap) + x] = new Color(v, v, v * 0.97f, 1);
                    }
            tex.SetPixels(px); tex.Apply();
            return tex;
        }
    }
}
