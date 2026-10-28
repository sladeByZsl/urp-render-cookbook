// 盒体投影演示用的“房间”图案：墙面颜色只由世界坐标和朝向决定。（GLSL 版，对应 Ch08/RoomPattern.hlsl）
// C# 侧（BoxProjectionDemo.cs）有一份逐行对应的实现，用它生成房间中心的 cubemap，
// 这样 cubemap 里看到的墙和场景里真实的墙严格一致，误差只可能来自投影方式本身。
#ifndef COOKBOOK_CH08_ROOM_PATTERN_INCLUDED
#define COOKBOOK_CH08_ROOM_PATTERN_INCLUDED

// face：0=+X 墙 1=-X 墙 2=天花板 3=地面 4=+Z 墙 5=-Z 墙
vec3 RoomPattern(vec3 p, int face)
{
    vec3 c;
    vec2 w;
    if (face == 0)      { c = vec3(0.85, 0.42, 0.18); w = p.zy; }
    else if (face == 1) { c = vec3(0.12, 0.55, 0.55); w = p.zy; }
    else if (face == 2) { c = vec3(0.9, 0.9, 0.88);   w = p.xz; }
    else if (face == 3) { c = vec3(0.08, 0.08, 0.09); w = p.xz; }
    else if (face == 4) { c = vec3(0.7, 0.74, 0.82);  w = p.xy; }
    else                { c = vec3(0.45, 0.3, 0.65);  w = p.xy; }

    // 1 米网格线
    vec2 g = abs(fract(w + 0.5) - 0.5);
    if (min(g.x, g.y) < 0.025) c *= 0.3;
    // 墙上一条白色腰线（y 在 1.1~1.4 米），反射里错位时最显眼
    if (face != 2 && face != 3 && p.y > 1.1 && p.y < 1.4) c = vec3(1.0, 0.97, 0.9);
    return c;
}

int RoomFaceFromNormal(vec3 n)
{
    vec3 a = abs(n);
    if (a.x > a.y && a.x > a.z) return n.x > 0.0 ? 1 : 0;   // 法线朝 -X 的是 +X 墙（墙面朝向房间内部）
    if (a.y > a.z)              return n.y > 0.0 ? 3 : 2;
    return n.z > 0.0 ? 5 : 4;
}
#endif
