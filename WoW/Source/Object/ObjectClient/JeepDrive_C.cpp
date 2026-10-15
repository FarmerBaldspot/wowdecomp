// Ours, not the game's (the World of Warcraft editor project): the jeep. See JeepDrive_C.h. No function here has
// an OFFSET: none of them is in the game.
//
// How it sits in the game:
//   - MovementIdleMoveUnits (Movement_C.cpp) calls Update once a frame, after the game's own units have moved.
//   - CGInputControl::UpdatePlayer leaves the unit alone while it is driven: the keys only set their bits
//     (0x10 forward, 0x20 backward, 0x1000 running by itself, 0x100 / 0x200 turning), which this reads, and no
//     movement of the game's is started (no flags, nothing sent to the server for them).
//   - CMovement_C::ExecuteMovement does not apply the game's movement to it (what the server sends, speed changes
//     and the like, is still taken and answered).
//   - CGUnit_C::Animate asks Animate, which puts the model where the body is, tilted, and turns the wheels' bones.
//   - CGUnit_C::ShouldRender hides the rider as it hides a passenger in a hidden seat (HidesRider).
//   - CGWorldFrame::RenderWorld draws the dust (RenderDust) right after the game's weather, as the game draws its
//     mist: squares before the eye, blended over what is behind, behind what stands before them.
// Its sounds are played by the game's own sound engine (SESound, FMOD), in the world where the jeep is and on the
// channel group of sound effects, so the game's own volume for those and its hearing by distance apply. Their
// files are loose files beside the client (Sound\WowEditor\Jeep\*.wav under bin\Win, put there by the build
// from Ours\Sound): the game's file layer finds such a file by its name relative to its own folder when a sound
// asks for it (System_SFile2::FindFile, the file system hash), as it does not for anything else.
// The server is told where the jeep is by heartbeats, ten times a second while it moves and once when it stops.

#include "WoW/Source/Object/ObjectClient/JeepDrive_C.h"
#include "Engine/Source/BLPFile/blp.h"
#include "Engine/Source/ConsoleBase/IConsole.h"
#include "Engine/Source/Gx/CGxBuf.h"
#include "Engine/Source/Gx/CGxDevice/CGxDevice.h"
#include "Engine/Source/Gx/CGxTexFlags.h"
#include "Engine/Source/Gx/CGxVertexPCT.h"
#include "Engine/Source/Gx/Gx.h"
#include "Engine/Source/Services/Texture.h"
#include "Engine/Source/SoundEngine/SoundEngine.h"
#include "Engine/Source/Tempest/C2Vector.h"
#include "Engine/Source/Tempest/CImVector.h"
#include "Engine/Source/Model2/M2Model.h"
#include "Engine/Source/Os/TimeManager.h"
#include "Engine/Source/Tempest/C44Matrix.h"
#include "WoW/Source/Net/Types.h"
#include "WoW/Source/Object/Movement.h"
#include "WoW/Source/Object/Types.h"
#include "WoW/Source/Object/ObjectClient/Unit_C.h"
#include "WoW/Source/ObjectMgrClient/ObjectMgrClient.h"
#include "WoW/Source/UIUtil/InputControl.h"
#include "WoW/Source/WorldClient/DayNight__DNInfo.h"
#include "WoW/Source/WorldClient/Map.h"
#include "WoW/Source/WorldClient/MapArea.h"
#include "WoW/Source/WorldClient/MapChunk.h"
#include "WoW/Source/WorldClient/Types.h"
#include "WoW/Source/WorldClient/World.h"
#include <algorithm>
#include <cmath>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

namespace JeepDrive {

namespace {

const uint32_t FORWARD = 0x1, BACKWARD = 0x2, SIDEWAYS = 0x4 | 0x8, LEFT = 0x10, RIGHT = 0x20, FALLING = 0x1000 | 0x2000;
const uint32_t MOVING = FORWARD | BACKWARD | SIDEWAYS | LEFT | RIGHT | FALLING;
// Of the other flags, those that mean it is not to be driven: swimming, flying, on a transport (taxi, boat).
const uint32_t NOT_DRIVING = 0x200000 | 0x2000000 | 0x200;

// The jeep's model (the editor's content\vehicles\make_vehicle_model.py): bone 0 the body, 1 front right, 2 front
// left, 3 rear right, 4 rear left; the wheels' middles.
const float WHEEL_AT[4][2] = { { 1.92f, -1.24f }, { 1.92f, 1.24f }, { -1.45f, -1.24f }, { -1.45f, 1.24f } };
const float WHEEL_RADIUS = 0.59f;     // and the wheels' middles as the model has them are this high

// The body (yards, seconds, radians; a mass of 1).
const float GRAVITY = 19.29f;         // the game's own (VehicleSeat.dbc's EnterGravity)
const float MASS_HEIGHT = 0.95f;      // where its weight is, over the model's foot
const float INERTIA[3] = { 0.9f, 2.6f, 3.0f }; // about its front, side and up axes
const float ATTACH = 0.92f;           // how high the springs hold on to the body
// The body's shell against the ground: points of it (in its own space, x ahead, y left, z up from its foot) that
// are never to go into the ground.
const float SHELL[22][3] = {
    { 2.55f, 1.15f, 0.50f }, { 2.55f, -1.15f, 0.50f }, { -2.55f, 1.15f, 0.50f }, { -2.55f, -1.15f, 0.50f },     // the floor's corners
    { 2.55f, 1.15f, 1.35f }, { 2.55f, -1.15f, 1.35f }, { -2.55f, 1.15f, 1.35f }, { -2.55f, -1.15f, 1.35f },     // the bonnet's and the back's
    { 1.10f, 1.10f, 2.15f }, { 1.10f, -1.10f, 2.15f }, { -2.40f, 1.10f, 2.15f }, { -2.40f, -1.10f, 2.15f },     // the roof's corners
    { -0.60f, 0.0f, 2.20f },                                                                                    // the roof's middle
    { 2.80f, 0.0f, 0.85f }, { -2.75f, 0.0f, 0.90f },                                                            // the bumpers
    { 0.0f, 1.28f, 0.70f }, { 0.0f, -1.28f, 0.70f }, { 0.0f, 1.20f, 1.80f }, { 0.0f, -1.20f, 1.80f },           // the doors, low and high
    { 0.0f, 0.0f, 0.45f },                                                                                      // under its middle
    { 1.92f, 1.0f, 2.05f }, { 1.92f, -1.0f, 2.05f },                                                            // the windscreen's top
};
// (and each wheel's outer face, at its middle: four more, from WHEEL_AT)
const int SHELL_POINTS = 26;
const float SHELL_STIFF = 320.0f;      // what the ground pushes back with, a second squared for each yard a point is in it
const float SHELL_DAMP = 28.0f;        // and against its going in, for each yard a second
const float SHELL_SLIDES = 0.7f;       // what it drags along the ground with, for what the ground pushes
const float SHELL_DRAG = 6.0f;         // (and for each yard a second it slides, up to that)
const float REST = 0.47f;             // a spring's length with nothing on it
const float SHORTEST = 0.10f, LONGEST = 0.62f;
const float SPRING = 32.0f;           // a wheel's quarter of the weight sinks it 0.15
const float DAMPING = 2.6f;
const float BUMP = 150.0f;            // past its shortest the spring is a stop
// The tyres and the engine.
const float GRIP = 1.6f;              // what a tyre gives, for what it carries
const float GRIP_SLIDING = 1.25f;     // and once it slides
const float CORNERING = 5.0f;         // its pull against sliding sideways, for each yard a second it slides
const float ENGINE = 4.6f;            // a wheel's push at standing; less toward full speed
const float FULL_SPEED = 32.0f;       // what the engine pulls toward, in yards a second (about 29 with the drag)
const float REVERSE_SHARE = 0.45f;
const float BRAKES = 6.5f;            // a wheel's
const float ROLLING = 0.04f;          // what the ground takes, for each yard a second
const float AIR = 0.0022f;            // and the air, by the square of the speed
const float STEER_SLOW = 0.58f, STEER_FAST = 0.22f, STEER_TAKES = 0.10f;
const int SUBSTEPS = 8;
const float GRIP_LEVER = 0.3f;        // how far under its weight the tyres push it

struct Wheel {
    bool onGround = false;            // its ray found ground this frame
    C3Vector hit;                     // where: the spring is along the jeep's own up from there to its hold
    bool down = false;
    float length = REST;              // its spring, as last worked out
    float spin = 0;
    float slid = 0;                   // how fast it slid sideways, yards a second, as last worked out
    float dustDue = 0, clodsDue = 0;  // puffs of dust and clods of dirt owed, not yet thrown
};

struct Driving {
    bool driving = false;
    WOWGUID unit = {};                // the unit being driven
    uint32_t groundFlags = 0;         // what the line trace is asked to hit: found when the driving begins
    // The body: where its weight is, how it moves and turns (in the world), its axes (columns: front, left, up).
    float at[3] = {}, v[3] = {}, w[3] = {};
    float axes[3][3] = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } };
    Wheel wheels[4];
    float steer = 0, steerAngle = 0;
    uint32_t lastAt = 0, toldAt = 0, saidAt = 0;
    bool moved = false;
    float footWas[3] = {};
    float shellGround[SHELL_POINTS] = {};
    unsigned traces = 0, told = 0, shellTouches = 0, shellLifted = 0, animated = 0;
    // What the model is to show: its axes and foot, and each wheel's turn (in the body's own space).
    bool placed = false;
    float foot[3] = {};
    // For the sounds: the engine's revs (0 to 1) and how hard it works, how long it has been in the air, and how
    // it moved the frame before.
    float rpm = 0.1f, load = 0, airTime = 0, wasV[3] = {};
    bool wasKnown = false;
    unsigned thumps = 0;
};

Driving g_driving;

bool trace(Driving& d, const float from[3], const float to[3], uint32_t what, float hit[3]) {
    C3Vector start(from[0], from[1], from[2]), end(to[0], to[1], to[2]), at(0.0f, 0.0f, 0.0f);
    float share = 1.0f;
    ++d.traces;
    const bool found = World::Intersect(start, end, &at, &share, what, nullptr) != 0;
    hit[0] = at.x;
    hit[1] = at.y;
    hit[2] = at.z;
    return found && share >= 0.0f && share <= 1.0f;
}

// The ground under a place, between so high over it and so far under it; -1e9 if none.
float groundAt(Driving& d, float x, float y, float over, float under) {
    const float from[3] = { x, y, over }, to[3] = { x, y, under };
    float hit[3];
    return trace(d, from, to, d.groundFlags, hit) ? hit[2] : -1e9f;
}

void cross(const float a[3], const float b[3], float out[3]) {
    const float c[3] = { a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
    std::memcpy(out, c, sizeof c);
}

float dot(const float a[3], const float b[3]) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

// The i-th of the shell's points, in the body's own space.
void shellPoint(int i, float out[3]) {
    if (i < 22) {
        std::memcpy(out, SHELL[i], 3 * sizeof(float));
        return;
    }
    const int wheel = i - 22;
    out[0] = WHEEL_AT[wheel][0];
    out[1] = WHEEL_AT[wheel][1] > 0 ? 1.42f : -1.42f;
    out[2] = WHEEL_RADIUS;
}

// A point of the body (in its own axes, from the model's foot) in the world.
void bodyPoint(const Driving& d, const float p[3], float out[3]) {
    const float q[3] = { p[0], p[1], p[2] - MASS_HEIGHT };
    for (int r = 0; r < 3; ++r) {
        out[r] = d.at[r] + d.axes[r][0] * q[0] + d.axes[r][1] * q[1] + d.axes[r][2] * q[2];
    }
}

// Its axes kept upright to one another after they are turned a little.
void straighten(float m[3][3]) {
    float f[3] = { m[0][0], m[1][0], m[2][0] }, l[3] = { m[0][1], m[1][1], m[2][1] }, u[3];
    float n = std::sqrt(dot(f, f));
    for (float& x : f) {
        x /= n;
    }
    cross(f, l, u);
    n = std::sqrt(dot(u, u));
    for (float& x : u) {
        x /= n;
    }
    cross(u, f, l);
    for (int r = 0; r < 3; ++r) {
        m[r][0] = f[r];
        m[r][1] = l[r];
        m[r][2] = u[r];
    }
}

// What the line trace is to be asked: the first of the game's ways that finds ground a few yards under the
// player's feet; and the body put on its wheels.
bool begin(Driving& d, float x, float y, float z, float facing) {
    static const uint32_t WAYS[] = { 0x100111, 0x100151, 0x100171, 0x120171, 0x100101, 0x100100, 0x111 };
    d.groundFlags = 0;
    for (uint32_t way : WAYS) {
        d.groundFlags = way;
        const float ground = groundAt(d, x, y, z + 3.0f, z - 6.0f);
        if (ground > -1e8f && std::fabs(ground - z) < 2.5f) {
            break;
        }
        d.groundFlags = 0;
    }
    if (!d.groundFlags) {
        return false;
    }
    const float c = std::cos(facing), s = std::sin(facing);
    const float axes[3][3] = { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } };
    std::memcpy(d.axes, axes, sizeof axes);
    d.at[0] = x;
    d.at[1] = y;
    d.at[2] = z + MASS_HEIGHT;
    std::memset(d.v, 0, sizeof d.v);
    std::memset(d.w, 0, sizeof d.w);
    for (Wheel& wheel : d.wheels) {
        wheel = Wheel {};
    }
    return true;
}

// The wheels' bones back to what their animation alone does.
void freeWheels(CGUnit_C* unit) {
    CM2Model* model = unit ? unit->GetObjectModel() : nullptr;
    if (!model) {
        return;
    }
    for (uint32_t bone = 1; bone <= 4; ++bone) {
        model->SetBoneProceduralTransformAt(bone, nullptr);
    }
}

void hushSounds();

void stop(Driving& d, uint32_t now) {
    if (!d.driving) {
        return;
    }
    CGUnit_C* unit = static_cast<CGUnit_C*>(ClntObjMgrObjectPtr(d.unit, TYPEMASK_UNIT, __FILE__, __LINE__));
    freeWheels(unit);
    hushSounds();
    ConsolePrintf("Jeep: stopped driving (%u heartbeat(s), %u trace(s), the shell touched the ground %u time(s), lifted out %u)", d.told, d.traces, d.shellTouches, d.shellLifted);
    d = Driving {};
    // Keys that are still held now move the player as the game moves them.
    if (CGInputControl* input = CGInputControl::GetActive()) {
        input->UpdatePlayer(now, 1);
    }
}

CGUnit_C* jeepOf(const CGUnit_C* unit) {
    if (!unit || !unit->m_movement || unit->m_mountDisplayId != JEEP_LOOK) {
        return nullptr;
    }
    if (unit->m_movement->m_flags & NOT_DRIVING) {
        return nullptr;
    }
    return const_cast<CGUnit_C*>(unit);
}

void physics(Driving& d, float dt, float throttle, float steering) {
    const float full = FULL_SPEED;

    // The ground under each wheel, once a frame: from a little over the wheel's middle down along the jeep's own
    // down (a spring is fixed to the body and works along it).
    for (int i = 0; i < 4; ++i) {
        const float a[3] = { WHEEL_AT[i][0], WHEEL_AT[i][1], ATTACH };
        float p[3];
        bodyPoint(d, a, p);
        const float up[3] = { d.axes[0][2], d.axes[1][2], d.axes[2][2] };
        const float start = d.wheels[i].length - 0.3f, end = LONGEST + WHEEL_RADIUS + 2.5f;
        const float from[3] = { p[0] - up[0] * start, p[1] - up[1] * start, p[2] - up[2] * start };
        const float to[3] = { p[0] - up[0] * end, p[1] - up[1] * end, p[2] - up[2] * end };
        float hit[3];
        d.wheels[i].onGround = trace(d, from, to, d.groundFlags, hit);
        d.wheels[i].hit = C3Vector(hit[0], hit[1], hit[2]);
    }
    // The ground under each of the shell's points: from 2.5 yards over it to 2 under.
    for (int i = 0; i < SHELL_POINTS; ++i) {
        float own[3], p[3];
        shellPoint(i, own);
        bodyPoint(d, own, p);
        d.shellGround[i] = groundAt(d, p[0], p[1], p[2] + 2.5f, p[2] - 2.0f);
    }
    // (Under the body, for when all the wheels find nothing: the ground far below, or none at all.)
    const bool anyGround = d.wheels[0].onGround || d.wheels[1].onGround || d.wheels[2].onGround || d.wheels[3].onGround;
    float below = -1e9f;
    if (!anyGround) {
        below = groundAt(d, d.at[0], d.at[1], d.at[2] + 2.0f, d.at[2] - 300.0f);
    }

    const float forwardNow[3] = { d.axes[0][0], d.axes[1][0], d.axes[2][0] };
    const float along = dot(d.v, forwardNow);
    const float share = std::min(1.0f, std::fabs(along) / full);
    d.steer += (steering - d.steer) * std::min(1.0f, dt / STEER_TAKES);
    const float steerAngle = d.steer * (STEER_SLOW + (STEER_FAST - STEER_SLOW) * share);
    d.steerAngle = steerAngle;

    const float h = dt / float(SUBSTEPS);
    for (int step = 0; step < SUBSTEPS && dt > 0; ++step) {
        float force[3] = { 0, 0, -GRAVITY }, torque[3] = { 0, 0, 0 };
        int down = 0;
        for (int i = 0; i < 4; ++i) {
            Wheel& wheelNow = d.wheels[i];
            const float a[3] = { WHEEL_AT[i][0], WHEEL_AT[i][1], ATTACH };
            float p[3];
            bodyPoint(d, a, p);
            const float arm[3] = { p[0] - d.at[0], p[1] - d.at[1], p[2] - d.at[2] };
            float spinV[3], pv[3];
            cross(d.w, arm, spinV);
            for (int k = 0; k < 3; ++k) {
                pv[k] = d.v[k] + spinV[k];
            }
            const float up[3] = { d.axes[0][2], d.axes[1][2], d.axes[2][2] };
            const float apart[3] = { p[0] - wheelNow.hit.x, p[1] - wheelNow.hit.y, p[2] - wheelNow.hit.z };
            const float length = wheelNow.onGround ? dot(apart, up) - WHEEL_RADIUS : 1e9f;
            const float closing = dot(pv, up);
            wheelNow.down = length < LONGEST;
            wheelNow.length = std::max(SHORTEST, std::min(LONGEST, length));
            if (!wheelNow.down) {
                continue;
            }
            ++down;
            float push = SPRING * (REST - length) - DAMPING * closing;
            if (length < SHORTEST) {
                push += BUMP * (SHORTEST - length) - 4.0f * closing;
            }
            // (No spring pushes more than three times the weight it carries standing: a step it meets is a jolt,
            // not a throw.)
            push = std::max(0.0f, std::min(push, 3.0f * GRAVITY * 0.25f * 4.0f));
            // The tyre: its front (the front wheels turned by the steering) and its left, along the ground.
            const float turn = i < 2 ? steerAngle : 0.0f;
            const float ct = std::cos(turn), st = std::sin(turn);
            float f[3] = { d.axes[0][0] * ct + d.axes[0][1] * st, d.axes[1][0] * ct + d.axes[1][1] * st, 0.0f };
            const float n = std::sqrt(f[0] * f[0] + f[1] * f[1]);
            if (n < 1e-4f) {
                continue;
            }
            f[0] /= n;
            f[1] /= n;
            const float l[3] = { -f[1], f[0], 0.0f };
            const float u = pv[0] * f[0] + pv[1] * f[1], s = pv[0] * l[0] + pv[1] * l[1];
            wheelNow.slid = std::fabs(s);
            float longF = -ROLLING * u, latF = -CORNERING * s;
            if (throttle > 0) {
                if (u < -0.5f) {
                    longF += BRAKES;
                } else {
                    longF += ENGINE * std::pow(std::max(0.0f, 1.0f - u / full), 0.5f);
                }
            } else if (throttle < 0) {
                if (u > 0.5f) {
                    longF -= BRAKES;
                } else {
                    longF -= ENGINE * 0.8f * std::pow(std::max(0.0f, 1.0f + u / (full * REVERSE_SHARE)), 0.5f);
                }
            }
            // What the tyre can give: more weight, more grip; asked for more, it slides, and gives less.
            const float most = GRIP * push;
            const float asked = std::sqrt(longF * longF + latF * latF);
            if (asked > most && asked > 0) {
                const float given = GRIP_SLIDING / GRIP * most / asked;
                longF *= given;
                latF *= given;
            }
            // The spring pushes where it holds the body; the tyre a little under its weight (as arcade cars have
            // it: pushed at the ground itself, a tyre turning it rolled the jeep over at a walking pace).
            const float held[3] = { up[0] * push, up[1] * push, up[2] * push };
            const float gripped[3] = { f[0] * longF + l[0] * latF, f[1] * longF + l[1] * latF, 0.0f };
            const float touch[3] = { arm[0], arm[1], -GRIP_LEVER };
            for (int k = 0; k < 3; ++k) {
                force[k] += held[k] + gripped[k];
            }
            float t[3];
            cross(arm, held, t);
            for (int k = 0; k < 3; ++k) {
                torque[k] += t[k];
            }
            cross(touch, gripped, t);
            for (int k = 0; k < 3; ++k) {
                torque[k] += t[k];
            }
            wheelNow.spin += u / WHEEL_RADIUS * h;
        }
        // The shell: a point in the ground is pushed back out (up, by how far in it is and how fast it goes in),
        // where it is, so that the jeep tips and rolls over as it lands; and drags along the ground.
        for (int i = 0; i < SHELL_POINTS; ++i) {
            if (d.shellGround[i] < -1e8f) {
                continue;
            }
            float own[3], p[3];
            shellPoint(i, own);
            bodyPoint(d, own, p);
            const float in = d.shellGround[i] - p[2];
            if (in <= 0.0f) {
                continue;
            }
            const float arm[3] = { p[0] - d.at[0], p[1] - d.at[1], p[2] - d.at[2] };
            float spinV[3], pv[3];
            cross(d.w, arm, spinV);
            for (int k = 0; k < 3; ++k) {
                pv[k] = d.v[k] + spinV[k];
            }
            const float pushed = std::max(0.0f, std::min(SHELL_STIFF * in - SHELL_DAMP * pv[2], 8.0f * GRAVITY));
            if (pushed <= 0.0f) {
                continue;
            }
            float f[3] = { 0.0f, 0.0f, pushed };
            const float sliding = std::sqrt(pv[0] * pv[0] + pv[1] * pv[1]);
            if (sliding > 1e-3f) {
                const float drag = std::min(SHELL_SLIDES * pushed, SHELL_DRAG * sliding);
                f[0] -= pv[0] / sliding * drag;
                f[1] -= pv[1] / sliding * drag;
            }
            for (int k = 0; k < 3; ++k) {
                force[k] += f[k];
            }
            float t[3];
            cross(arm, f, t);
            for (int k = 0; k < 3; ++k) {
                torque[k] += t[k];
            }
            if (step == 0) {
                ++d.shellTouches;
            }
        }
        // The air.
        const float speed = std::sqrt(dot(d.v, d.v));
        for (int k = 0; k < 3; ++k) {
            force[k] -= AIR * speed * d.v[k];
        }
        // With nothing under it at all and no ground anywhere below, it is held where it is (the world around it
        // has not come yet, or it is over the edge of it).
        if (!anyGround && below < -1e8f) {
            force[2] = 0.0f;
            d.v[2] = 0.0f;
        }
        for (int k = 0; k < 3; ++k) {
            d.v[k] += force[k] * h;
        }
        // Turning: the torque into its own axes, by its inertia there, and back.
        float local[3], spin[3];
        for (int c = 0; c < 3; ++c) {
            local[c] = (d.axes[0][c] * torque[0] + d.axes[1][c] * torque[1] + d.axes[2][c] * torque[2]) / INERTIA[c];
        }
        for (int r = 0; r < 3; ++r) {
            spin[r] = d.axes[r][0] * local[0] + d.axes[r][1] * local[1] + d.axes[r][2] * local[2];
        }
        for (int k = 0; k < 3; ++k) {
            d.w[k] += spin[k] * h;
        }
        if (down == 0) {
            for (float& x : d.w) {
                x *= 1.0f - 0.3f * h;           // in the air it keeps its spin, nearly
            }
        }
        const float spinning = std::sqrt(dot(d.w, d.w));
        if (spinning > 4.0f) {
            for (float& x : d.w) {
                x *= 4.0f / spinning;
            }
        }
        for (int k = 0; k < 3; ++k) {
            d.at[k] += d.v[k] * h;
        }
        float turned[3][3];
        for (int r = 0; r < 3; ++r) {
            for (int c = 0; c < 3; ++c) {
                turned[r][c] = d.axes[r][c] + (d.w[(r + 1) % 3] * d.axes[(r + 2) % 3][c] - d.w[(r + 2) % 3] * d.axes[(r + 1) % 3][c]) * h;
            }
        }
        std::memcpy(d.axes, turned, sizeof turned);
        straighten(d.axes);
    }

    // A point still deep in the ground lifts the body out by as much, and it stops going down: the push alone, in
    // one hard landing, may not be enough.
    float deepest = 0.0f;
    for (int i = 0; i < SHELL_POINTS; ++i) {
        if (d.shellGround[i] < -1e8f) {
            continue;
        }
        float own[3], p[3];
        shellPoint(i, own);
        bodyPoint(d, own, p);
        deepest = std::max(deepest, d.shellGround[i] - p[2]);
    }
    if (deepest > 0.25f) {
        d.at[2] += deepest - 0.25f;
        d.v[2] = std::max(d.v[2], 0.0f);
        ++d.shellLifted;
    }

    // What is in its way: from its middle out to points of its outline, at the height of its bumper and of its
    // doors. What a trace meets is inside the jeep: the jeep is pushed out of it, and what of its speed went into
    // it stops, with a little bounce.
    static const float OUTLINE[12][2] = { { 2.75f, 1.30f }, { 2.75f, -1.30f }, { -2.75f, 1.30f }, { -2.75f, -1.30f }, { 2.85f, 0.0f }, { -2.85f, 0.0f },
        { 1.0f, 1.45f }, { 1.0f, -1.45f }, { -0.9f, 1.45f }, { -0.9f, -1.45f }, { 2.0f, 1.42f }, { 2.0f, -1.42f } };
    float shove[3] = { 0, 0, 0 };
    for (float height : { 0.75f, 1.45f }) {
        const float middleAt[3] = { 0.0f, 0.0f, height };
        float from[3];
        bodyPoint(d, middleAt, from);
        for (const auto& corner : OUTLINE) {
            const float edgeAt[3] = { corner[0], corner[1], height };
            float to[3], hit[3];
            bodyPoint(d, edgeAt, to);
            if (!trace(d, from, to, 0x100171, hit)) {
                continue;
            }
            // (Low down, what it meets may be the ground going up before it: a slope the wheels take.)
            if (height < 1.0f) {
                const float ground = groundAt(d, hit[0], hit[1], hit[2] + 1.2f, hit[2] - 1.2f);
                if (ground > hit[2] - 0.6f && ground < hit[2] + 0.6f) {
                    continue;
                }
            }
            float way[3] = { to[0] - from[0], to[1] - from[1], 0.0f };
            const float length = std::sqrt(way[0] * way[0] + way[1] * way[1]);
            if (length < 1e-3f) {
                continue;
            }
            way[0] /= length;
            way[1] /= length;
            const float inside = (to[0] - hit[0]) * way[0] + (to[1] - hit[1]) * way[1];
            for (int k = 0; k < 2; ++k) {
                const float out = -way[k] * inside;
                if (std::fabs(out) > std::fabs(shove[k])) {
                    shove[k] = out;
                }
            }
            const float into = d.v[0] * way[0] + d.v[1] * way[1];
            if (into > 0) {
                // A blow bounces it back a little and turns it by where it was struck; a touch only stops what
                // goes into it.
                const bool blow = into > 2.0f;
                const float back = blow ? 1.2f : 1.0f;
                d.v[0] -= back * into * way[0];
                d.v[1] -= back * into * way[1];
                if (blow) {
                    const float arm[3] = { to[0] - d.at[0], to[1] - d.at[1], 0.0f };
                    float struck[3] = { -way[0] * into, -way[1] * into, 0.0f }, turn[3];
                    cross(arm, struck, turn);
                    d.w[2] += turn[2] * 0.15f;
                }
            }
        }
    }
    // (Out of it by most of the way, not all of it at once: it settles against what it touches.)
    const float shoved = std::sqrt(shove[0] * shove[0] + shove[1] * shove[1]);
    if (shoved > 0.03f) {
        d.at[0] += shove[0] * 0.6f * (shoved - 0.03f) / shoved;
        d.at[1] += shove[1] * 0.6f * (shoved - 0.03f) / shoved;
    }
    // Never under the ground: the body's middle is kept over what is under it.
    const float under = groundAt(d, d.at[0], d.at[1], d.at[2] + 1.5f, d.at[2] - 3.0f);
    if (under > -1e8f && d.at[2] < under + 0.35f) {
        d.at[2] = under + 0.35f;
        d.v[2] = std::max(d.v[2], 0.0f);
    }
}


// ---- The dust the wheels throw up (it was the gfx DLL's, drive.inc's throwDust and drawDust, with the same numbers).
// Each wheel on the ground throws puffs where it touches, the more the faster the jeep goes (from 6 yards a second;
// the back wheels twice the front ones) and the more it slides sideways, and clods of dirt flung off the tyre; they
// rise a little, are slowed by the air, grow and fade. Their colour is the ground's under the wheel: what the map's
// own texture there comes to (the one that shows most on that square of the chunk, as the game's ground type is
// found: CMap::QueryGroundTypeTerrain), lit by the game's light of the hour, and moved toward what the wheel is on now
// only a quarter of a second's worth at a time (a colour taken fresh every frame flickers over stones and tufts).
struct Puff {
    float at[3], v[3];
    float age, life, size, grows;
    float turn;                        // how its square is turned, so that no two look alike
    bool clod;                         // a clod of dirt flung off the tyre, not a puff of dust
    int wheel;                         // which wheel threw it: it takes the colour of the ground under that one
};

const size_t MOST_PUFFS = 1200;
std::vector<Puff> g_puffs;
uint32_t g_dustLot = 12345;
uint32_t g_dustAt = 0;                 // when the puffs were last moved on
float g_wheelEarth[4][3] = { { 0.5f, 0.42f, 0.32f }, { 0.5f, 0.42f, 0.32f }, { 0.5f, 0.42f, 0.32f }, { 0.5f, 0.42f, 0.32f } };
bool g_wheelEarthKnown[4] = {};
std::unordered_map<std::string, std::vector<float>> g_textureColours;   // a ground texture's file: its colour, or nothing
unsigned g_dustThrown = 0;

float lot() {
    g_dustLot = g_dustLot * 1664525u + 1013904223u;
    return static_cast<float>(g_dustLot >> 8) / 16777216.0f;
}

// What a texture of the ground comes to: the middle of one of its small levels (8 x 8 or so), from the file.
bool textureColour(const char* name, float out[3]) {
    auto known = g_textureColours.find(name);
    if (known == g_textureColours.end()) {
        std::vector<float> colour;
        CBLPFile blp;
        if (blp.Open(name, 0)) {
            uint32_t level = 0;
            while (blp.IsValidMip(level + 1) && blp.Width(level) > 8) {
                ++level;
            }
            uint8_t* data = nullptr;
            uint32_t stride = 0;
            if (blp.Lock(PIXEL_ARGB8888, level, data, stride) && data) {
                const uint32_t width = blp.Width(level), height = blp.Height(level);
                double sum[3] = {};
                for (uint32_t y = 0; y < height; ++y) {
                    const uint8_t* row = data + y * (stride ? stride : 4 * width);
                    for (uint32_t x = 0; x < width; ++x) {
                        sum[0] += row[4 * x + 2];   // (bytes as they lie: blue, green, red, alpha)
                        sum[1] += row[4 * x + 1];
                        sum[2] += row[4 * x + 0];
                    }
                }
                const double count = std::max(1u, width * height) * 255.0;
                colour = { static_cast<float>(sum[0] / count), static_cast<float>(sum[1] / count), static_cast<float>(sum[2] / count) };
                blp.Unlock(level);
            }
            blp.Close();
        }
        ConsolePrintf("Jeep: the ground's texture %s %s", name, colour.empty() ? "could not be read" : "is read for the dust's colour");
        known = g_textureColours.emplace(name, colour).first;
    }
    if (known->second.size() != 3) {
        return false;
    }
    std::memcpy(out, known->second.data(), 3 * sizeof(float));
    return true;
}

// The colour of the map's own ground at a place: its texture that shows most on that square.
bool groundColour(float x, float y, float out[3]) {
    const float fromWest = -(y - 17066.666f), fromNorth = -(x - 17066.666f);
    if (fromWest < 0.0f || fromNorth < 0.0f || fromWest >= 34133.332f || fromNorth >= 34133.332f) {
        return false;
    }
    const int32_t cellY = static_cast<int32_t>(fromNorth * 0.24f), cellX = static_cast<int32_t>(fromWest * 0.24f);
    CMapArea* area = CMap::GetLoadedArea((cellX >> 7) & 0x3F, (cellY >> 7) & 0x3F);
    if (!area) {
        return false;
    }
    CMapChunk* chunk = area->m_mapChunks[16 * ((cellY >> 3) & 0xF) + ((cellX >> 3) & 0xF)];
    if (!chunk || !chunk->m_header || !chunk->m_layers || !chunk->m_lowQualityTexMap) {
        return false;
    }
    const int32_t col = cellX & 7, row = cellY & 7;
    const uint32_t layer = (CMap::s_2bitSplatMask[col] & reinterpret_cast<const uint16_t*>(chunk->m_lowQualityTexMap)[row]) >> CMap::s_2bitSplatShft[col];
    if (layer >= chunk->m_header->m_nLayers) {
        return false;
    }
    const uint32_t texture = chunk->m_layers[layer].m_textureId;
    if (texture >= area->m_textures.Count() || !area->m_textures.m_data[texture].m_textureName) {
        return false;
    }
    return textureColour(area->m_textures.m_data[texture].m_textureName, out);
}

void throwDust(Driving& d, float dt) {
    const float speed = std::sqrt(dot(d.v, d.v));
    const float front[3] = { d.axes[0][0], d.axes[1][0], d.axes[2][0] };
    const float left[3] = { d.axes[0][1], d.axes[1][1], d.axes[2][1] };
    for (int i = 0; i < 4; ++i) {
        Wheel& wheel = d.wheels[i];
        if (!wheel.down || !wheel.onGround) {
            wheel.dustDue = 0;
            continue;
        }
        // The colour of what it is on, moved toward a quarter of a second's worth.
        float earth[3];
        if (groundColour(wheel.hit.x, wheel.hit.y, earth)) {
            const float take = g_wheelEarthKnown[i] ? std::min(1.0f, dt / 0.25f) : 1.0f;
            for (int k = 0; k < 3; ++k) {
                g_wheelEarth[i][k] += (earth[k] - g_wheelEarth[i][k]) * take;
            }
            g_wheelEarthKnown[i] = true;
        }
        const float hit[3] = { wheel.hit.x, wheel.hit.y, wheel.hit.z };
        const float fast = std::max(0.0f, std::min(1.0f, (speed - 6.0f) / 22.0f));
        const float sliding = std::min(1.0f, wheel.slid / 5.0f);
        const float back = i < 2 ? 0.5f : 1.0f;                                              // the back wheels throw more
        wheel.dustDue += back * (35.0f * fast + 28.0f * sliding) * dt;
        wheel.clodsDue += back * (28.0f * fast + 24.0f * sliding) * dt;
        // (A puff of dust: carried on with the jeep for the most part; rising a little, spreading, growing large.)
        while (wheel.dustDue >= 1.0f && g_puffs.size() < MOST_PUFFS) {
            wheel.dustDue -= 1.0f;
            Puff puff;
            puff.clod = false;
            puff.wheel = i;
            const float aside = (lot() - 0.5f) * 0.5f, ahead = (lot() - 0.5f) * 0.6f;
            for (int k = 0; k < 3; ++k) {
                puff.at[k] = hit[k] + left[k] * aside + front[k] * ahead;
                puff.v[k] = d.v[k] * 0.62f + left[k] * (lot() - 0.5f) * (2.0f + wheel.slid * 0.5f);
            }
            puff.at[2] += 0.1f;
            puff.v[2] += 0.3f + lot() * (0.6f + speed * 0.015f);
            puff.age = 0;
            puff.life = 0.8f + lot() * (0.6f + fast * 0.6f);
            puff.size = 0.4f + lot() * 0.3f;
            puff.grows = 0.9f + lot() * 0.8f + fast * 0.8f;
            puff.turn = lot() * 6.2831853f;
            g_puffs.push_back(puff);
            ++g_dustThrown;
        }
        // (A clod: flung up and back off the tyre's top, falling as anything falls.)
        while (wheel.clodsDue >= 1.0f && g_puffs.size() < MOST_PUFFS) {
            wheel.clodsDue -= 1.0f;
            Puff puff;
            puff.clod = true;
            puff.wheel = i;
            const float aside = (lot() - 0.5f) * 0.5f;
            for (int k = 0; k < 3; ++k) {
                puff.at[k] = hit[k] + left[k] * aside;
                puff.v[k] = d.v[k] * (0.45f + lot() * 0.3f) + left[k] * (lot() - 0.5f) * (3.0f + wheel.slid * 0.6f);
            }
            puff.at[2] += 0.35f;
            puff.v[2] += 1.5f + lot() * (2.0f + speed * 0.06f);
            puff.age = 0;
            puff.life = 0.5f + lot() * 0.6f;
            puff.size = 0.05f + lot() * 0.08f;
            puff.grows = 0;
            puff.turn = lot() * 6.2831853f;
            g_puffs.push_back(puff);
        }
        wheel.clodsDue = std::min(wheel.clodsDue, 4.0f);
        wheel.dustDue = std::min(wheel.dustDue, 4.0f);
    }
}

// Moved on: the air slows them, they sink a little, grow and fade.
void moveDust(float dt) {
    const float slowed = std::exp(-1.8f * dt), slowedLess = std::exp(-0.4f * dt);
    size_t kept = 0;
    for (Puff& puff : g_puffs) {
        puff.age += dt;
        if (puff.age >= puff.life) {
            continue;
        }
        for (int k = 0; k < 3; ++k) {
            puff.v[k] *= puff.clod ? slowedLess : slowed;
            puff.at[k] += puff.v[k] * dt;
        }
        puff.v[2] -= (puff.clod ? GRAVITY * 0.8f : 1.5f) * dt;
        puff.size += puff.grows * dt;
        g_puffs[kept++] = puff;
    }
    g_puffs.resize(kept);
}

// The picture a puff is drawn with: soft all the way to its edge, thickest in its middle, lumpy (two slow waves
// across it, as the DLL's shader had them). White: each puff's colour is its corners'.
const uint32_t PUFF_SIZE = 64;
CImVector g_puffTexels[PUFF_SIZE * PUFF_SIZE];
CTexture* g_puffTexture = nullptr;

void puffTexels(EGxTexCommand command, uint32_t width, uint32_t height, uint32_t depth, uint32_t mipLevel, void* userArg, uint32_t& texelStrideInBytes, const void*& texels) {
    if (command == GxTex_Latch) {
        texelStrideInBytes = 4 * width;
        texels = g_puffTexels;
    }
}

CGxTex* puffTexture() {
    if (!g_puffTexture) {
        for (uint32_t y = 0; y < PUFF_SIZE; ++y) {
            for (uint32_t x = 0; x < PUFF_SIZE; ++x) {
                const float px = (x + 0.5f) / PUFF_SIZE * 2.0f - 1.0f, py = (y + 0.5f) / PUFF_SIZE * 2.0f - 1.0f;
                const float r = std::sqrt(px * px + py * py);
                float soft = std::max(0.0f, std::min(1.0f, 1.0f - r));
                soft = soft * soft * (3.0f - 2.0f * soft);
                const float lumps = 0.7f + 0.3f * std::sin(px * 4.3f + 1.3f) * std::sin(py * 3.7f + 4.1f);
                CImVector& texel = g_puffTexels[y * PUFF_SIZE + x];
                texel.r = texel.g = texel.b = 255;
                texel.a = static_cast<uint8_t>(std::max(0.0f, std::min(1.0f, soft * lumps)) * 255.0f);
            }
        }
        g_puffTexture = TextureCreate(PUFF_SIZE, PUFF_SIZE, GxTex_Argb8888, GxTex_Argb8888, CGxTexFlags(GxTex_Linear, 0, 0, 0, 0, 0, 1), nullptr, puffTexels, "JeepDust", 0);
    }
    return g_puffTexture ? TextureGetGxTex(g_puffTexture, 0, nullptr) : nullptr;
}

// ---- Its sounds (they were the gfx DLL's, drive.inc's soundJeep, with the same numbers; the files are made by the
// editor's client\gfx\sounds\make_sounds.py):
//   - the engine, a loop played faster with the revs, which climb through five gears with the speed along the jeep
//     and fall back at each change; with the throttle and the wheels spinning on the spot or in the air it revs up;
//     standing still, an idle; louder with the throttle;
//   - the tyres' squeal, by how fast the wheels on the ground slide sideways;
//   - the ground under them, by the speed and how many wheels touch it;
//   - the wind, from 8 yards a second;
//   - a thump, landing hard (by how fast it fell) or brought up short (its speed changed by more than the driving
//     itself changes it in a frame: a wall, the ground's edge).
// How far off it is heard and to which side is the game's sound engine's affair now (the jeep is a sound in the
// world); the DLL worked it out from the camera itself.
const char* const JEEP_SOUND_FILES[5] = {
    "Sound\\WowEditor\\Jeep\\engine.wav", "Sound\\WowEditor\\Jeep\\skid.wav", "Sound\\WowEditor\\Jeep\\gravel.wav",
    "Sound\\WowEditor\\Jeep\\wind.wav", "Sound\\WowEditor\\Jeep\\thump.wav"
};
enum { ENGINE_SOUND, SKID_SOUND, GROUND_SOUND, WIND_SOUND, THUMP_SOUND };
const float GEAR_TOPS[5] = { 5.5f, 11.0f, 17.0f, 23.5f, 31.0f };   // yards a second at the top of each gear
const float SOUND_LOUDNESS = 0.9f;
const float HEARD_FULLY = 8.0f, HEARD_UP_TO = 80.0f;               // yards: as loud as it is up to, and heard up to
SESound g_loops[4];
bool g_loopsMade = false, g_soundsSaid = false;

bool makeSound(SESound& sound, int which, bool looping, const C3Vector& at) {
    if (!sound.Create3D(JEEP_SOUND_FILES[which], looping ? 1 : 0, nullptr, nullptr, looping, false, 128, 1, 360.0f, 360.0f, 1.0f, nullptr)) {
        if (!g_soundsSaid) {
            ConsolePrintf("Jeep: the sound %s could not be made (is it beside the client, under bin\\Win?)", JEEP_SOUND_FILES[which]);
            g_soundsSaid = true;
        }
        return false;
    }
    sound.Set3DPosition(at);
    sound.Set3DMinMaxDistance(HEARD_FULLY, HEARD_UP_TO);
    sound.SetChannelGroup("SFX", true);
    sound.SetVolume(0.0f);
    sound.CompleteNonBlockingLoad();
    sound.Play();
    return true;
}

void hushSounds() {
    if (!g_loopsMade) {
        return;
    }
    for (SESound& loop : g_loops) {
        loop.Stop(0, 0.3f);
    }
    g_loopsMade = false;
}

void setLoop(int which, float volume, float pitch, const C3Vector& at) {
    SESound& loop = g_loops[which];
    loop.Set3DPosition(at);
    loop.SetVolume(std::max(0.0f, std::min(1.0f, volume)));
    loop.SetPitch(std::max(0.25f, std::min(4.0f, pitch)));
}

void soundJeep(Driving& d, float dt, float throttle) {
    const C3Vector at(d.at[0], d.at[1], d.at[2]);
    if (!g_loopsMade) {
        bool all = true;
        for (int i = 0; i < 4; ++i) {
            all = makeSound(g_loops[i], i, true, at) && all;
        }
        g_loopsMade = true;
        if (all) {
            ConsolePrintf("Jeep: its sounds are playing");
        }
    }
    if (dt <= 0) {
        return;
    }
    const float front[3] = { d.axes[0][0], d.axes[1][0], d.axes[2][0] };
    const float along = std::fabs(dot(d.v, front));
    const float speed = std::sqrt(dot(d.v, d.v));
    int down = 0;
    float slid = 0;
    for (const Wheel& wheel : d.wheels) {
        if (wheel.down) {
            ++down;
            slid = std::max(slid, wheel.slid);
        }
    }
    const float loud = SOUND_LOUDNESS;
    // The engine.
    int gear = 0;
    while (gear < 4 && along > GEAR_TOPS[gear]) {
        ++gear;
    }
    const float low = gear ? GEAR_TOPS[gear - 1] : 0.0f;
    const float share = std::max(0.0f, std::min(1.0f, (along - low) / (GEAR_TOPS[gear] - low)));
    float revs = gear ? 0.38f + 0.62f * share : 0.16f + 0.84f * share;
    const bool working = throttle != 0.0f;
    if (working && (down == 0 || slid > 4.0f)) {
        revs = std::max(revs, 0.75f);              // spinning, or in the air: it revs
    }
    if (!working && along < 0.5f) {
        revs = 0.1f;                               // standing: an idle
    }
    d.rpm += (revs - d.rpm) * std::min(1.0f, dt * (revs < d.rpm ? 10.0f : 5.0f));
    d.load += ((working ? 1.0f : 0.0f) - d.load) * std::min(1.0f, dt * 6.0f);
    setLoop(ENGINE_SOUND, loud * (0.30f + 0.36f * d.load + 0.22f * d.rpm), 0.85f + d.rpm * 3.4f, at);
    // The tyres sliding.
    const float squeal = std::max(0.0f, std::min(1.0f, (slid - 1.5f) / 5.0f)) * (down ? 1.0f : 0.0f);
    setLoop(SKID_SOUND, loud * 0.55f * squeal, 0.92f + 0.15f * std::min(1.0f, slid / 10.0f), at);
    // The ground under them.
    const float rolling = std::pow(std::min(1.0f, speed / 18.0f), 0.7f) * static_cast<float>(down) / 4.0f;
    setLoop(GROUND_SOUND, loud * 0.5f * rolling, 0.75f + 0.55f * std::min(1.0f, speed / 28.0f), at);
    // The wind.
    const float windy = std::pow(std::max(0.0f, std::min(1.0f, (speed - 8.0f) / 22.0f)), 1.5f);
    setLoop(WIND_SOUND, loud * 0.45f * windy, 0.8f + 0.5f * std::min(1.0f, speed / 30.0f), at);
    // A thump.
    float knock = 0;
    if (down == 0) {
        d.airTime += dt;
    } else {
        if (d.airTime > 0.25f && d.wasKnown && d.wasV[2] < -4.0f) {
            knock = std::max(knock, (-d.wasV[2] - 4.0f) / 10.0f);
        }
        d.airTime = 0;
    }
    if (d.wasKnown) {
        const float changed[3] = { d.v[0] - d.wasV[0], d.v[1] - d.wasV[1], d.v[2] - d.wasV[2] + GRAVITY * dt };
        const float by = std::sqrt(dot(changed, changed));
        if (by > 4.0f) {
            knock = std::max(knock, (by - 4.0f) / 8.0f);
        }
    }
    if (knock > 0.05f) {
        // (A sound of its own each time; it plays to its end after this one is gone, as the game's one-off sounds do.)
        SESound thump;
        if (makeSound(thump, THUMP_SOUND, false, at)) {
            thump.SetVolume(std::min(1.0f, loud * std::min(1.0f, 0.35f + knock)));
            thump.SetPitch(0.9f + 0.2f * lot());
            ++d.thumps;
        }
    }
    std::memcpy(d.wasV, d.v, sizeof d.wasV);
    d.wasKnown = true;
}

}  // namespace

bool Drives(const CGUnit_C* unit) {
    return g_driving.driving && unit && unit->m_obj && unit->m_obj->m_guid == g_driving.unit;
}

bool HidesRider(const CGUnit_C* unit) {
    return Drives(unit);
}

void Update(uint32_t now) {
    Driving& d = g_driving;
    if (!g_puffs.empty()) {
        moveDust(g_dustAt ? std::min(static_cast<float>(now - g_dustAt) * 0.001f, 0.1f) : 0.0f);
    }
    g_dustAt = now;
    CGUnit_C* mover = static_cast<CGUnit_C*>(ClntObjMgrObjectPtr(CGUnit_C::s_activeMover, TYPEMASK_UNIT, __FILE__, __LINE__));
    CGUnit_C* unit = jeepOf(mover);

    if (d.driving && (!unit || unit->m_obj->m_guid != d.unit)) {
        stop(d, now);
    }
    if (!unit) {
        return;
    }

    CMovement_C* movement = unit->m_movement;

    if (!d.driving) {
        if (!begin(d, movement->m_position.x, movement->m_position.y, movement->m_position.z, movement->m_facing)) {
            return;
        }
        d.driving = true;
        d.unit = unit->m_obj->m_guid;
        d.lastAt = now;
        d.footWas[0] = movement->m_position.x;
        d.footWas[1] = movement->m_position.y;
        d.footWas[2] = movement->m_position.z;
        // What the game had begun of its own movement ends here, and the server is told so at once.
        d.moved = (movement->m_flags & MOVING) != 0;
        movement->m_flags &= ~MOVING;
        ConsolePrintf("Jeep: driving (the ground asked with 0x%X)", d.groundFlags);
    }

    const float dt = std::min(static_cast<float>(now - d.lastAt) * 0.001f, 0.05f);
    d.lastAt = now;

    // Put somewhere else by the game (a teleport, a summons, a hearthstone): it begins again there.
    const C3Vector& was = movement->m_position;
    if (std::fabs(was.x - d.footWas[0]) + std::fabs(was.y - d.footWas[1]) + std::fabs(was.z - d.footWas[2]) > 6.0f) {
        ConsolePrintf("Jeep: put elsewhere by the game; it begins again there");
        if (!begin(d, was.x, was.y, was.z, movement->m_facing)) {
            stop(d, now);
            return;
        }
    }

    // What the player asks for.
    CGInputControl* input = CGInputControl::GetActive();
    const uint32_t keys = input ? input->m_flags : 0;
    const float throttle = ((keys & (0x10 | 0x1000)) ? 1.0f : 0.0f) - ((keys & 0x20) ? 1.0f : 0.0f);
    const float steering = ((keys & 0x100) ? 1.0f : 0.0f) - ((keys & 0x200) ? 1.0f : 0.0f);

    physics(d, dt, throttle, steering);
    throwDust(d, dt);

    // The game: the unit where the body's foot is, facing the way the body points.
    const float front[3] = { d.axes[0][0], d.axes[1][0], d.axes[2][0] };
    const float origin[3] = { 0, 0, 0 };
    bodyPoint(d, origin, d.foot);
    std::memcpy(d.footWas, d.foot, sizeof d.footWas);
    movement->m_flags &= ~MOVING;
    movement->m_position = C3Vector(d.foot[0], d.foot[1], d.foot[2]);
    movement->m_facing = std::atan2(front[1], front[0]);
    d.placed = true;
    unit->OnMoveUpdate(now, 0, 0);
    soundJeep(d, dt, throttle);

    // The server: where it is, ten times a second while it moves, and once more when it stops.
    const float speed = std::sqrt(dot(d.v, d.v));
    if (now - d.toldAt > 100 && (speed > 0.2f || d.moved)) {
        if (speed > 0.2f) {
            movement->m_flags |= FORWARD;
        }
        unit->SendMovementUpdate(now, MSG_MOVE_HEARTBEAT, 0.0f, 0, 0, 255);
        movement->m_flags &= ~MOVING;
        d.moved = speed > 0.2f;
        d.toldAt = now;
        ++d.told;
    }

    if (now - d.saidAt > 5000) {
        ConsolePrintf("Jeep: %.1f yd/s, springs %.2f %.2f %.2f %.2f, steer %.2f, %u heartbeat(s), %u frame(s) drawn by it; %u thump(s); dust: %u thrown, %u in the air, the ground's colour %.2f %.2f %.2f",
            speed, d.wheels[0].length, d.wheels[1].length, d.wheels[2].length, d.wheels[3].length, d.steer, d.told, d.animated, d.thumps,
            g_dustThrown, static_cast<unsigned>(g_puffs.size()), g_wheelEarth[3][0], g_wheelEarth[3][1], g_wheelEarth[3][2]);
        d.saidAt = now;
    }
}

bool Animate(CGUnit_C* unit) {
    Driving& d = g_driving;
    if (!Drives(unit) || !d.placed) {
        return false;
    }
    CM2Model* model = unit->GetObjectModel();
    if (!model) {
        return false;
    }
    // The body: its axes as the model's (rows: where the model's x, y and z go), at its foot.
    const float scale = unit->GetTrueScale();
    const C44Matrix body(
        d.axes[0][0] * scale, d.axes[1][0] * scale, d.axes[2][0] * scale, 0.0f,
        d.axes[0][1] * scale, d.axes[1][1] * scale, d.axes[2][1] * scale, 0.0f,
        d.axes[0][2] * scale, d.axes[1][2] * scale, d.axes[2][2] * scale, 0.0f,
        d.foot[0], d.foot[1], d.foot[2], 1.0f);
    model->SetWorldTransform(body);

    // Each wheel: turned about its own middle (its bone's pivot) by the steering and by how far it has rolled,
    // and moved up or down the body by its spring: in the body's own space, which the game puts before the bone's
    // own animation (which, standing, does nothing).
    for (int i = 0; i < 4; ++i) {
        const Wheel& wheel = d.wheels[i];
        const float turn = i < 2 ? d.steerAngle : 0.0f;
        const float ct = std::cos(turn), st = std::sin(turn), cs = std::cos(wheel.spin), ss = std::sin(wheel.spin);
        // R = Rz(turn) * Ry(spin), for a point as a column; as the game's rows: where x, y and z go.
        const float r[3][3] = { { ct * cs, -st, ct * ss }, { st * cs, ct, st * ss }, { -ss, 0.0f, cs } };
        const float lift = ATTACH - wheel.length - WHEEL_RADIUS;
        const C44Matrix turned(
            r[0][0], r[1][0], r[2][0], 0.0f,
            r[0][1], r[1][1], r[2][1], 0.0f,
            r[0][2], r[1][2], r[2][2], 0.0f,
            0.0f, 0.0f, lift, 1.0f);
        model->SetBoneProceduralTransformAt(static_cast<uint32_t>(i + 1), &turned);
    }
    ++d.animated;
    return true;
}

void RenderDust() {
    if (g_puffs.empty()) {
        return;
    }
    CGxTex* texture = puffTexture();
    if (!texture) {
        return;
    }
    // Lit as the ground is: the game's light of the hour and the place (ambient, and the sun's in part).
    const DayNight::DNInfo* info = DayNight::GetInfo();
    float light[3] = { 1.0f, 1.0f, 1.0f };
    if (info) {
        const CImVector& ambient = info->m_light0.m_ambient;
        const CImVector& diffuse = info->m_light0.m_diffuse;
        light[0] = (ambient.r + diffuse.r * 0.6f) / 255.0f;
        light[1] = (ambient.g + diffuse.g * 0.6f) / 255.0f;
        light[2] = (ambient.b + diffuse.b * 0.6f) / 255.0f;
        for (float& part : light) {
            part = std::max(0.12f, std::min(1.4f, part));
        }
    }
    // Dust is the ground made fine and dry: paler, and a little toward grey; a clod is the ground itself, darker.
    float dust[4][3], clod[4][3];
    for (int i = 0; i < 4; ++i) {
        const float* earth = g_wheelEarth[i];
        const float grey = earth[0] * 0.30f + earth[1] * 0.55f + earth[2] * 0.15f;
        for (int k = 0; k < 3; ++k) {
            dust[i][k] = std::min(1.0f, ((earth[k] + (grey - earth[k]) * 0.3f) * 1.25f + 0.04f) * light[k]);
            clod[i][k] = std::min(1.0f, earth[k] * 0.55f * light[k]);
        }
    }

    // Squares before the eye: the view's right and up, as the game's mist has them.
    C44Matrix view;
    GxXformView(view);
    const C3Vector right(view.a0, view.b0, view.c0), up(view.a1, view.b1, view.c1);
    const C3Vector& eye = CWorldScene::s_activeWorldView;
    const bool rgba = g_theGxDevicePtr->Caps().m_colorFormat == GxCF_rgba;
    static const C2Vector CORNER_UV[4] = { C2Vector(0.0f, 0.0f), C2Vector(1.0f, 0.0f), C2Vector(1.0f, 1.0f), C2Vector(0.0f, 1.0f) };
    static const float CORNER_AT[4][2] = { { -1.0f, 1.0f }, { 1.0f, 1.0f }, { 1.0f, -1.0f }, { -1.0f, -1.0f } };

    const uint32_t most = static_cast<uint32_t>(std::min<size_t>(g_puffs.size(), 16000 / 4));
    CGxBuf* vertexBuf = g_theGxDevicePtr->BufStream(GxPoolTarget_Vertex, sizeof(CGxVertexPCT), 4 * most);
    CGxVertexPCT* vertices = reinterpret_cast<CGxVertexPCT*>(g_theGxDevicePtr->BufLock(vertexBuf));
    CGxBuf* indexBuf = g_theGxDevicePtr->BufStream(GxPoolTarget_Index, sizeof(uint16_t), 6 * most);
    uint16_t* indices = reinterpret_cast<uint16_t*>(g_theGxDevicePtr->BufLock(indexBuf));
    uint32_t vertexCount = 0;
    for (const Puff& puff : g_puffs) {
        if (vertexCount / 4 >= most) {
            break;
        }
        const C3Vector at(puff.at[0] - eye.x, puff.at[1] - eye.y, puff.at[2] - eye.z);
        const float share = puff.age / puff.life;
        float much = puff.clod ? 0.95f * std::min(1.0f, (1.0f - share) * 4.0f)
                               : 0.45f * std::pow(1.0f - share, 1.3f) * std::min(1.0f, puff.age * 10.0f);
        // (Faded where it comes near the eye: else it is a cloud over the whole screen.)
        const float away = std::sqrt(at.x * at.x + at.y * at.y + at.z * at.z);
        much *= std::max(0.0f, std::min(1.0f, (away - 1.5f) / 3.0f));
        if (much < 0.01f) {
            continue;
        }
        const float* tint = puff.clod ? clod[puff.wheel] : dust[puff.wheel];
        CImVector colour;
        colour.r = static_cast<uint8_t>(tint[0] * 255.0f);
        colour.g = static_cast<uint8_t>(tint[1] * 255.0f);
        colour.b = static_cast<uint8_t>(tint[2] * 255.0f);
        colour.a = static_cast<uint8_t>(std::min(1.0f, much) * 255.0f);
        if (rgba) {
            std::swap(colour.r, colour.b);
        }
        // Its square turned by its own angle, so that no two show their lumps alike.
        const float c = std::cos(puff.turn) * puff.size, s = std::sin(puff.turn) * puff.size;
        const C3Vector across(right.x * c + up.x * s, right.y * c + up.y * s, right.z * c + up.z * s);
        const C3Vector upward(up.x * c - right.x * s, up.y * c - right.y * s, up.z * c - right.z * s);
        for (int j = 0; j < 4; ++j) {
            vertices->p = C3Vector(at.x + across.x * CORNER_AT[j][0] + upward.x * CORNER_AT[j][1],
                                   at.y + across.y * CORNER_AT[j][0] + upward.y * CORNER_AT[j][1],
                                   at.z + across.z * CORNER_AT[j][0] + upward.z * CORNER_AT[j][1]);
            vertices->c = colour;
            vertices->tc = CORNER_UV[j];
            ++vertices;
        }
        indices[0] = static_cast<uint16_t>(vertexCount);
        indices[1] = static_cast<uint16_t>(vertexCount + 1);
        indices[2] = static_cast<uint16_t>(vertexCount + 2);
        indices[3] = static_cast<uint16_t>(vertexCount);
        indices[4] = static_cast<uint16_t>(vertexCount + 2);
        indices[5] = static_cast<uint16_t>(vertexCount + 3);
        indices += 6;
        vertexCount += 4;
    }
    GxBufUnlock(indexBuf, 0);
    GxBufUnlock(vertexBuf, 0);
    if (!vertexCount) {
        return;
    }
    g_theGxDevicePtr->RsPush();
    GxRsSet(GxRs_BlendingMode, GxBlend_Alpha);
    GxRsSet(GxRs_AlphaRef, static_cast<int32_t>(CGxDevice::s_alphaRef[g_theGxDevicePtr->m_appRenderStates.m_data[GxRs_BlendingMode].m_value.m_data.i[0]]));
    GxRsSet(GxRs_Fog, 0);
    GxRsSet(GxRs_DepthWrite, 0);
    GxRsSet(GxRs_Culling, 0);
    GxRsSet(GxRs_Lighting, 0);
    GxRsSet(GxRs_Texture0, texture);
    GxPrimVertexPtr(vertexBuf, GxVBF_PCT);
    g_theGxDevicePtr->PrimIndexPtr(indexBuf);
    CGxBatch batch;
    batch.m_primType = GxPrim_Triangles;
    batch.m_start = 0;
    batch.m_count = (6 * vertexCount) / 4;
    batch.m_minIndex = 0;
    batch.m_maxIndex = vertexCount - 1;
    g_theGxDevicePtr->Draw(&batch, 1);
    g_theGxDevicePtr->RsPop();
}

}  // namespace JeepDrive
