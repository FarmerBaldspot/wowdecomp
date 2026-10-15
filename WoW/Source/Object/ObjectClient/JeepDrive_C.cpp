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
// The server is told where the jeep is by heartbeats, ten times a second while it moves and once when it stops.

#include "WoW/Source/Object/ObjectClient/JeepDrive_C.h"
#include "Engine/Source/ConsoleBase/IConsole.h"
#include "Engine/Source/Model2/M2Model.h"
#include "Engine/Source/Os/TimeManager.h"
#include "Engine/Source/Tempest/C44Matrix.h"
#include "WoW/Source/Net/Types.h"
#include "WoW/Source/Object/Movement.h"
#include "WoW/Source/Object/Types.h"
#include "WoW/Source/Object/ObjectClient/Unit_C.h"
#include "WoW/Source/ObjectMgrClient/ObjectMgrClient.h"
#include "WoW/Source/UIUtil/InputControl.h"
#include "WoW/Source/WorldClient/World.h"
#include <algorithm>
#include <cmath>
#include <cstring>

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

void stop(Driving& d, uint32_t now) {
    if (!d.driving) {
        return;
    }
    CGUnit_C* unit = static_cast<CGUnit_C*>(ClntObjMgrObjectPtr(d.unit, TYPEMASK_UNIT, __FILE__, __LINE__));
    freeWheels(unit);
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

}  // namespace

bool Drives(const CGUnit_C* unit) {
    return g_driving.driving && unit && unit->m_obj && unit->m_obj->m_guid == g_driving.unit;
}

bool HidesRider(const CGUnit_C* unit) {
    return Drives(unit);
}

void Update(uint32_t now) {
    Driving& d = g_driving;
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
        ConsolePrintf("Jeep: %.1f yd/s, springs %.2f %.2f %.2f %.2f, steer %.2f, %u heartbeat(s), %u frame(s) drawn by it",
            speed, d.wheels[0].length, d.wheels[1].length, d.wheels[2].length, d.wheels[3].length, d.steer, d.told, d.animated);
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

}  // namespace JeepDrive
