// Ours (the World of Warcraft editor project): the sky drawn anew in our own client (OursSky.cpp,
// OursSkyColours.cpp), over all of the sky, in the place of the game's dome of colours and its clouds.
//
// THE COLOURS ARE THE ZONE'S OWN (the user's choice, 2026-10-16: "Zone colours, made smooth"): the picture at s0 is
// the game's own dome colours, as it works them out every frame, laid out smoothly around and up and down. Here they
// are read where the look meets the game's own dome (a sphere of 1 whose middle lies 0.707 below the eye), so that
// every colour stands at the height it stood at; what is new is that it is smooth, with a little noise against the
// steps of 8-bit colour; a glow round the sun in the zone's own sun colour; and clouds that drift, lit from the side
// the sun (by night the moon) is on, in the zone's own cloud colours, as thick as the zone's own cloud density.
// The sun and the moons are the game's, drawn before this (the stars are ours: below, "The night sky"): what this gives is added over them, as the
// game's dome is (its alpha the colours' own), and the clouds cover them by their alpha.
//
// Switches: VERTEX 1 the vertex shader (it hands on the way through the corner it is at), 0 the pixel shader.

#ifndef VERTEX
#define VERTEX 0
#endif

#if VERTEX

struct VertexIn
{
    float4 at : POSITION;                // where on the screen (already in clip space: the corners of the view)
    float3 way : TEXCOORD0;              // the way from the eye through that corner, in the world's axes
};

struct VertexOut
{
    float4 at : POSITION;
    float3 way : TEXCOORD0;
};

VertexOut main(VertexIn input)
{
    VertexOut output;
    output.at = input.at;
    output.way = input.way;
    return output;
}

#else

sampler2D colours : register(s0);        // the zone's sky colours: around (the way round, nothing to one) and up (the
                                         // angle from the top of the game's dome, to its horizon at a quarter circle)
float4 sun : register(c0);               // the way to the sun (by night the moon), and how much of it is up
float4 sunColour : register(c1);         // the zone's sun colour, and how strongly it glows
float4 cloudLit : register(c2);          // the clouds where the light falls (the zone's "cloud sun"), and how lit
float4 cloudBody : register(c3);         // their own colour (the zone's first cloud layer), and how much they cover
float4 cloudShade : register(c4);        // their shade (the zone's "cloud emissive"), and the storm
float4 settings : register(c5);          // the settings: the clouds' amount, their speed, the sun's glow
float4 clock : register(c6);             // seconds; the colour picture's size around and up
float4 night : register(c7);             // how much of the night's stars are out (the game's own star fade), and the
                                         // settings: the stars' brightness, the Milky Way's, how much they twinkle
float4 nightMore : register(c8);         // how many shooting stars (a setting), and nothing
float4 sphereX : register(c9);           // the turning sky of stars: the rows that take a way in the world's axes into
float4 sphereY : register(c10);          // the sky's own (its pole the z), turned by the hour as the night goes
float4 sphereZ : register(c11);

static const float PI = 3.14159265;
static const float HALF = 0.70710678;    // how far below the eye the middle of the game's dome lies (cos 45)

// The clouds: a layer of them with a thickness, overhead, stepped through. The eye is at height 0 and the layer lies
// from LAYER_LOW to LAYER_HIGH (in units of the layer's own; the world's size of it does not matter for a sky).
static const float LAYER_LOW = 1.0;
static const float LAYER_HIGH = 1.45;
static const float CLOUD_WIDE = 0.10;    // how large the clouds are across: the noise cube is 1 / this units wide
static const int STEPS = 9;              // steps through the layer for each spot of sky
static const int LIGHT_STEPS = 3;        // and from each, toward the light
static const float LIGHT_STEP = 0.09;
static const float THICK = 9.0;          // how much a unit of full cloud dims what is behind it
static const float THICK_LIGHT = 6.0;    // and the light that comes through it
static const float FAR_FADE = 0.035;     // clouds far off fade into the sky by so much a unit of distance
static const float GLOW_WIDE = 0.05;     // the sun's wide glow (the first make had 0.18 over a far wider part of the sky: a white blot
                                         // over a quarter of the screen, the game's own sun and glare being there besides), and
static const float GLOW_TIGHT = 0.22;    // its tight one

float hash(float2 p)
{
    float3 q = frac(p.xyx * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return frac((q.x + q.y) * q.z);
}

float noise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    float2 u = f * f * (3 - 2 * f);
    return lerp(lerp(hash(i), hash(i + float2(1, 0)), u.x), lerp(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

sampler3D cloudNoise : register(s1);     // red: heaped shapes (billowy cells in soft noise); green: finer cells

// How much cloud there is at a point of the layer: the shape, held to the layer's height (flat below, rounded above),
// less what the zone's cover leaves clear, and eaten at its edges by the finer cells.
float cloudAt(float3 at, float cover, float2 drift)
{
    float high = saturate((at.z - LAYER_LOW) / (LAYER_HIGH - LAYER_LOW));
    float3 q = float3(at.xy * CLOUD_WIDE + drift, at.z * 0.35);
    float shape = tex3Dlod(cloudNoise, float4(q, 0)).r;
    float rounded = saturate(high * 6.0) * saturate((1 - high) * 1.6);
    float there = saturate((shape * rounded - (1 - cover)) / max(cover, 0.08));
    float fine = tex3Dlod(cloudNoise, float4(q * 3.7 + float3(drift * 1.7, 0), 0)).g;
    return saturate(there - (1 - fine) * 0.45 * (1 - there));
}

// The same without the fine edges, for the way to the light (where they are not seen, and a third as many lookups).
float roughCloudAt(float3 at, float cover, float2 drift)
{
    float high = saturate((at.z - LAYER_LOW) / (LAYER_HIGH - LAYER_LOW));
    float shape = tex3Dlod(cloudNoise, float4(float3(at.xy * CLOUD_WIDE + drift, at.z * 0.35), 0)).r;
    return saturate((shape * saturate(high * 6.0) * saturate((1 - high) * 1.6) - (1 - cover)) / max(cover, 0.08));
}


// ---- The night sky (asked for 2026-10-16: "a night sky, with pretty stars during the night"). In place of the game's
// own stars (a model of a few hundred dots, Environments\Stars\stars.mdl, which is not drawn while these are on).

float hash3(float3 p)
{
    p = frac(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

// A star's colour by its warmth: most white to blue-white, some yellow, a few orange.
float3 starColour(float h)
{
    float3 warm = float3(1.0, 0.72, 0.45), white = float3(1.0, 0.96, 0.9), blue = float3(0.72, 0.82, 1.0);
    return h < 0.18 ? lerp(warm, white, h / 0.18) : lerp(white, blue, saturate((h - 0.18) / 0.82) * 0.85);
}

// One layer of stars: the sky (a way of the turning sky, "d") cut into the squares of a cube's six faces, "cells" of
// them along a face (each face's squares stretched by atan so that they are about as large near its corners as at
// its middle), and in a square a star by chance at a place of its own within it. Its light lies over a pixel or two
// ("pixel": how much of the sky one pixel takes) and, for the brightest, a soft halo. "more" is a share by which
// more of the squares have a star (the Milky Way's), "seed" keeps the layers apart.
float3 starLayer(float3 d, float cells, float share, float more, float dimmest, float brightest, float seed, float pixel, float twinkle,
                 float low, float clump)
{
    float3 a = abs(d);
    float3 n, t, b;
    float major;
    if (a.x >= a.y && a.x >= a.z) {
        n = float3(sign(d.x), 0, 0); t = float3(0, 1, 0); b = float3(0, 0, 1); major = a.x;
    } else if (a.y >= a.z) {
        n = float3(0, sign(d.y), 0); t = float3(1, 0, 0); b = float3(0, 0, 1); major = a.y;
    } else {
        n = float3(0, 0, sign(d.z)); t = float3(1, 0, 0); b = float3(0, 1, 0); major = a.z;
    }
    float2 uv = float2(dot(d, t), dot(d, b)) / major;
    float2 grid = (atan(uv) * (4 / PI) * 0.5 + 0.5) * cells;
    float2 cell = floor(grid);
    float3 key = float3(cell, dot(n, float3(1, 2, 3)) * 17 + seed);
    float there = hash3(key);
    // (Stars are not spread evenly: where the noise is high there are more, so that they gather in drifts.)
    float drifts = lerp(1, 0.35 + 1.3 * tex3Dlod(cloudNoise, float4(d * 2.3 + seed * 0.17, 0)).r, clump);
    if (there > saturate(share * drifts + more)) {
        return 0;
    }
    float2 place = cell + 0.2 + 0.6 * float2(hash3(key + 11.3), hash3(key + 27.1));
    float2 back = tan(((place / cells) * 2 - 1) * (PI / 4));
    float3 star = normalize(n + back.x * t + back.y * b);
    float apart = length(d - star);
    float shine = lerp(dimmest, brightest, pow(hash3(key + 5.7), 3));
    // It twinkles: two waves of its own, more the lower it stands (more air between).
    float phase = hash3(key + 3.9) * 6.283;
    float speed = 2.0 + 4.0 * hash3(key + 8.1);
    shine *= 1 + twinkle * (0.25 + 0.55 * low) * (0.6 * sin(clock.x * speed + phase) + 0.4 * sin(clock.x * speed * 2.31 + phase * 1.7));
    // The brighter, the larger it looks (as a bright star does to the eye), a pixel at the least.
    float wide = pixel * (0.8 + 0.55 * saturate(shine / 2.0));
    float light = exp(-(apart * apart) / (wide * wide));
    float halo = brightest > 1 ? exp(-apart / (pixel * 3.0)) * 0.08 * shine : 0;
    return starColour(hash3(key + 19.4)) * (light * shine + halo);
}

// The Milky Way: a band across the sky (round the great circle whose pole is "GALAXY_POLE"), clouded by the noise,
// brighter and warmer toward its heart, with lanes of dust along its middle; and how much of it is there at a way.
// (In the turning sky's axes: so placed that the band goes through the top of the sky at midnight, with its heart
// some 30 degrees up toward the east.)
static const float3 GALAXY_POLE = float3(-0.616, 0.287, 0.733);
static const float3 GALAXY_HEART = float3(0.543, 0.830, 0.131);
float band(float3 d)
{
    float across = dot(d, GALAXY_POLE);
    return exp(-across * across / 0.045);
}
float3 milkyWay(float3 d)
{
    float across = dot(d, GALAXY_POLE);
    float heart = pow(saturate(dot(d, GALAXY_HEART) * 0.5 + 0.5), 4);
    float wide = 0.13 + 0.14 * heart;
    float there = exp(-across * across / (wide * wide));
    float clouds = tex3Dlod(cloudNoise, float4(d * 1.3 + 0.37, 0)).r * 0.6 + tex3Dlod(cloudNoise, float4(d * 3.1 + 0.71, 0)).r * 0.4;
    float grain = tex3Dlod(cloudNoise, float4(d * 7.0, 0)).g;
    float glow = there * saturate(clouds * 1.6 - 0.25) * (0.6 + 0.4 * grain);
    // A wider, fainter haze about it, and a glow at the heart.
    glow += exp(-across * across / (wide * wide * 4)) * 0.18 + heart * there * 0.6;
    // The dust: dark lanes along its middle, ragged by the noise.
    float lane = exp(-across * across / 0.0025) * saturate(tex3Dlod(cloudNoise, float4(d * 2.2 + 0.13, 0)).r * 1.8 - 0.4);
    glow *= 1 - 0.75 * lane;
    float3 colour = lerp(float3(0.55, 0.62, 0.88), float3(1.0, 0.84, 0.64), saturate(heart * 1.5));
    return colour * glow * (0.45 + 0.55 * heart);
}

// Now and then a shooting star: a short streak across the upper sky, in the world's own axes (it is not of the turning
// sky). Time is cut into slots of SHOT_EVERY seconds, and in a slot there is one by chance ("often": the setting).
static const float SHOT_EVERY = 7.0;
static const float SHOT_TAKES = 0.8;
float3 shootingStar(float3 look, float pixel, float often)
{
    float slot = floor(clock.x / SHOT_EVERY);
    if (hash3(float3(slot, 4.1, 9.7)) > 0.22 * often) {
        return 0;
    }
    float since = clock.x - slot * SHOT_EVERY - hash3(float3(slot, 2.3, 1.1)) * (SHOT_EVERY - SHOT_TAKES);
    float done = since / SHOT_TAKES;
    if (done < 0 || done > 1) {
        return 0;
    }
    float round = hash3(float3(slot, 7.7, 3.3)) * 6.283;
    float up = 0.45 + 0.6 * hash3(float3(slot, 5.5, 8.8));
    float3 from = float3(cos(round) * cos(up), sin(round) * cos(up), sin(up));
    float turn = hash3(float3(slot, 1.9, 6.6)) * 6.283;
    float3 side = normalize(cross(from, float3(0, 0, 1)));
    float3 down = cross(side, from);
    float3 goes = normalize(side * cos(turn) + down * (0.4 + 0.6 * abs(sin(turn))));
    float3 head = normalize(from + goes * (0.05 + done * 0.3));
    float3 tail = normalize(from + goes * max(0.05 + done * 0.3 - 0.12, 0.0));
    // How far the look is from the streak between tail and head.
    float3 along = head - tail;
    float s = saturate(dot(look - tail, along) / max(dot(along, along), 1e-6));
    float apart = length(look - (tail + along * s));
    float wide = pixel * 1.1;
    float bright = sin(done * PI) * s * s * 1.8;
    return float3(1.0, 0.95, 0.85) * exp(-apart * apart / (wide * wide)) * bright;
}

float4 main(float3 way : TEXCOORD0, float2 pixel : VPOS) : COLOR0
{
    float3 look = normalize(way);
    // How much of the sky a pixel takes (outside all branches: the hardware works it out from its neighbours).
    float pixelWide = max(length(fwidth(look)) * 0.7071, 1e-5);

    // The zone's colours, where the look meets the game's own dome.
    float far = -HALF * look.z + sqrt(0.5 * look.z * look.z + 0.5);
    float fromTop = acos(saturate(far * look.z + HALF));
    float round = atan2(look.x, look.y) / (2 * PI);
    float4 own = tex2Dlod(colours, float4(round, saturate(fromTop / (0.25 * PI)), 0, 0));
    float3 sky = own.rgb * own.a;

    // The sun's glow, in the zone's own sun colour.
    float toward = saturate(dot(look, sun.xyz));
    float3 glow = sunColour.rgb * (sunColour.a * settings.z * sun.w) * (pow(toward, 24) * GLOW_WIDE + pow(toward, 300) * GLOW_TIGHT);

    // The clouds: as thick as the zone's own (more in a storm), stepped through, each step lit by how much cloud lies
    // between it and the light; their shade the sky's own colour there and the zone's cloud colour, their lit side
    // the zone's "cloud sun" colour; bright at their thin edges toward the sun.
    float storm = cloudShade.a;
    float cover = saturate(max(cloudBody.a, storm * 0.85) * settings.x);
    float clear = 1;                         // how much of what is behind still shows through
    float3 cloud = 0;
    if (look.z > 0.015 && cover > 0.001) {
        float2 drift = float2(0.0021, 0.0013) * clock.x * settings.y;
        float enter = LAYER_LOW / look.z, leave = min(LAYER_HIGH / look.z, enter + 3.0);
        float step = (leave - enter) / STEPS;
        float along = enter + step * hash(pixel + frac(clock.x) * 37);
        float3 shaded = lerp(cloudBody.rgb, sky, 0.45) + cloudShade.rgb * 0.25;
        float3 litBy = cloudLit.rgb * cloudLit.a * (0.55 + sun.w * 0.45);
        float forward = 0.7 + pow(toward, 5) * 0.8 + pow(toward, 40) * 1.2;    // light that comes through, toward the sun (halved: with the glow it made the sun a blot)
        [unroll] for (int i = 0; i < STEPS; ++i) {
            float3 at = look * along;
            float here = cloudAt(at, cover, drift);
            float toLight = 0;
            [unroll] for (int j = 0; j < LIGHT_STEPS; ++j) {
                toLight += roughCloudAt(at + sun.xyz * (LIGHT_STEP * (j + 0.5)), cover, drift);
            }
            float reached = exp(-toLight * LIGHT_STEP * THICK_LIGHT);
            float high = saturate((at.z - LAYER_LOW) / (LAYER_HIGH - LAYER_LOW));
            float3 colour = shaded * (0.65 + 0.35 * high) + litBy * reached * forward * (1 - exp(-here * 4));
            float taken = 1 - exp(-here * step * THICK);
            cloud += clear * taken * colour;
            clear *= 1 - taken;
            along += step;
        }
        // Far off they fade into the sky, and toward the horizon.
        float kept = exp(-enter * FAR_FADE) * smoothstep(0.015, 0.12, look.z);
        cloud *= kept;
        clear = 1 - (1 - clear) * kept;
    }
    float cloudy = 1 - clear;

    // The stars, where the night has them: less where the sky is bright (dusk, the moon's glow), fewer toward the
    // horizon, and behind the clouds.
    float3 stars = 0;
    float shown = night.x;
    float skyLight = dot(sky, float3(0.3, 0.55, 0.15));
    shown *= smoothstep(0.5, 0.06, skyLight) * smoothstep(-0.02, 0.18, look.z);
    // (By night "sun" is the moon: round it the stars are washed out.)
    shown *= 1 - 0.8 * pow(toward, 12) * sun.w;
    if (shown > 0.002) {
        float3 d = float3(dot(look, sphereX.xyz), dot(look, sphereY.xyz), dot(look, sphereZ.xyz));
        float low = 1 - saturate(look.z * 2);
        float inBand = band(d) * night.z;
        float twinkle = night.w;
        stars += starLayer(d, 110, 0.28, 0.55 * inBand, 0.10, 0.35, 1.0, pixelWide, twinkle, low, 1.0);
        stars += starLayer(d, 40, 0.50, 0.30 * inBand, 0.30, 0.95, 2.0, pixelWide, twinkle, low, 0.6);
        stars += starLayer(d, 13, 0.50, 0, 0.9, 3.0, 3.0, pixelWide, twinkle, low, 0);
        stars *= night.y;
        stars += milkyWay(d) * night.z * 0.2;
        stars += shootingStar(look, pixelWide, nightMore.x);
        stars *= shown;
    }


    // A little noise against the steps of 8-bit colour.
    float dither = (hash(pixel) - 0.5) / 255;
    // (What the clouds give is already weighed by how much of them each step is: what is behind shows through the rest.)
    return float4((sky + glow + stars) * clear + cloud + dither, cloudy);
}

#endif
