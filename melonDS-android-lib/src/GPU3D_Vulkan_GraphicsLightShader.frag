#version 450

// Krater-Licht: Umgebungsverdeckung (SSAO) aus dem DS-Tiefenpuffer.
// Läuft im Final-Pass nach Kantenmarkierung/Nebel und dunkelt nur ab
// (Ausgabe schwarz, Deckkraft = Verdeckung). Stärke 0..100 kommt über
// pc.passIndex, 0 = Pass wird gar nicht ausgeführt.

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

// 12 Richtungen, zwei Ringe. Feste Werte statt Rauschen, damit nichts flimmert.
const vec2 kDirs[12] = vec2[12](
    vec2( 1.000,  0.000), vec2( 0.500,  0.866), vec2(-0.500,  0.866),
    vec2(-1.000,  0.000), vec2(-0.500, -0.866), vec2( 0.500, -0.866),
    vec2( 0.866,  0.500), vec2( 0.000,  1.000), vec2(-0.866,  0.500),
    vec2(-0.866, -0.500), vec2( 0.000, -1.000), vec2( 0.866, -0.500)
);

float loadDepth(ivec2 c, ivec2 size)
{
    c = clamp(c, ivec2(0), size - ivec2(1));
    return texelFetch(DepthBuffer, c, 0).r;
}

void main()
{
    float strength = float(min(pc.passIndex, 100u)) * 0.01;
    ivec2 size = ivec2(int(pc.width), int(pc.height));
    ivec2 coord = ivec2(gl_FragCoord.xy);

    float d = loadDepth(coord, size);
    float farDepth = float(pc.clearDepth & 0xFFFFFFu) * (1.0 / 16777216.0);

    // Hintergrund (nichts gezeichnet) bekommt keinen Schatten.
    if (d >= 0.9999 || d >= farDepth - 1e-6)
    {
        oColor = vec4(0.0);
        return;
    }

    float scale = max(float(pc.width) / 256.0, 1.0);
    // Erlaubte Tiefendifferenz: kleiner Bereich = Ecken/Kontakt, großer Sprung = Silhouette (ignorieren)
    float minDelta = 0.0004 + d * 0.0006;
    float maxDelta = 0.02 + d * 0.04;

    float occ = 0.0;
    float weight = 0.0;
    for (int i = 0; i < 12; i++)
    {
        float radius = (i < 6 ? 3.0 : 7.0) * scale;
        ivec2 sc = coord + ivec2(round(kDirs[i] * radius));
        float sd = loadDepth(sc, size);
        if (sd >= farDepth - 1e-6)
            continue;
        float delta = d - sd; // > 0: Nachbar liegt näher an der Kamera
        float w = i < 6 ? 1.0 : 0.6;
        weight += w;
        if (delta > minDelta && delta < maxDelta)
        {
            // weich ein- und am Rand des Bereichs wieder ausblenden
            float t = (delta - minDelta) / (maxDelta - minDelta);
            occ += w * smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.6, 1.0, t));
        }
    }

    if (weight <= 0.0)
    {
        oColor = vec4(0.0);
        return;
    }

    float ao = clamp(occ / weight, 0.0, 1.0);
    ao = ao * ao * (3.0 - 2.0 * ao);
    oColor = vec4(0.0, 0.0, 0.0, ao * 0.55 * strength);
}
