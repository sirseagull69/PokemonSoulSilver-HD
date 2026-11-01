#version 450

// Krater-Licht: Umgebungsverdeckung (SSAO) aus dem DS-Tiefenpuffer.
// Läuft im Final-Pass nach Kantenmarkierung/Nebel und dunkelt nur ab
// (Ausgabe schwarz, Deckkraft = Verdeckung). Stärke 0..100 kommt über
// pc.passIndex, 0 = Pass wird gar nicht ausgeführt.
//
// Gemessen wird pro gegenüberliegendem Stichproben-Paar die Krümmung der
// Tiefe: auf einer Ebene ist d = Mittel der beiden Nachbarn (kein Schatten),
// in einer Innenecke liegt d dahinter. Das Maß ist skalenfrei, funktioniert
// also mit Z- und W-Buffer. Große Sprünge (Silhouetten) werden verworfen.

layout(set = 0, binding = 3) uniform sampler2D AttrBuffer;
layout(set = 0, binding = 4) uniform sampler2D DepthBuffer;

layout(push_constant) uniform PushConsts
{
    uint width;
    uint height;
    uint clearColor;
    uint clearDepth;
    uint triangleCount;
    uint dispCnt;
    uint alphaRef;
    uint fogColor;
    uint fogOffset;
    uint fogShift;
    uint clearAttr;
    uint fogDensityPacked[9];
    uint edgeColorPacked[8];
    uint variantKey;
    uint passIndex;
    uint triangleBase;
    uint depthBlendMode;
} pc;

layout(location = 0) out vec4 oColor;

// 3 Paare pro Ring (je 60° versetzt), Ring 2 um 30° gedreht. Fest, damit nichts flimmert.
const vec2 kDirs[6] = vec2[6](
    vec2(1.000, 0.000), vec2(0.500, 0.866), vec2(-0.500, 0.866),
    vec2(0.866, 0.500), vec2(0.000, 1.000), vec2(-0.866, 0.500)
);

bool loadDepth(ivec2 c, ivec2 size, float farDepth, out float depth)
{
    if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, size)))
    {
        depth = 1.0;
        return false;
    }
    depth = texelFetch(DepthBuffer, c, 0).r;
    return depth < farDepth - 1e-6;
}

void main()
{
    float strength = float(min(pc.passIndex, 100u)) * 0.01;
    ivec2 size = ivec2(int(pc.width), int(pc.height));
    ivec2 coord = ivec2(gl_FragCoord.xy);

    float farDepth = min(float(pc.clearDepth & 0xFFFFFFu) * (1.0 / 16777216.0), 0.9999);
    float d = texelFetch(DepthBuffer, coord, 0).r;

    // Hintergrund (nichts gezeichnet) bekommt keinen Schatten.
    if (d >= farDepth - 1e-6)
    {
        oColor = vec4(0.0);
        return;
    }

    float scale = max(float(pc.width) / 256.0, 1.0);
    float occ = 0.0;
    float weight = 0.0;

    for (int k = 0; k < 6; k++)
    {
        float radius = (k < 3 ? 3.0 : 7.0) * scale;
        float w = k < 3 ? 1.0 : 0.6;
        ivec2 o = ivec2(round(kDirs[k] * radius));
        weight += w;

        float s1, s2;
        if (!loadDepth(coord + o, size, farDepth, s1) || !loadDepth(coord - o, size, farDepth, s2))
            continue;

        float a1 = abs(d - s1);
        float a2 = abs(d - s2);
        // Silhouette: ein Nachbar springt viel stärker als der andere -> ignorieren
        if (max(a1, a2) >= 6.0 * min(a1, a2) + 2e-5)
            continue;

        float delta = d - 0.5 * (s1 + s2);
        float r = delta / (0.5 * abs(s1 - s2) + abs(delta) + 1e-7);
        occ += w * smoothstep(0.15, 0.6, r);
    }

    float ao = clamp(occ / max(weight, 1e-6), 0.0, 1.0);
    ao = ao * ao * (3.0 - 2.0 * ao);
    oColor = vec4(0.0, 0.0, 0.0, ao * 0.8 * strength);
}
