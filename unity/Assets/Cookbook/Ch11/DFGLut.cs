// 程序生成 split-sum 的环境 BRDF 查找表（DFG LUT）。
// 对每个 (NoV, 感知粗糙度) 用 GGX 重要性采样数值积分：
//   ∫ f_s cosθ dω = F0 · A + F90 · B
//   A = 平均[(1 - Fc) · Gv]，B = 平均[Fc · Gv]，Fc = (1 - VoH)^5，Gv = V · 4 NoL VoH / NoH
// 其中 V 是高度相关 Smith 可见性项 —— 与 MyPBR_BRDF.hlsl 里的直接光完全同一套模型。
using UnityEngine;

namespace Cookbook.Ch11
{
    public static class DFGLut
    {
        //#region generate
        public static Texture2D Generate(int size = 64, int sampleCount = 512)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBAHalf, false, true)   // 线性、无 mip
            {
                name = "MyPBR_DFG_LUT",
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear
            };
            var px = new Color[size * size];
            for (int y = 0; y < size; y++)
            {
                float perceptualRoughness = (y + 0.5f) / size;   // 取像素中心，双线性采样时才对得上
                float a = perceptualRoughness * perceptualRoughness;
                for (int x = 0; x < size; x++)
                {
                    float NoV = (x + 0.5f) / size;
                    Vector2 ab = Integrate(NoV, a, sampleCount);
                    px[y * size + x] = new Color(ab.x, ab.y, 0, 1);
                }
            }
            tex.SetPixels(px);
            tex.Apply(false, false);
            return tex;
        }

        static Vector2 Integrate(float NoV, float a, int sampleCount)
        {
            // 切线空间里 N = (0,0,1)，V 放在 xz 平面
            var V = new Vector3(Mathf.Sqrt(1f - NoV * NoV), 0f, NoV);
            float a2 = a * a;
            float A = 0, B = 0;
            for (int i = 0; i < sampleCount; i++)
            {
                Vector2 xi = Hammersley(i, sampleCount);
                Vector3 H = ImportanceSampleGGX(xi, a2);
                Vector3 L = 2f * Vector3.Dot(V, H) * H - V;
                float NoL = Mathf.Clamp01(L.z);
                float NoH = Mathf.Clamp01(H.z);
                float VoH = Mathf.Clamp01(Vector3.Dot(V, H));
                if (NoL <= 0f) continue;

                // pdf(L) = D · NoH / (4 VoH)；被积函数 f_s·NoL = D·V·F·NoL
                // 两者相除 D 消掉：F · V · 4 · NoL · VoH / NoH
                float vis = SmithGGXCorrelated(NoV, NoL, a2);
                float gv = vis * 4f * NoL * VoH / Mathf.Max(NoH, 1e-6f);
                float fc = Mathf.Pow(1f - VoH, 5f);
                A += (1f - fc) * gv;
                B += fc * gv;
            }
            return new Vector2(A / sampleCount, B / sampleCount);
        }

        // 与 HLSL 的 MyV_SmithGGXCorrelated 逐字对应
        static float SmithGGXCorrelated(float NoV, float NoL, float a2)
        {
            float lv = NoL * Mathf.Sqrt((NoV - NoV * a2) * NoV + a2);
            float ll = NoV * Mathf.Sqrt((NoL - NoL * a2) * NoL + a2);
            return 0.5f / Mathf.Max(lv + ll, 1e-5f);
        }

        // GGX 重要性采样：按 D(h)·NoH 的分布抽半角向量
        static Vector3 ImportanceSampleGGX(Vector2 xi, float a2)
        {
            float phi = 2f * Mathf.PI * xi.x;
            float cosTheta = Mathf.Sqrt((1f - xi.y) / (1f + (a2 - 1f) * xi.y));
            float sinTheta = Mathf.Sqrt(1f - cosTheta * cosTheta);
            return new Vector3(sinTheta * Mathf.Cos(phi), sinTheta * Mathf.Sin(phi), cosTheta);
        }

        // 低差异序列：比纯随机数收敛快得多，512 个样本就很平滑
        static Vector2 Hammersley(int i, int n)
        {
            uint bits = (uint)i;
            bits = (bits << 16) | (bits >> 16);
            bits = ((bits & 0x55555555u) << 1) | ((bits & 0xAAAAAAAAu) >> 1);
            bits = ((bits & 0x33333333u) << 2) | ((bits & 0xCCCCCCCCu) >> 2);
            bits = ((bits & 0x0F0F0F0Fu) << 4) | ((bits & 0xF0F0F0F0u) >> 4);
            bits = ((bits & 0x00FF00FFu) << 8) | ((bits & 0xFF00FF00u) >> 8);
            return new Vector2((float)i / n, bits * 2.3283064365386963e-10f);
        }
        //#endregion
    }
}
