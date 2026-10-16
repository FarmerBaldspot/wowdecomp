// Ours (the World of Warcraft editor project): the sky drawn anew in our own client (OursSky.cpp,
// OursSkyColours.cpp), over all of the sky, in the place of the game's dome of colours and its clouds.
//
// THE COLOURS ARE THE ZONE'S OWN (the user's choice, 2026-10-16: "Zone colours, made smooth"): the picture at s0 is
// the game's own dome colours, as it works them out every frame, laid out smoothly around and up and down. Here they
// are read where the look meets the game's own dome (a sphere of 1 whose middle lies 0.707 below the eye), so that
// every colour stands at the height it stood at; what is new is that it is smooth, with a little noise against the
// steps of 8-bit colour; a glow round the sun in the zone's own sun colour; and clouds that drift, lit from the side
// the sun (by night the moon) is on, in the zone's own cloud colours, as thick as the zone's own cloud density.
// The sun, the moons and the stars are the game's, drawn before this: what this gives is added over them, as the
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


float4 main(float3 way : TEXCOORD0, float2 pixel : VPOS) : COLOR0
{
    float3 look = normalize(way);

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


    // A little noise against the steps of 8-bit colour.
    float dither = (hash(pixel) - 0.5) / 255;
    // (What the clouds give is already weighed by how much of them each step is: what is behind shows through the rest.)
    return float4((sky + glow) * clear + cloud + dither, cloudy);
}

#endif
