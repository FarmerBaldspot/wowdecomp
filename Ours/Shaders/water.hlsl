// The game's water, made anew: vsLiquidWater and psLiquidWater of the 3.3.5a
// client (the vs_3_0 / ps_3_0 set), which draw every lake, river, sea and
// canal.
//
// The vertex shader does what the game's own does, and besides hands the
// pixel shader what it needs to know how the water is looked at and where a
// spot of it is: the way from the eye to the spot, the spot itself (in yards,
// fixed to the world, for the waves), the way to the sun and how high the
// eye is over the water, all in the water's own axes (two level ones and
// straight up). They ride in the halves of the two texture coordinates that
// the game's own leaves empty and in the second colour (which was the shine
// the game works out per corner). And it says where on the screen things are
// to be found in the frame as it was drawn before the water (five more
// texture coordinates): the spot itself, the far end of the line of sight
// as level water turns it back, and what a yard along each of the water's
// axes comes to there, so that the pixel shader can bend both by the waves.
//
// Compiled by make.py with:
//   VERTEX 1            the vertex shader; LAMPS 0 to 3: how many lights are near (the game has a shader for each)
//   AS_THE_GAMES 1      (vertex) exactly the game's own, for holding the two against each other
//   SCENE 1             (pixel) the frame as drawn so far is read (the project's program inside the game keeps it at stage 14)
//   PROBE 1             (pixel) no water: the screen shows what the game hands the shader, in twenty stripes, over and over
//   ONLY_STRIPE n       (pixel) one of those stripes over all of the picture, for the test bench
//   STRIPE              (pixel) how many pixels a stripe is wide

#ifndef LAMPS
#define LAMPS 0
#endif
#ifndef AS_THE_GAMES
#define AS_THE_GAMES 0
#endif
#ifndef PROBE
#define PROBE 0
#endif
#ifndef SCENE
#define SCENE 0
#endif
#ifndef ONLY_STRIPE
#define ONLY_STRIPE 99      // none (the compiler's "#if" takes -1 for more than 0)
#endif
#ifndef STRIPE
#define STRIPE 64
#endif

#if VERTEX

// What the game sets for the water's vertex shader (read out of its own).
float4 toScreen[4] : register(c0);       // c0 to c3: from the eye's space onto the screen
float4 fogNumbers : register(c4);        // clear = (depth * x + y) to the power z
float4 toEye[4] : register(c5);          // c5 to c8: from the water's own space into the eye's
float4 rippleAcross : register(c9);       // the ripple picture's coordinates: a matrix of two rows and a shift
float4 rippleDown : register(c10);
float4 rippleShift : register(c12);
float4 colourAcross : register(c13);      // the colour picture's
float4 colourDown : register(c14);
float4 colourShift : register(c16);
float4 sunTravels : register(c33);       // the way the sun's light goes, in the eye's space
float4 shade : register(c34);            // the light where the sun does not reach
float4 sunLight : register(c35);
float4 shineColour : register(c36);      // w: how tight the game's own shine is
float4 lamps[9] : register(c37);         // for each light near: where it is, its colour, how it fades

struct VertexIn
{
    float4 position : POSITION;
    float3 normal : NORMAL;
    float4 colour : COLOR0;
    float2 rippleAt : TEXCOORD0;
    float2 colourAt : TEXCOORD1;
};

struct VertexOut
{
    float4 position : POSITION;
    float4 light : COLOR0;
    float4 shine : COLOR1;
    float4 colourAt : TEXCOORD0;
    float4 rippleAt : TEXCOORD1;
    float clear : FOG;
#if !AS_THE_GAMES
    float4 onScreenAt : TEXCOORD2;       // where the spot is on the screen: across, down and the number both are divided by
    float4 mirrorAt : TEXCOORD3;         // where the line of sight ends up, turned back by level water and followed without end
    float4 acrossAt : TEXCOORD4;         // what a yard along each of the water's three axes comes to there
    float4 alongAt : TEXCOORD5;          // (the fourths of these four: the depth numbers, see the vertex shader's end)
    float4 upAt : TEXCOORD6;             // w: how high the spot is along the water's own up, for where it is in the world
#endif
};

// A way in the eye's space, as it lies on the screen (to be added to a spot's place there, or followed without end).
float3 onScreen(float3 way)
{
    return (way.x * toScreen[0] + way.y * toScreen[1] + way.z * toScreen[2]).xyw;
}

VertexOut main(VertexIn input)
{
    VertexOut output;
    float4 seen = input.position.x * toEye[0] + input.position.y * toEye[1] + input.position.z * toEye[2] + toEye[3];
    output.position = seen.x * toScreen[0] + seen.y * toScreen[1] + seen.z * toScreen[2] + seen.w * toScreen[3];
    output.rippleAt = float4(input.rippleAt.x * rippleAcross.xy + input.rippleAt.y * rippleDown.xy + rippleShift.xy, 0, 0);
    output.colourAt = float4(input.colourAt.x * colourAcross.xy + input.colourAt.y * colourDown.xy + colourShift.xy, 0, 0);
    output.clear = min(pow(max(seen.z * fogNumbers.x + fogNumbers.y, 0), fogNumbers.z), 1);

    float3 normal = input.normal.x * toEye[0].xyz + input.normal.y * toEye[1].xyz + input.normal.z * toEye[2].xyz;
    float3 lit = sunLight.rgb * saturate(dot(-sunTravels.xyz, normal)) + shade.rgb;
    for (int lamp = 0; lamp < LAMPS; ++lamp) {
        float3 toLamp = lamps[lamp * 3].xyz - seen.xyz;
        float away = length(toLamp);
        float3 fades = lamps[lamp * 3 + 2].xyz;
        lit += lamps[lamp * 3 + 1].rgb * saturate(dot(toLamp / away, normal)) / (fades.x + fades.y * away + fades.z * away * away);
    }
    output.light = float4(lit, 1) * input.colour;

#if AS_THE_GAMES
    float3 between = normalize(normalize(seen.xyz) + sunTravels.xyz);
    output.shine = float4(pow(max(dot(-between, normal), 0), shineColour.w) * shineColour.rgb, 1);
#else
    // The water's own axes: straight up, and two level ones.
    float3 up = input.normal;
    float3 other = lerp(float3(0, 0, 1), float3(1, 0, 0), step(0.9, abs(up.z)));
    float3 across = normalize(cross(other, up));
    float3 along = cross(up, across);
    // From the eye's space back into the water's: the matrix the other way round.
    float3 fromEye = float3(dot(toEye[0].xyz, seen.xyz), dot(toEye[1].xyz, seen.xyz), dot(toEye[2].xyz, seen.xyz));
    float3 toSun = -float3(dot(toEye[0].xyz, sunTravels.xyz), dot(toEye[1].xyz, sunTravels.xyz), dot(toEye[2].xyz, sunTravels.xyz));
    // The way from the eye to the spot, its level part; the spot itself, in yards and fixed to the world, for the
    // waves; and in the second colour the way to the sun (its level part) and how high the eye is over the water.
    output.colourAt.zw = float2(dot(fromEye, across), dot(fromEye, along));
    output.rippleAt.zw = float2(dot(input.position.xyz, across), dot(input.position.xyz, along));
    output.shine = float4(dot(toSun, across) * 0.5 + 0.5, dot(toSun, along) * 0.5 + 0.5, saturate(-dot(fromEye, up) / 1000), 1);
    // For reading the frame as drawn so far ("normal" is the water's "up" in the eye's space).
    // The screen keeps of everything drawn its depth, (far * x + y) / (far * z + w) with four numbers, "far" being
    // how far ahead of the eye it is: handed on, so that the pixel shader can turn a depth back into yards, as the
    // fourths of the next four (a vertex shader gives out eleven things at the most, and that is what there are).
    output.onScreenAt = float4(output.position.xyw, toScreen[2].z);
    output.mirrorAt = float4(onScreen(seen.xyz - 2 * dot(seen.xyz, normal) * normal), toScreen[3].z);
    output.acrossAt = float4(onScreen(across.x * toEye[0].xyz + across.y * toEye[1].xyz + across.z * toEye[2].xyz), toScreen[2].w);
    output.alongAt = float4(onScreen(along.x * toEye[0].xyz + along.y * toEye[1].xyz + along.z * toEye[2].xyz), toScreen[3].w);
    output.upAt = float4(onScreen(normal), dot(input.position.xyz, up));
#endif
    return output;
}

#else

// What the two pictures are was measured in the game (the stripes below, 2026-10-13):
sampler2D colourPicture : register(s0);  // the water's colour, which the game makes for the place and the hour; its alpha: how opaque
sampler2D ripplePicture : register(s1);  // the game's animated pale ripples (lake_a and its like): black, the pattern is in its ALPHA
float4 fogColour : register(c4);
float4 clock : register(c200);           // from the project's program inside the game: x the seconds gone by. All 0 without it: nothing moves
float4 screen : register(c201);          // from the same: one over the width and the height of the frame it keeps; z: 1 if it is there; w: 1 if its depth is

struct PixelIn
{
    float4 light : COLOR0;       // the light on the water times the water's own colour; alpha: how opaque the game wants it
    float4 more : COLOR1;        // r, g: the way to the sun, its level part; b: how high the eye is over the water, in thousands of yards
    float4 colourAt : TEXCOORD0; // xy: where in the colour picture; zw: the way from the eye to the spot, its level part, in yards
    float4 rippleAt : TEXCOORD1; // xy: where in the ripple picture; zw: the spot itself, in yards, fixed to the world
    float clear : FOG;           // 1 near; 0 where the fog has taken everything
    float4 onScreenAt : TEXCOORD2;       // where the spot is on the screen: across, down and the number both are divided by
    float4 mirrorAt : TEXCOORD3;         // where the line of sight ends up, turned back by level water and followed without end
    float4 acrossAt : TEXCOORD4;         // what a yard along each of the water's three axes comes to there
    float4 alongAt : TEXCOORD5;          // (the fourths of these four: the depth numbers, see the vertex shader's end)
    float4 upAt : TEXCOORD6;             // w: how high the spot is along the water's own up
#if PROBE || ONLY_STRIPE < 99
    float2 onScreen : VPOS;
#endif
};

// --- the look ------------------------------------------------------------------
// Water as glass that moves. It has waves of its own: a picture of rippled
// water (the project's, made by client\gfx\textures\make_waves.py; the
// project's program inside the game puts it at stage 13), laid over the water
// several times, at other sizes, turned other ways and each drifting its own
// way. Everything else follows from the waves:
// - it is seen through: what lies under it is read from the frame as it was
//   drawn before the water (stage 14) at a place bent by the wave, with the
//   web of light on it that waves throw on a bed; the more water the look
//   goes through, the more of the water's own colour (the game's, for the
//   place and the hour) and the less red;
// - it mirrors, little from above and nearly all at a flat angle: what is far
//   away, read from that same frame where the line of sight ends up when the
//   wave turns it back, and where that is not on the screen a sky made of the
//   fog's colour; and the sun in it as glitter.
// The game's own pale flecks are not used. Without the project's program in
// the game there is no picture of waves, no clock and no frame to read: this
// look is for there. Where only the frame is missing (SCENE 0, or it is not
// there this frame), the water is laid over what is behind it by its alpha,
// unbent.
sampler2D wavePicture : register(s13);   // red, green: the tilt of the water; blue: its height; alpha: the web of light
sampler2D scenePicture : register(s14);  // the frame as it was drawn before the water
sampler2D depthPicture : register(s15);  // and the depth the screen keeps of everything in it, if screen.w is 1
float4 dials[8] : register(c203);       // the dials an addon sets: [1].x foam, [1].y the waves' height, [1].w the web of light,
                                        // [5].x the foam's width, [5].y how clear the water is, [5].z how much it mirrors, [5].w the sun's glitter
float4 depthPart : register(c202);       // the game keeps its depths in a part of nothing-to-one: where that begins, and one over how long it is
// From our own client (OursFoam.cpp, OursWater.cpp): where the world is solid around the camera, seen from above, in
// squares of half a yard: for each square two stretches of height (low, high; none: low above high) at which
// something solid is, counted from solidPlace.w. That is the world's own collision, not the screen: what stands
// between the camera and the water is none of it.
sampler2D solidPicture : register(s12);
float4 solidPlace : register(c219);      // where the map begins (the world's x, y), one over how far it reaches, the height its numbers are counted from
float4 toWorldX : register(c220);        // from the water's own space into the world's, a row for each of the world's x, y and z
float4 toWorldY : register(c221);
float4 toWorldZ : register(c222);
float4 solidThere : register(c223);      // x: 1 if the map is there
#ifndef SHOW
#define SHOW 0                           // 1: the waves alone, as the tilt they give; 2: the web of light alone; 3: how much water is looked through; 4: the foam
#endif

static const float SLOPE_RANGE = 3.5;    // what the wave picture's tilts go up to: as in make_waves.py
static const float WAVES = 1.0;          // all the layings of the wave picture (below) made steeper or gentler together

static const float BEND = 1.0;           // what lies under the water is seen moved by the tilt times so many yards
static const float3 SWALLOWED = float3(0.30, 0.11, 0.08);  // how much red, green and blue light from below a yard of water swallows
                                         // (it was a third of this: the lake bed's weed showed through far out, as stains)
static const float WATER_GUESSED = 4.0;  // where the depth is not known: the water is taken to be so many yards deep
static const float SHORE_SOFT = 0.35;    // the water comes in over so many yards of itself at its edge: no hard line
static const float FOAM_WIDE = 2.4;      // foam where the look goes through less than about so many yards of water,
static const float FOAM_THICK = 0.88;    // this much of it white,
static const float FOAM_LAPS = 0.22;     // and its edge laps in and out by this share of that width
static const float COLOUR_GAIN = 1.9;    // the water's own colour, made this much brighter than the game's dark picture of it
static const float OWN_HUE = 0.45;       // how much of the light's hue that colour takes (the rest: only how bright the light is)
static const float WAVE_SHADE = 2.0;     // how much a wave that faces the sun is brighter, and one that faces away darker
static const float MIRROR_LEAST = 0.06;  // how much it mirrors seen from right above
static const float MIRROR_RISE = 3.2;    // how late the mirror comes in as the look gets flatter (higher: later)
static const float MIRROR_BEND = 0.5;    // how much of the waves' bending of the mirror image is shown (1: all of it)
static const int TRUE_STEPS = 28;        // the true mirror: so many steps along the turned-back line of sight,
static const float TRUE_FIRST = 0.25;    // the first this many yards out, each this much longer than the one before
static const float TRUE_GROWS = 1.28;    // (to some 200 yards),
static const float TRUE_THICK = 0.25;    // and what the line passes this share of its length behind is taken to be behind it, not met
static const float SKY_BRIGHT = 1.35;    // the made-up sky in the mirror, against the fog's colour
static const float SUN_SHARP = 520.0;    // the sun's own image on the waves: how small,
static const float SUN_BRIGHT = 9.0;     // and how bright
static const float SUN_GLOW = 0.6;       // the glow around it
static const float WEB_ACROSS = 9.0;     // the web of light: the wave picture is so many yards across for it,
static const float WEB_SWAY = 5.0;       // it sways with the waves: moved by the tilt times so many yards,
static const float WEB_LIGHT = 0.42;     // and this much of the bed's light is gathered into it (0: none, even light; 1: all)
// Without the frame to read:
static const float CLEAR_ABOVE = 0.40;   // seen from right above, the water is this much of how opaque the game has it,
static const float CLEAR_ASLANT = 0.95;  // and seen along its surface this much

// One laying of the wave picture: so many yards across, turned (a unit vector:
// where the picture's own "across" points on the water), drifting so many of
// its widths a second along that and to its side, and this steep. Gives the
// tilt of the water at the spot, in the water's own two level axes. Far away
// (so many of its widths) a laying is left out: it would only be grain. (The
// clock starts anew every hour: a drift with two decimals goes on without a
// jump.)
float2 laid(float2 spot, float away, float across, float2 turned, float2 drift, float steep)
{
    float2 side = float2(-turned.y, turned.x);
    float2 at = float2(dot(spot, turned), dot(spot, side)) / across - drift * clock.x;
    float2 read = (tex2D(wavePicture, at).rg - 0.50196) * (SLOPE_RANGE * 2.008);
    return (turned * read.x + side * read.y) * (steep * WAVES * saturate(1.6 - away / (across * 12)));
}

float2 tiltAt(float2 spot, float away)
{
    float2 tilt = laid(spot, away, 34.0, float2(0.966, 0.259), float2(0.03, 0.00), 0.030);  // long, slow ones
    tilt += laid(spot, away, 15.0, float2(0.819, -0.574), float2(0.04, 0.01), 0.040);       // the waves that are seen most, two layings
    tilt += laid(spot, away, 12.1, float2(0.423, 0.906), float2(0.05, -0.01), 0.035);       // that cross
    tilt += laid(spot, away, 6.3, float2(0.940, 0.342), float2(0.07, 0.02), 0.035);         // ripples, two layings
    tilt += laid(spot, away, 5.1, float2(-0.174, 0.985), float2(0.09, -0.02), 0.030);
    tilt += laid(spot, away, 2.3, float2(0.707, -0.707), float2(0.13, 0.03), 0.022);        // and the finest, which only show near
    return tilt * dials[1].y;
}

// The web of light on a bed: the wave picture's alpha, which is a quarter where the light is as without waves.
// Two layings of it, the second larger and fainter, each drifting its own way. 1: as much light as without waves.
float webAt(float2 spot)
{
    float one = tex2D(wavePicture, spot / WEB_ACROSS + float2(0.02, 0.01) * clock.x).a;
    float other = tex2D(wavePicture, float2(spot.y, -spot.x) / (WEB_ACROSS * 2.3) + float2(-0.01, 0.01) * clock.x).a;
    return min(one * 4.0 * (0.6 + other * 1.6), 2.4);         // (not brighter than this: under a low sun it came out as veins of gold)
}

// The sky in a direction, as far as it can be told here: the fog's colour along the horizon, deeper overhead.
float3 skyAt(float3 way)
{
    float3 above = fogColour.rgb * float3(0.55, 0.72, 1.05) + float3(0.02, 0.05, 0.11);
    return lerp(fogColour.rgb, above, pow(saturate(way.z), 0.55)) * SKY_BRIGHT;
}

// A place in the kept frame, from a place on the screen as the vertex shader gives it.
float2 inFrame(float3 at)
{
    return at.xy / at.z * float2(0.5, -0.5) + 0.5 + screen.xy * 0.5;
}

// How far ahead of the eye what was drawn at a place of the kept frame is, in yards.
float farAt(float2 place, float4 numbers)
{
    float depth = (tex2Dlod(depthPicture, float4(place, 0, 0)).r - depthPart.x) * depthPart.y;
    float under = depth * numbers.z - numbers.x;
    return abs((numbers.y - depth * numbers.w) / (abs(under) < 0.0000001 ? 0.0000001 : under));    // (ahead may count below nothing in the eye's space)
}

// The true mirror: from the spot (on the screen as the vertex shader gives it) along "way" (what a yard of the
// turned-back line of sight comes to on the screen), in longer and longer steps, until what the kept frame shows at
// a step lies before it: then the line has met that, and the meeting is closed in on. A line that comes out behind
// something by much has passed behind it, and one that leaves the frame has met nothing it can show: x 0 then.
// Gives in xy the place in the frame, in z how sure (faded at the frame's edges and far out).
float3 trueMirror(float3 start, float3 way, float4 numbers)
{
    // (No "break" in the loop: the compiler made each one a test of a number against itself, which never breaks,
    // and the walk ran on past every meeting. A flag says whether it goes on.)
    float before = 0, now = TRUE_FIRST, going = 1, met = 0, metBefore = 0, metNow = 0;
    [loop] for (int i = 0; i < TRUE_STEPS; ++i) {
        if (going > 0.5) {
            float3 at = start + way * now;
            float2 place = inFrame(at);
            float gone = (at.z * start.z <= 0.00000001 || place.x < 0 || place.x > 1 || place.y < 0 || place.y > 1) ? 1 : 0;
            float behind = gone > 0.5 ? 0 : abs((at.z - numbers.w) / numbers.z) - farAt(place, numbers);
            if (gone > 0.5) {
                going = 0;
            } else if (behind > 0) {
                going = 0;
                met = behind > max(0.6, now * TRUE_THICK) ? 0 : 1;
                metBefore = before;
                metNow = now;
            } else {
                before = now;
                now *= TRUE_GROWS;
            }
        }
    }
    if (met < 0.5)
        return 0;
    // Closed in on between the last step before the meeting and the one that met.
    float near = metBefore, far = metNow;
    [unroll] for (int k = 0; k < 5; ++k) {
        float middle = (near + far) * 0.5;
        float3 there = start + way * middle;
        float behindThere = abs((there.z - numbers.w) / numbers.z) - farAt(inFrame(there), numbers);
        far = behindThere > 0 ? middle : far;
        near = behindThere > 0 ? near : middle;
    }
    float2 place = inFrame(start + way * far);
    float edge = saturate(min(min(place.x, 1 - place.x), min(place.y, 1 - place.y)) / 0.06);
    return float3(place, edge * saturate(1.5 - far / 160));
}

// Does something stand out of the water at a spot that lies so many yards from this one, along the water's own two
// axes? 1 if so. (What is seen there lies before the water's level; but not far before it: that would be something
// between the eye and the water, which is none of the water's affair.)
float standsOut(float3 here, float3 across, float3 along, float4 numbers, float2 by, float aslant)
{
    float3 at = here + by.x * across + by.y * along;
    float before = abs((at.z - numbers.w) / numbers.z) - farAt(inFrame(at), numbers);
    return step(0.02, before) * step(before * aslant, 2.5 + 2 * length(by));
}

// How much of a ring around this spot, so many yards wide, stands out of the water: nothing to one. Eight spots of
// the ring are looked at, the ring turned by "turn" (a sine and a cosine) so that neighbours look elsewhere.
float ringOut(float3 here, float3 across, float3 along, float4 numbers, float wide, float2 turn, float aslant)
{
    float2 a = turn * wide, b = float2(-turn.y, turn.x) * wide, c = (a + b) * 0.7071, d = (a - b) * 0.7071;
    return (standsOut(here, across, along, numbers, a, aslant) + standsOut(here, across, along, numbers, -a, aslant)
          + standsOut(here, across, along, numbers, b, aslant) + standsOut(here, across, along, numbers, -b, aslant)
          + standsOut(here, across, along, numbers, c, aslant) + standsOut(here, across, along, numbers, -c, aslant)
          + standsOut(here, across, along, numbers, d, aslant) + standsOut(here, across, along, numbers, -d, aslant)) / 8;
}

// Where a spot of the water is in the world. (Level water: its own "across" is -y, its "along" +x; see the vertex
// shader.)
float3 inWorld(float2 spot, float high)
{
    float4 own = float4(spot.y, -spot.x, high, 1);
    return float3(dot(toWorldX, own), dot(toWorldY, own), dot(toWorldZ, own));
}

// The two stretches of height at which the world is solid at a place, in the world's own heights.
float4 solidAt(float2 place)
{
    return tex2Dlod(solidPicture, float4((place - solidPlace.xy) * solidPlace.z, 0, 0)) + solidPlace.w;
}

// How far within the map a place lies, nothing at its edge to one from 16 yards in.
float onTheMap(float2 place)
{
    float2 at = (place - solidPlace.xy) * solidPlace.z;
    return saturate(min(min(at.x, 1 - at.x), min(at.y, 1 - at.y)) / (16 * solidPlace.z)) * solidThere.x;
}

// Does something solid reach up through the water's level at a place? 1 where it does, less and less for what lies
// just under it (nothing from a quarter of a yard down), so that a flat bank under shallow water is not all of it
// "shore" with a hard edge where it ends (the first make took 0.3 above to 0.1 below as all or nothing).
float solidCrosses(float2 place, float level)
{
    float4 s = solidAt(place);
    float gap1 = s.x <= s.y ? max(max(s.x - level, level - s.y), 0) : 100;
    float gap2 = s.z <= s.w ? max(max(s.z - level, level - s.w), 0) : 100;
    return saturate(1 - min(gap1, gap2) / 0.25);
}

// How far down it is from the water's level to what is solid under it, straight down (very far where nothing is).
float bedBelow(float2 place, float level)
{
    float4 s = solidAt(place);
    float top = -10000;
    top = (s.y < level + 0.05 && s.x <= s.y) ? max(top, s.y) : top;
    top = (s.w < level + 0.05 && s.z <= s.w) ? max(top, s.w) : top;
    return max(level - top, 0);
}

// How much of a ring around a place in the world, so many yards wide, has something solid reaching up through the
// water: nothing to one. The camera has no part in it.
float ringCrosses(float3 at, float wide, float2 turn)
{
    float2 a = turn * wide, b = float2(-turn.y, turn.x) * wide, c = (a + b) * 0.7071, d = (a - b) * 0.7071;
    return (solidCrosses(at.xy + a, at.z) + solidCrosses(at.xy - a, at.z) + solidCrosses(at.xy + b, at.z) + solidCrosses(at.xy - b, at.z)
          + solidCrosses(at.xy + c, at.z) + solidCrosses(at.xy - c, at.z) + solidCrosses(at.xy + d, at.z) + solidCrosses(at.xy - d, at.z)) / 8;
}

float4 main(PixelIn input) : COLOR0
{
    float4 colour = tex2D(colourPicture, input.colourAt.xy);
    float4 ripple = tex2D(ripplePicture, input.rippleAt.xy);
    float3 fromEye = float3(input.colourAt.zw, -input.more.b * 1000);
    float away = length(fromEye);
    float3 toEye = -fromEye / away;
    float2 sunLevel = input.more.rg * 2 - 1;
    float3 toSun = float3(sunLevel, sqrt(saturate(1 - dot(sunLevel, sunLevel))));
    float2 spot = input.rippleAt.zw;

    float4 farNumbers = float4(input.onScreenAt.w, input.mirrorAt.w, input.acrossAt.w, input.alongAt.w);
    float2 tilt = tiltAt(spot, away);
    float3 surface = normalize(float3(-tilt, 1));
    float3 sunColour = input.light.rgb / max(max(input.light.r, input.light.g), max(input.light.b, 0.001));

    // How much it mirrors; the sky and the sun in the mirror.
    float mirror = saturate((MIRROR_LEAST + (1 - MIRROR_LEAST) * pow(1 - saturate(dot(toEye, surface)), MIRROR_RISE)) * dials[5].z);
    float3 back = reflect(-toEye, surface);
    back.z = abs(back.z);
    float3 sky = skyAt(back);
    float toward = saturate(dot(back, toSun));
    float3 sun = sunColour * (pow(toward, SUN_SHARP) * SUN_BRIGHT + pow(toward, 24) * SUN_GLOW) * (saturate(toSun.z * 6 + 0.3) * dials[5].w);

    // Its own colour, lit by how the wave faces the sun.
    float bright = dot(input.light.rgb, float3(0.30, 0.59, 0.11));
    float facing = saturate(1 + (dot(surface, toSun) - toSun.z) * WAVE_SHADE);
    float3 body = colour.rgb * lerp(bright.xxx, input.light.rgb, OWN_HUE) * (COLOUR_GAIN * facing);
    float thick = colour.a * input.light.a;                  // how opaque the game has the water here
    float web = lerp(1, webAt(spot + tilt * WEB_SWAY), WEB_LIGHT * dials[1].w * saturate(1.3 - away / 90));     // the light on the bed, against even light

    // Without the frame to read: laid over what is behind by its alpha.
    float opaque = saturate(thick * lerp(CLEAR_ASLANT, CLEAR_ABOVE, pow(saturate(toEye.z), 0.8)));
    float through = (1 - mirror) * (1 - opaque);
    float3 laidOn = (sky + sun) * mirror + body * opaque * (1 - mirror) + sunColour * (saturate(web - 1) * 0.3 * through);
    float4 result;
    result.a = saturate(max(1 - through, max(laidOn.r, max(laidOn.g, laidOn.b))));
    result.rgb = laidOn / max(result.a, 0.001);
#if SCENE
    // With it. How much water the look goes through here: from how far the water is and how far what lies behind it.
    float3 leaning = tilt.x * input.acrossAt.xyz + tilt.y * input.alongAt.xyz;
    float waterFar = abs((input.onScreenAt.z - farNumbers.w) / farNumbers.z);
    float aslant = away / max(waterFar, 0.01);                // yards of the look for each yard straight ahead
    float2 here = inFrame(input.onScreenAt.xyz);
    float water = lerp(WATER_GUESSED / max(toEye.z, 0.16), max(farAt(here, farNumbers) - waterFar, 0) * aslant, screen.w);
    // What lies under the water: read where the wave bends the look to (less at the water's very edge). But what
    // stands in front of the water is not seen through it: then it is read unbent.
    float2 bent = inFrame(input.onScreenAt.xyz - leaning * (BEND * saturate(water / 1.5)));
    float bentFar = farAt(bent, farNumbers);
    float behind = lerp(1, step(waterFar, bentFar), screen.w);
    bent = lerp(here, bent, behind);
    water = lerp(water, lerp(water, max(bentFar - waterFar, 0) * aslant, behind), screen.w);
    float3 under = tex2Dlod(scenePicture, float4(bent, 0, 0)).rgb;
    float3 kept = exp(-SWALLOWED * (water * thick / max(dials[5].y, 0.05)));
    float3 seenThrough = under * lerp(1, web, saturate(water / 1.0)) * kept + body * (1 - kept);
    // What is far away, mirrored: read where the line of sight ends up, turned back by the tilted water.
    float3 turned = input.mirrorAt.xyz + (leaning * (2 * fromEye.z) + input.upAt.xyz * (2 * dot(tilt, fromEye.xy))) * MIRROR_BEND;
    float2 place = inFrame(float3(turned.xy, max(turned.z, 0.0001)));
    float inside = min(min(place.x, 1 - place.x), min(place.y, 1 - place.y));
    float there = saturate(inside / 0.06) * step(0.0001, turned.z);
    float3 mirrored = lerp(sky, tex2Dlod(scenePicture, float4(saturate(place), 0, 0)).rgb, there);
    // And what is near, where the turned-back line of sight meets it: a post meets its own image at its foot, a
    // wall or a boat stands on its own. (Before, only what is far away was mirrored right, and near things came out
    // as pale columns that did not meet them.) Where it meets nothing it can show, the far mirror as it was.
    if (screen.w > 0.5) {
        float3 way = back.x * input.acrossAt.xyz + back.y * input.alongAt.xyz + back.z * input.upAt.xyz;
        float3 met = trueMirror(input.onScreenAt.xyz, way, farNumbers);
        mirrored = lerp(mirrored, tex2Dlod(scenePicture, float4(met.xy, 0, 0)).rgb, met.z);
    }
    mirrored += sun;
    float edge = saturate(water / SHORE_SOFT);                // the water comes in softly at its edge
    float3 whole = lerp(seenThrough, mirrored, mirror * edge);
    // Foam: around what stands out of the water (a shore, a wall, a post, somebody wading), as far from it as
    // FOAM_WIDE says, and where the water is thin. How near such a thing is: how much of two rings around the spot
    // stands out of the water. Thick at the very edge and thinning out from it; broken up into lace by the wave
    // picture's heights (three layings, drifting: a coarse one that still shows from afar, two finer); and with
    // lines that run out from the edge, as small waves lap.
    float coarse = tex2D(wavePicture, spot / 11.0 + tilt * 0.3 + float2(0.02, 0.01) * clock.x).b;
    float fine = tex2D(wavePicture, spot / 3.1 + tilt * 0.6 + float2(0.03, 0.02) * clock.x).b
               + tex2D(wavePicture, float2(-spot.y, spot.x) / 1.3 - float2(0.02, 0.05) * clock.x).b - 1;
    // (Far off the fine layings are only grain, which flickers as the camera moves: they go, the coarse one stays.)
    float lace = saturate((coarse - 0.5) * 3.0 + fine * 2.2 * (1 - smoothstep(25, 70, away)) + 0.5);
    float2 turn;
    sincos(fine * 9.0 + coarse * 5.0, turn.x, turn.y);
    // Never narrower than about 4 yards in 100 of distance: far off a band of 2.4 yards is a hairline a spot or two wide
    // that flickers as the camera moves.
    float reach = max(FOAM_WIDE * max(dials[5].x, 0.05), away * 0.04) * (1 - FOAM_LAPS + FOAM_LAPS * sin(clock.x * 1.1 + coarse * 12));
    // Where our client has the solid world around the camera (all of what is near), the rings and how thin the water
    // is are taken from that: the world's own shapes, straight down from the spot, whatever the camera sees. Beyond
    // it, and where it is not there, from the screen as before; the two blend over 16 yards at its edge.
    float3 inTheWorld = inWorld(spot, input.upAt.w);
    float mapped = onTheMap(inTheWorld.xy);
    float byRings = ringOut(input.onScreenAt.xyz, input.acrossAt.xyz, input.alongAt.xyz, farNumbers, reach * 0.42, turn, aslant) * 1.25
                  + ringOut(input.onScreenAt.xyz, input.acrossAt.xyz, input.alongAt.xyz, farNumbers, reach * 0.95, turn.yx, aslant) * 0.9;
    float thin = water * lerp(1, toEye.z, 0.5);
    float byWorld = ringCrosses(inTheWorld, reach * 0.42, turn) * 1.25 + ringCrosses(inTheWorld, reach * 0.95, turn.yx) * 0.9;
    byRings = lerp(byRings * screen.w, byWorld, mapped);
    // (How thin the water is counts by the screen only: by the world, a flat bank under shallow water was all foam,
    // ending in a straight line where it dropped off. There the foam is by how near the waterline is, and nothing
    // else.)
    thin = lerp(lerp(reach, thin, screen.w), reach * 2, mapped);
    float inFoam = saturate(max(1 - thin / (reach * 0.5), byRings * 1.1 - 0.14));  // 1 at the very edge, nothing where the foam ends (and none for a leaf or two)
    float laps = saturate(sin(inFoam * 14.0 + clock.x * 2.0 + coarse * 9) * 0.8 - 0.2);
    float foam = saturate(inFoam * inFoam * 1.2 + (inFoam * 1.7 - lace) * 1.4 + laps * inFoam * 0.5) * saturate(inFoam * 5) * max(screen.w, mapped) * dials[1].x;
    float3 foamColour = saturate(lerp(bright.xxx, input.light.rgb, 0.5) * 1.15 + 0.05);
    whole = lerp(whole, foamColour, saturate(foam) * FOAM_THICK);
    result = lerp(result, float4(whole, 1), screen.z);
#if SHOW == 5
    { float raw = tex2Dlod(depthPicture, float4(here, 0, 0)).r;
      result = float4(raw > 0.99995 ? 0.3 : 0, saturate((raw - 0.98) * 50) * 0.3, saturate(raw) * 0.3, 1); }
#elif SHOW == 3
    result = float4(saturate(water / 20).xxx, 1);
#elif SHOW == 4
    result = float4(foam.xxx, 1);
#endif
#endif
    result.rgb = lerp(fogColour.rgb, result.rgb, input.clear);
#if SHOW == 1
    result = float4(tilt * 2 + 0.5, 0.5, 1);
#elif SHOW == 2
    result = float4(web.xxx * 0.4, 1);
#endif

#if PROBE || ONLY_STRIPE < 99
    // What the game hands the shader, a stripe each, over and over across the screen.
#if ONLY_STRIPE < 99
    float stripe = ONLY_STRIPE;
#else
    float stripe = floor(input.onScreen.x / STRIPE);
    stripe -= 20 * floor(stripe / 20);
#endif
    float4 shown = float4(0, 0, 0, 1);
    if (stripe < 0.5)                    // 0: a marker to count the stripes from
        shown.rgb = frac(input.onScreen.y / (STRIPE * 0.5)) < 0.5 ? float3(1, 0, 1) : float3(0, 1, 0);
    else if (stripe < 1.5) shown.rgb = input.light.rgb;                               // 1: the first colour
    else if (stripe < 2.5) shown.rgb = input.light.aaa;                               // 2: its alpha
    else if (stripe < 3.5) shown.rgb = colour.rgb;                                    // 3: the colour picture
    else if (stripe < 4.5) shown.rgb = colour.aaa;                                    // 4: its alpha
    else if (stripe < 5.5) shown.rgb = ripple.rgb;                                    // 5: the ripple picture
    else if (stripe < 6.5) shown.rgb = ripple.aaa;                                    // 6: its alpha
    else if (stripe < 7.5) shown.rgb = float3(frac(input.rippleAt.xy), 0);            // 7: where in the ripple picture, over and over
    else if (stripe < 8.5)                                                            // 8: where in the colour picture, across: red beyond 1, blue below 0
        shown.rgb = input.colourAt.x > 1 ? float3(1, 0, 0) : input.colourAt.x < 0 ? float3(0, 0, 1) : input.colourAt.xxx;
    else if (stripe < 9.5)                                                            // 9: and down
        shown.rgb = input.colourAt.y > 1 ? float3(1, 0, 0) : input.colourAt.y < 0 ? float3(0, 0, 1) : input.colourAt.yyy;
    else if (stripe < 10.5) shown.rgb = fogColour.rgb;                                // 10: the fog's colour
    else if (stripe < 11.5) shown.rgb = abs(toEye.z).xxx;                             // 11: how steeply the water is looked at
    else if (stripe < 12.5) shown.rgb = float3(toSun.xy * 0.5 + 0.5, toSun.z);        // 12: the way to the sun
    else if (stripe < 13.5) shown.rgb = float3(frac(spot / 10), 0);                   // 13: the spot itself: squares of ten yards
    else if (stripe < 14.5) shown.rgb = input.clear.xxx;                              // 14: how clear of fog
    else if (stripe < 15.5) shown.rgb = frac(away / 10).xxx;                          // 15: a ring every ten yards from the eye
    // Three that say how the game lays the water over what is behind it.
    else if (stripe < 16.5) shown = float4(1, 1, 1, 0.5);                             // 16: white, alpha a half
    else if (stripe < 17.5) shown = float4(1, 1, 1, 0);                               // 17: white, alpha nothing
    else if (stripe < 18.5) shown = float4(0, 0, 0, 0.5);                             // 18: black, alpha a half
    else if (stripe < 19.5) {                                                         // 19: the game's own water, but for the shine of its corners
        shown.rgb = lerp(fogColour.rgb, input.light.rgb * colour.rgb + ripple.rgb + 0.25 * ripple.a, input.clear);
        shown.a = colour.a * input.light.a;
    }
    // Five more that never come up on the screen (ONLY_STRIPE alone asks for them, on the test bench): where in the
    // kept frame the vertex shader says things are.
    else if (stripe < 20.5) shown.rgb = float3(inFrame(input.onScreenAt.xyz), 0);         // 20: the spot itself
    else if (stripe > 24.5)                                                           // 25: how far ahead of the eye the water is, in hundreds of yards
        shown.rgb = (abs((input.onScreenAt.z - farNumbers.w) / farNumbers.z) / 100).xxx;
    else if (stripe < 21.5)                                                           // 21: the far end of the mirrored line of sight (down: a quarter, about the middle)
        shown.rgb = float3(inFrame(input.mirrorAt.xyz).x, inFrame(input.mirrorAt.xyz).y * 0.25 + 0.5, step(0, input.mirrorAt.z));
    else {                                                                            // 22 to 24: what a yard along "across", "along" and up comes to, times ten, about the middle
        float3 yard = stripe < 22.5 ? input.acrossAt.xyz : stripe < 23.5 ? input.alongAt.xyz : input.upAt.xyz;
        shown.rgb = float3((inFrame(input.onScreenAt.xyz + yard) - inFrame(input.onScreenAt.xyz)) * 10 + 0.5, 0);
    }
    result = shown;
#endif
    return result;
}

#endif
