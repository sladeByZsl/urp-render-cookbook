// 第 8 章的运行时工具：把“任意环境函数”投影成球谐（环境光）、生成预过滤的 Cubemap（环境反射）。
// 环境用一个 C# 函数 radiance(direction) 描述，返回该方向射来的辐射率（线性空间，可以大于 1）。
using System;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch08
{
    public static class EnvironmentTools
    {
        //#region project
        /// 蒙特卡洛投影：在球面上均匀取 sampleCount 个方向，每个方向当成一盏小方向光加进 SH。
        /// AddDirectionalLight 内部已经做了余弦卷积，但它的归一化是“在灯光方向上求值 = 2 × 强度”
        /// （实测：AddDirectionalLight(up, 白, 1) 在 up 方向求值得 2.0）。而三阶截断的余弦波瓣在峰值处
        /// 理论值是 1/4 + 1/2 + 5/16 = 17/16，所以 Unity 的结果比“辐照度/π”大 2÷(17/16) = 32/17 倍。
        /// 均匀环境 L 拆成 N 盏灯时，每盏取 4L/N 才能得到 L，再乘 17/32 抵消上面的倍数。
        public static SphericalHarmonicsL2 ProjectToSH(Func<Vector3, Color> radiance, int sampleCount = 4096, int seed = 1)
        {
            var sh = new SphericalHarmonicsL2();
            var rnd = new System.Random(seed);
            float weight = 4f / sampleCount * (17f / 32f);
            for (int i = 0; i < sampleCount; i++)
            {
                float z = (float)rnd.NextDouble() * 2f - 1f;
                float a = (float)rnd.NextDouble() * Mathf.PI * 2f;
                float r = Mathf.Sqrt(1f - z * z);
                var d = new Vector3(r * Mathf.Cos(a), z, r * Mathf.Sin(a));
                sh.AddDirectionalLight(d, radiance(d), weight);
            }
            return sh;
        }
        //#endregion

        /// 近似 Lighting 窗口 Environment Lighting 的 Gradient 模式：天空 / 地平线 / 地面三色
        public static Func<Vector3, Color> Gradient(Color sky, Color equator, Color ground) => d =>
            d.y >= 0 ? Color.Lerp(equator, sky, Mathf.Pow(d.y, 0.6f)) : Color.Lerp(equator, ground, Mathf.Pow(-d.y, 0.6f));

        //#region cubemap
        /// 生成 HDR Cubemap，并按 URP 的“粗糙度 → mip”曲线对每一级 mip 做 GGX 预过滤（split-sum 的第一项）。
        public static Cubemap BakeCubemap(Func<Vector3, Color> radiance, int size = 128, int samplesPerTexel = 64)
        {
            var cube = new Cubemap(size, TextureFormat.RGBAHalf, true) { name = "Ch08Env", hideFlags = HideFlags.DontSave };
            int mipCount = cube.mipmapCount;
            for (int mip = 0; mip < mipCount; mip++)
            {
                int s = Mathf.Max(1, size >> mip);
                // URP: mip = r·(1.7 - 0.7r)·6，反解出这一级对应的感知粗糙度 r
                float t = Mathf.Min(mip / 6f, 1f);
                float perceptual = (1.7f - Mathf.Sqrt(2.89f - 2.8f * t)) / 1.4f;
                float alpha = Mathf.Max(perceptual * perceptual, 1e-4f);
                var px = new Color[s * s];
                for (int f = 0; f < 6; f++)
                {
                    for (int y = 0; y < s; y++)
                        for (int x = 0; x < s; x++)
                        {
                            Vector3 n = FaceDirection((CubemapFace)f, (x + 0.5f) / s * 2f - 1f, (y + 0.5f) / s * 2f - 1f);
                            px[y * s + x] = mip == 0 ? radiance(n) : PrefilterGGX(radiance, n, alpha, samplesPerTexel);
                        }
                    cube.SetPixels(px, (CubemapFace)f, mip);
                }
            }
            cube.Apply(false, false);
            return cube;
        }

        // 预过滤假设 N = V = R：以 N 为中心按 GGX 分布重要性采样半程向量 H，反射出 L，按 N·L 加权平均
        static Color PrefilterGGX(Func<Vector3, Color> radiance, Vector3 n, float alpha, int count)
        {
            Vector3 up = Mathf.Abs(n.y) < 0.999f ? Vector3.up : Vector3.right;
            Vector3 tx = Vector3.Normalize(Vector3.Cross(up, n));
            Vector3 ty = Vector3.Cross(n, tx);
            Color sum = Color.black; float wsum = 0;
            for (int i = 0; i < count; i++)
            {
                // Hammersley 低差异序列
                float u1 = (i + 0.5f) / count;
                uint bits = (uint)i;
                bits = (bits << 16) | (bits >> 16);
                bits = ((bits & 0x55555555u) << 1) | ((bits & 0xAAAAAAAAu) >> 1);
                bits = ((bits & 0x33333333u) << 2) | ((bits & 0xCCCCCCCCu) >> 2);
                bits = ((bits & 0x0F0F0F0Fu) << 4) | ((bits & 0xF0F0F0F0u) >> 4);
                bits = ((bits & 0x00FF00FFu) << 8) | ((bits & 0xFF00FF00u) >> 8);
                float u2 = bits * 2.3283064365386963e-10f;
                // GGX 的 cosθh 采样公式
                float phi = 2f * Mathf.PI * u2;
                float cosT = Mathf.Sqrt((1f - u1) / (1f + (alpha * alpha - 1f) * u1));
                float sinT = Mathf.Sqrt(1f - cosT * cosT);
                Vector3 h = tx * (sinT * Mathf.Cos(phi)) + ty * (sinT * Mathf.Sin(phi)) + n * cosT;
                Vector3 l = 2f * Vector3.Dot(n, h) * h - n;
                float ndl = Vector3.Dot(n, l);
                if (ndl <= 0) continue;
                sum += radiance(l) * ndl; wsum += ndl;
            }
            return wsum > 0 ? sum / wsum : Color.black;
        }

        /// Cubemap 第 face 面上 (u,v)∈[-1,1] 的像素对应的方向（与 Unity 的面朝向约定一致）
        public static Vector3 FaceDirection(CubemapFace face, float u, float v)
        {
            Vector3 d;
            switch (face)
            {
                case CubemapFace.PositiveX: d = new Vector3(1, -v, -u); break;
                case CubemapFace.NegativeX: d = new Vector3(-1, -v, u); break;
                case CubemapFace.PositiveY: d = new Vector3(u, 1, v); break;
                case CubemapFace.NegativeY: d = new Vector3(u, -1, -v); break;
                case CubemapFace.PositiveZ: d = new Vector3(u, -v, 1); break;
                default: d = new Vector3(-u, -v, -1); break;
            }
            return d.normalized;
        }
        //#endregion

        //#region irradiance
        /// “标准答案”：对每个法线方向做余弦加权的半球积分，得到 URP 约定下的间接漫反射（E/π）。
        /// 用来和 9 个系数的 SH 近似做对比。
        public static Cubemap BakeIrradiance(Func<Vector3, Color> radiance, int size = 32, int samples = 1024)
        {
            var cube = new Cubemap(size, TextureFormat.RGBAHalf, false) { name = "Ch08Irradiance", hideFlags = HideFlags.DontSave };
            var px = new Color[size * size];
            for (int f = 0; f < 6; f++)
            {
                for (int y = 0; y < size; y++)
                    for (int x = 0; x < size; x++)
                    {
                        Vector3 n = FaceDirection((CubemapFace)f, (x + 0.5f) / size * 2f - 1f, (y + 0.5f) / size * 2f - 1f);
                        Vector3 up = Mathf.Abs(n.y) < 0.999f ? Vector3.up : Vector3.right;
                        Vector3 tx = Vector3.Normalize(Vector3.Cross(up, n)), ty = Vector3.Cross(n, tx);
                        Color sum = Color.black;
                        int sq = Mathf.RoundToInt(Mathf.Sqrt(samples));
                        for (int i = 0; i < sq; i++)
                            for (int j = 0; j < sq; j++)
                            {
                                // 分层的余弦加权采样：pdf = cosθ/π，正好与积分里的 cosθ/π 抵消，结果就是简单平均
                                float u1 = (i + 0.5f) / sq, u2 = (j + 0.5f) / sq;
                                float r = Mathf.Sqrt(u1), phi = 2f * Mathf.PI * u2;
                                Vector3 l = tx * (r * Mathf.Cos(phi)) + ty * (r * Mathf.Sin(phi)) + n * Mathf.Sqrt(1f - u1);
                                sum += radiance(l);
                            }
                        px[y * size + x] = sum / (sq * sq);
                    }
                cube.SetPixels(px, (CubemapFace)f);
            }
            cube.Apply(false, false);
            return cube;
        }
        //#endregion

        // ---------------- 几个现成的环境函数 ----------------

        /// 摄影棚：深灰背景 + 两块大柔光箱 + 一条暖色轮廓灯
        public static Color Studio(Vector3 d)
        {
            float g = Mathf.Lerp(0.03f, 0.10f, d.y * 0.5f + 0.5f);
            Color c = new Color(g, g, g * 1.05f);
            c += SoftBox(d, new Vector3(-0.6f, 0.7f, -0.4f), 0.55f, 0.35f) * new Color(6f, 6f, 6f);
            c += SoftBox(d, new Vector3(0.8f, 0.25f, -0.3f), 0.25f, 0.45f) * new Color(2.5f, 2.6f, 3f);
            c += SoftBox(d, new Vector3(0.1f, 0.3f, 1f), 0.9f, 0.08f) * new Color(3f, 1.6f, 0.6f);
            return c;
        }

        /// 黄昏：低垂的暖色太阳 + 紫蓝天顶
        public static Color Sunset(Vector3 d)
        {
            Color horizon = new Color(1.4f, 0.55f, 0.22f), zenith = new Color(0.12f, 0.1f, 0.35f), ground = new Color(0.08f, 0.05f, 0.05f);
            Color c = d.y >= 0 ? Color.Lerp(horizon, zenith, Mathf.Pow(d.y, 0.4f)) : Color.Lerp(horizon * 0.4f, ground, Mathf.Clamp01(-d.y * 5f));
            Vector3 sun = new Vector3(0.75f, 0.08f, 0.65f).normalized;
            float sd = Mathf.Max(0, Vector3.Dot(d, sun));
            c += new Color(6f, 3f, 1.2f) * Mathf.Pow(sd, 400f) + new Color(0.6f, 0.25f, 0.08f) * Mathf.Pow(sd, 8f);
            return c;
        }

        /// 与拍摄环境默认天空相近的晴天（不含太阳尖峰，太阳交给方向光）
        public static Color ClearSky(Vector3 d)
        {
            Color zenith = new Color(0.12f, 0.25f, 0.55f), horizon = new Color(0.55f, 0.6f, 0.68f), ground = new Color(0.2f, 0.19f, 0.18f);
            return d.y >= 0 ? Color.Lerp(horizon, zenith, Mathf.Pow(d.y, 0.45f)) : Color.Lerp(horizon * 0.6f, ground, Mathf.Clamp01(-d.y * 4f));
        }

        // 方向 d 落在以 center 为法线、半宽 a、半高 b 的矩形“窗口”里时返回 1（边缘柔化）
        static float SoftBox(Vector3 d, Vector3 center, float a, float b)
        {
            Vector3 c = center.normalized;
            float k = Vector3.Dot(d, c);
            if (k <= 0) return 0;
            Vector3 p = d / k;
            Vector3 u = Vector3.Normalize(Vector3.Cross(Vector3.up, c));
            if (u.sqrMagnitude < 1e-4f) u = Vector3.right;
            Vector3 v = Vector3.Cross(c, u);
            float x = Mathf.Abs(Vector3.Dot(p, u)) / a, y = Mathf.Abs(Vector3.Dot(p, v)) / b;
            return Mathf.Clamp01((1f - x) * 12f) * Mathf.Clamp01((1f - y) * 12f);
        }
    }
}
