//! Asteroids, played among photographed moon rocks above a gas giant. A
//! game built from the SDK's libraries together: limn draws it, slime holds
//! the rocks and shots as entities, keybinds turns keys into actions, and
//! audio plays the sounds.
//!
//!   A/D or Left/Right  turn
//!   W or Up            thrust
//!   Space              fire
//!   Enter              play again once the ships are gone
//!
//! Large rocks break into two medium ones, medium into two small, and small
//! ones into dust. Clearing a wave brings the next, with one rock more.
//!
//! `--demo 1` lets the ship fly itself. `--frames N`, `--screenshot file.png`.
const std = @import("std");
const gfx = @import("limn");
const math = gfx.math;
const glfw = @import("glfw");
const slime = @import("slime");
const keybinds = @import("keybinds");
const audio = @import("audio");
const window = @import("window");
const Stage = window.Stage;
const TextOptions = gfx.TextOptions;

/// The camera, fixed above the middle of the field.
const eye = math.Vec3{ 0, 34, 5 };
const look_at = math.Vec3{ 0, 0, 0.6 };
const fov_y: f32 = std.math.degreesToRadians(50.0);
/// Least and greatest X and Z where rocks are in play: what the camera sees
/// of the plane of play in a 16:9 window, and room for the largest rock
/// beyond, so that a rock leaving one side comes back on the other out of
/// sight.
const field = visibleField(16.0 / 9.0, 4.5, .around);
/// Where the ship and its shots are in play: they come back as soon as they
/// leave the picture, so the player never loses sight of the ship.
const view = visibleField(16.0 / 9.0, 0.5, .within);
const ship_scale = 2.4;
const ship_radius = 1.7;
const turn_rate = 4.2;
const thrust_accel = 30;
const ship_drag = 0.55;
const max_speed = 26;
const shot_speed = 46;
const shot_life = 0.85;
const shot_cooldown = 0.16;
const max_shots = 8;
const respawn_delay = 2.0;
const invulnerable_time = 2.5;
const start_lives = 3;
const extra_life_every = 10_000;
/// Explosions in flight at once, each with its own emitters and light.
const blast_count = 6;
const rock_files = [_][]const u8{
    "examples/assets/asteroids_game/rock_1.glb",
    "examples/assets/asteroids_game/rock_2.glb",
    "examples/assets/asteroids_game/rock_3.glb",
    "examples/assets/asteroids_game/rock_4.glb",
    "examples/assets/asteroids_game/rock_5.glb",
    "examples/assets/asteroids_game/rock_6.glb",
    "examples/assets/asteroids_game/rock_7.glb",
};

const Action = enum { turn, thrust, fire, start };

/// The default controls, in keybinds' text format; a player's own could be
/// loaded over them.
const bindings =
    \\turn = d
    \\turn = right
    \\turn = a, scale -1
    \\turn = left, scale -1
    \\thrust = w
    \\thrust = up
    \\fire = space
    \\start = enter
;

/// GLFW keys the game reads, and what keybinds calls them.
const watched_keys = [_]struct { glfw: c_int, key: keybinds.Key }{
    .{ .glfw = glfw.GLFW_KEY_A, .key = .a },
    .{ .glfw = glfw.GLFW_KEY_D, .key = .d },
    .{ .glfw = glfw.GLFW_KEY_W, .key = .w },
    .{ .glfw = glfw.GLFW_KEY_LEFT, .key = .left },
    .{ .glfw = glfw.GLFW_KEY_RIGHT, .key = .right },
    .{ .glfw = glfw.GLFW_KEY_UP, .key = .up },
    .{ .glfw = glfw.GLFW_KEY_SPACE, .key = .space },
    .{ .glfw = glfw.GLFW_KEY_ENTER, .key = .enter },
};

const Keymap = keybinds.Keymap(Action, void);

/// Where something is in the field and how it moves.
const Body = struct {
    position: math.Vec3,
    velocity: math.Vec3,
    /// For collisions, in the plane of the field.
    radius: f32,
};

const Size = enum(u2) {
    large,
    medium,
    small,

    fn radius(size: Size) f32 {
        return switch (size) {
            .large => 3.4,
            .medium => 1.9,
            .small => 1.0,
        };
    }

    fn points(size: Size) u32 {
        return switch (size) {
            .large => 20,
            .medium => 50,
            .small => 100,
        };
    }
};

const Rock = struct {
    size: Size,
    axis: math.Vec3,
    /// Radians per second about `axis`, and how far it has turned.
    spin: f32,
    angle: f32,
};

const Shot = struct {
    /// Seconds left before it fades.
    life: f32,
};

/// The limn entity that draws a slime entity.
/// What the player or the demo asks of the ship this frame.
const Pilot = struct {
    turn: f32,
    thrust: bool,
    fire: bool,
};

const Look = struct {
    entity: gfx.Entity,
};

/// One explosion's particles and flash, reused round robin.
const Blast = struct {
    sparks: gfx.Emitter,
    dust: gfx.Emitter,
    position: math.Vec3 = .{ 0, 0, 0 },
    /// Seconds since it went off; the flash fades over the first half.
    age: f32 = 10,
    strength: f32 = 0,
};

const Sounds = struct {
    engine: audio.Engine,
    shoot: audio.Sound,
    breaks: [3]audio.Sound,
    ship_lost: audio.Sound,
    respawn: audio.Sound,
    thrust: audio.Voice,

    /// Null where there is no audio device; the game plays silent.
    fn init(gpa: std.mem.Allocator, io: std.Io) ?Sounds {
        var engine = audio.Engine.init(gpa, .{}) catch |err| {
            std.log.warn("no sound: {t}", .{err});
            return null;
        };
        return load(&engine, io) catch |err| {
            std.log.warn("no sound: {t}", .{err});
            engine.deinit();
            return null;
        };
    }

    fn load(engine: *audio.Engine, io: std.Io) !Sounds {
        const dir = std.Io.Dir.cwd();
        const base = "examples/assets/asteroids_game/sounds/";
        const thrust = try engine.loadFile(io, dir, base ++ "thrust.wav", .{});
        const shoot = try engine.loadFile(io, dir, base ++ "shoot.wav", .{});
        const breaks = [3]audio.Sound{
            try engine.loadFile(io, dir, base ++ "break_large.wav", .{}),
            try engine.loadFile(io, dir, base ++ "break_medium.wav", .{}),
            try engine.loadFile(io, dir, base ++ "break_small.wav", .{}),
        };
        const ship_lost = try engine.loadFile(io, dir, base ++ "ship_lost.wav", .{});
        const respawn = try engine.loadFile(io, dir, base ++ "respawn.wav", .{});
        const thrust_voice = try engine.play(thrust, .{ .looping = true, .volume = 0 });
        return .{
            .engine = engine.*,
            .shoot = shoot,
            .breaks = breaks,
            .ship_lost = ship_lost,
            .respawn = respawn,
            .thrust = thrust_voice,
        };
    }

    fn play(self: *Sounds, sound: audio.Sound, volume: f32, pitch: f32) void {
        _ = self.engine.play(sound, .{ .volume = volume, .pitch = pitch }) catch {};
    }
};

const Game = struct {
    gpa: std.mem.Allocator,
    renderer: *gfx.Renderer,
    scene: gfx.Scene,
    world: slime.World,
    rng: std.Random,
    /// The ship flies itself and nothing destroys it.
    demo: bool,
    sounds: ?Sounds,
    rock_models: [rock_files.len]gfx.Model,
    shot_model: gfx.Model,
    ship: gfx.Entity,
    planet: gfx.Entity,
    flame: gfx.Emitter,
    blasts: [blast_count]Blast,
    next_blast: usize = 0,

    position: math.Vec3 = .{ 0, 0, 0 },
    velocity: math.Vec3 = .{ 0, 0, 0 },
    /// Radians; zero faces the far edge of the field.
    heading: f32 = 0,
    /// Sideways lean while turning, for looks.
    bank: f32 = 0,
    thrusting: bool = false,
    /// The ship is in play; false while waiting to come back.
    alive: bool = true,
    respawn_in: f32 = 0,
    invulnerable: f32 = invulnerable_time,
    cooldown: f32 = 0,
    lives: u32 = start_lives,
    score: u32 = 0,
    next_extra_life: u32 = extra_life_every,
    wave: u32 = 0,
    shake: f32 = 0,
    clock: f32 = 0,

    fn forward(self: *const Game) math.Vec3 {
        return .{ -@sin(self.heading), 0, -@cos(self.heading) };
    }

    fn startWave(self: *Game) !void {
        self.wave += 1;
        for (0..self.wave + 3) |_| {
            var position: math.Vec3 = undefined;
            while (true) {
                position = .{ std.math.lerp(field[0][0], field[1][0], self.rng.float(f32)), 0, std.math.lerp(field[0][1], field[1][1], self.rng.float(f32)) };
                if (math.length(math.sub(position, self.position)) > 14) break;
            }
            try self.spawnRock(.large, position, self.driftFor(.large));
        }
    }

    /// A random velocity in the plane, faster for smaller rocks and later waves.
    fn driftFor(self: *Game, size: Size) math.Vec3 {
        const angle = self.rng.float(f32) * std.math.tau;
        const base: f32 = switch (size) {
            .large => 3.0,
            .medium => 5.5,
            .small => 8.5,
        };
        const speed = (base + self.rng.float(f32) * 2.5) * (1 + 0.08 * @as(f32, @floatFromInt(self.wave - 1)));
        return .{ @cos(angle) * speed, 0, @sin(angle) * speed };
    }

    fn spawnRock(self: *Game, size: Size, position: math.Vec3, velocity: math.Vec3) !void {
        const grey = 0.42 + self.rng.float(f32) * 0.2;
        const warmth = self.rng.float(f32) * 0.12;
        const look = try self.renderer.entities.create(self.scene, .{
            .model = self.rock_models[self.rng.uintLessThan(usize, rock_files.len)],
            .tint = .{ grey + warmth, grey, grey - warmth },
        });
        const axis = math.normalize(.{ self.rng.float(f32) - 0.5, self.rng.float(f32) - 0.5, self.rng.float(f32) - 0.5 });
        const radius = size.radius() * (0.9 + self.rng.float(f32) * 0.25);
        try self.world.commands().spawn(.{
            Body{ .position = position, .velocity = velocity, .radius = radius * 0.82 },
            Rock{ .size = size, .axis = axis, .spin = (self.rng.float(f32) - 0.5) * 2.4, .angle = self.rng.float(f32) * std.math.tau },
            Look{ .entity = look },
        });
    }

    fn fire(self: *Game) !void {
        var shots = self.world.query(&.{Shot});
        if (shots.count() >= max_shots) return;
        const direction = self.forward();
        const position = math.add(self.position, math.scale(direction, 2.0));
        const look = try self.renderer.entities.create(self.scene, .{ .model = self.shot_model, .transform = shotTransform(position, self.heading) });
        try self.world.commands().spawn(.{
            Body{ .position = position, .velocity = math.add(self.velocity, math.scale(direction, shot_speed)), .radius = 0.3 },
            Shot{ .life = shot_life },
            Look{ .entity = look },
        });
        self.cooldown = shot_cooldown;
        if (self.sounds) |*sounds| sounds.play(sounds.shoot, 0.45, 0.95 + self.rng.float(f32) * 0.1);
    }

    fn explode(self: *Game, position: math.Vec3, strength: f32) void {
        const blast = &self.blasts[self.next_blast];
        self.next_blast = (self.next_blast + 1) % blast_count;
        blast.position = position;
        blast.age = 0;
        blast.strength = strength;
        var sparks = sparkDesc(position);
        var dust = dustDesc(position);
        sparks.speed = .{ 6 * strength, 18 * strength };
        dust.speed = .{ 1.5 * strength, 6 * strength };
        dust.size = .{ 0.3 * strength, 1.1 * strength };
        self.renderer.emitters.set(blast.sparks, sparks);
        self.renderer.emitters.set(blast.dust, dust);
        self.renderer.emitters.burst(blast.sparks, @intFromFloat(90 * strength));
        self.renderer.emitters.burst(blast.dust, @intFromFloat(70 * strength));
        self.shake = @max(self.shake, 0.35 * strength);
    }

    /// Moves every rock and shot, and brings back whatever left its bounds.
    fn moveBodies(self: *Game, dt: f32) void {
        var rocks = self.world.query(&.{ Body, Rock });
        while (rocks.next()) |chunk| for (chunk.slice(Body)) |*body| {
            body.position = wrap(math.add(body.position, math.scale(body.velocity, dt)), field);
        };
        var shots = self.world.query(&.{ Body, Shot });
        while (shots.next()) |chunk| for (chunk.slice(Body)) |*body| {
            body.position = wrap(math.add(body.position, math.scale(body.velocity, dt)), view);
        };
    }

    fn spinRocks(self: *Game, dt: f32) void {
        var rocks = self.world.query(&.{ Body, Rock, Look });
        while (rocks.next()) |chunk| for (chunk.slice(Body), chunk.slice(Rock), chunk.slice(Look)) |body, *rock, look| {
            rock.angle += rock.spin * dt;
            const turned = math.fromQuat(math.quatFromAxisAngle(rock.axis, rock.angle));
            self.renderer.entities.setTransform(look.entity, math.mul(math.translation(body.position), math.mul(turned, math.uniformScaling(body.radius / 0.82))));
        };
    }

    fn ageShots(self: *Game, dt: f32) !void {
        var shots = self.world.query(&.{ Body, Shot, Look });
        while (shots.next()) |chunk| for (chunk.entities(), chunk.slice(Body), chunk.slice(Shot), chunk.slice(Look)) |entity, body, *shot, look| {
            shot.life -= dt;
            if (shot.life <= 0) {
                self.renderer.entities.destroy(look.entity);
                try self.world.commands().despawn(entity);
                continue;
            }
            const heading = std.math.atan2(-body.velocity[0], -body.velocity[2]);
            self.renderer.entities.setTransform(look.entity, shotTransform(body.position, heading));
        };
    }

    /// Shots against rocks, then rocks against the ship. Broken rocks and
    /// spent shots leave through slime's commands, after the queries.
    fn collide(self: *Game) !void {
        const Target = struct { entity: slime.Entity, body: Body, rock: Rock, look: Look, hit: bool = false };
        var targets: std.ArrayList(Target) = .empty;
        defer targets.deinit(self.gpa);
        var rocks = self.world.query(&.{ Body, Rock, Look });
        while (rocks.next()) |chunk| for (chunk.entities(), chunk.slice(Body), chunk.slice(Rock), chunk.slice(Look)) |entity, body, rock, look| {
            try targets.append(self.gpa, .{ .entity = entity, .body = body, .rock = rock, .look = look });
        };

        var shots = self.world.query(&.{ Body, Shot, Look });
        while (shots.next()) |chunk| for (chunk.entities(), chunk.slice(Body), chunk.slice(Look)) |entity, body, look| {
            for (targets.items) |*target| {
                if (target.hit or !touching(body, target.body)) continue;
                target.hit = true;
                self.renderer.entities.destroy(look.entity);
                try self.world.commands().despawn(entity);
                try self.breakRock(target.entity, target.body, target.rock, target.look, body.velocity);
                break;
            }
        };

        if (!self.alive or self.invulnerable > 0 or self.demo) return;
        const ship = Body{ .position = self.position, .velocity = self.velocity, .radius = ship_radius };
        for (targets.items) |*target| {
            if (target.hit or !touching(ship, target.body)) continue;
            target.hit = true;
            try self.breakRock(target.entity, target.body, target.rock, target.look, self.velocity);
            try self.loseShip();
            return;
        }
    }

    fn breakRock(self: *Game, entity: slime.Entity, body: Body, rock: Rock, look: Look, push: math.Vec3) !void {
        self.renderer.entities.destroy(look.entity);
        try self.world.commands().despawn(entity);
        self.addScore(rock.size.points());
        const strength: f32 = switch (rock.size) {
            .large => 1.6,
            .medium => 1.1,
            .small => 0.7,
        };
        self.explode(body.position, strength);
        if (self.sounds) |*sounds| sounds.play(sounds.breaks[@backingInt(rock.size)], 0.8, 0.9 + self.rng.float(f32) * 0.2);
        const smaller: Size = switch (rock.size) {
            .large => .medium,
            .medium => .small,
            .small => return,
        };
        const nudge = math.scale(push, 0.06);
        for (0..2) |_| try self.spawnRock(smaller, body.position, math.add(self.driftFor(smaller), nudge));
    }

    fn loseShip(self: *Game) !void {
        self.alive = false;
        self.thrusting = false;
        self.renderer.entities.setVisible(self.ship, false);
        self.explode(self.position, 2.2);
        self.shake = 1.2;
        if (self.sounds) |*sounds| sounds.play(sounds.ship_lost, 1, 1);
        self.lives -= 1;
        self.respawn_in = respawn_delay;
    }

    fn addScore(self: *Game, points: u32) void {
        self.score += points;
        if (self.score >= self.next_extra_life) {
            self.lives += 1;
            self.next_extra_life += extra_life_every;
        }
    }

    /// Brings the ship back in the middle once nothing is close to it.
    fn tryRespawn(self: *Game) bool {
        var rocks = self.world.query(&.{ Body, Rock });
        while (rocks.next()) |chunk| for (chunk.slice(Body)) |body| {
            if (math.length(body.position) < body.radius + 7) return false;
        };
        self.alive = true;
        self.position = .{ 0, 0, 0 };
        self.velocity = .{ 0, 0, 0 };
        self.heading = 0;
        self.invulnerable = invulnerable_time;
        self.renderer.entities.setVisible(self.ship, true);
        if (self.sounds) |*sounds| sounds.play(sounds.respawn, 0.6, 1);
        return true;
    }

    fn restart(self: *Game) !void {
        var everything = self.world.query(&.{Look});
        while (everything.next()) |chunk| for (chunk.entities(), chunk.slice(Look)) |entity, look| {
            self.renderer.entities.destroy(look.entity);
            try self.world.commands().despawn(entity);
        };
        try self.world.applyCommands();
        self.lives = start_lives;
        self.score = 0;
        self.next_extra_life = extra_life_every;
        self.wave = 0;
        self.respawn_in = 0;
        self.position = .{ 0, 0, 0 };
        _ = self.tryRespawn();
        try self.startWave();
    }

    fn steerShip(self: *Game, turn: f32, thrust: bool, dt: f32) void {
        self.heading -= turn * turn_rate * dt;
        self.bank += (turn * 0.55 - self.bank) * @min(dt * 8, 1);
        self.thrusting = thrust;
        if (thrust) self.velocity = math.add(self.velocity, math.scale(self.forward(), thrust_accel * dt));
        self.velocity = math.scale(self.velocity, @exp(-ship_drag * dt));
        const speed = math.length(self.velocity);
        if (speed > max_speed) self.velocity = math.scale(self.velocity, max_speed / speed);
        self.position = wrap(math.add(self.position, math.scale(self.velocity, dt)), view);
    }

    /// The demo's pilot: turns toward the nearest rock, closes in on it
    /// when it is far, and fires when it points close enough.
    fn autopilot(self: *Game) Pilot {
        var nearest: ?math.Vec3 = null;
        var best: f32 = std.math.inf(f32);
        var rocks = self.world.query(&.{ Body, Rock });
        while (rocks.next()) |chunk| for (chunk.slice(Body)) |body| {
            const distance = math.length(math.sub(body.position, self.position));
            if (distance < best) {
                best = distance;
                nearest = body.position;
            }
        };
        const target = nearest orelse return .{ .turn = 0, .thrust = false, .fire = false };
        const to = math.sub(target, self.position);
        const wanted = std.math.atan2(-to[0], -to[2]);
        var difference = wanted - self.heading;
        while (difference > std.math.pi) difference -= std.math.tau;
        while (difference < -std.math.pi) difference += std.math.tau;
        return .{ .turn = std.math.clamp(-difference * 3, -1, 1), .thrust = best > 16 and @abs(difference) < 0.5, .fire = @abs(difference) < 0.12 };
    }

    fn updateEffects(self: *Game, dt: f32) !void {
        const visible = self.alive and (self.invulnerable <= 0 or @mod(self.clock, 0.2) < 0.13);
        self.renderer.entities.setVisible(self.ship, visible);
        const turned = math.mul(math.rotationY(self.heading), math.rotationZ(self.bank));
        self.renderer.entities.setTransform(self.ship, math.mul(math.translation(self.position), math.mul(turned, math.uniformScaling(ship_scale))));

        const back = math.scale(self.forward(), -1);
        var flame = flameDesc(math.add(self.position, math.scale(back, 1.55)), back);
        flame.rate = if (self.thrusting and self.alive) 480 else 0;
        self.renderer.emitters.set(self.flame, flame);
        if (self.sounds) |*sounds| sounds.engine.setVolume(sounds.thrust, if (self.thrusting and self.alive) 0.35 else 0) catch {};

        var lights: [blast_count + max_shots + 2]gfx.LightDesc = undefined;
        var count: usize = 0;
        lights[count] = .{ .kind = .directional, .position = .{ 0, 0, 0 }, .direction = math.normalize(.{ 0.6, -0.45, 0.55 }), .color = .{ 0.4, 0.55, 1.0 }, .intensity = 0.9 };
        count += 1;
        if (self.thrusting and self.alive) {
            lights[count] = .{ .position = math.add(self.position, math.scale(back, 2.2)), .color = .{ 1.0, 0.55, 0.2 }, .intensity = 18 + 6 * @sin(self.clock * 60), .range = 9 };
            count += 1;
        }
        for (&self.blasts) |*blast| {
            blast.age += dt;
            const fade = 1 - blast.age / (0.5 * blast.strength);
            if (fade <= 0) continue;
            lights[count] = .{ .position = math.add(blast.position, .{ 0, 1.5, 0 }), .color = .{ 1.0, 0.6, 0.3 }, .intensity = 260 * blast.strength * fade * fade, .range = 14 * blast.strength };
            count += 1;
        }
        var shots = self.world.query(&.{ Body, Shot });
        while (shots.next()) |chunk| for (chunk.slice(Body)) |body| {
            if (count == lights.len) break;
            lights[count] = .{ .position = body.position, .color = .{ 0.3, 0.8, 1.0 }, .intensity = 5, .range = 5 };
            count += 1;
        };
        try self.renderer.scenes.setLights(self.scene, lights[0..count]);

        self.renderer.entities.setTransform(self.planet, planetTransform(self.clock));
        self.shake = @max(self.shake - dt * 2.2, 0);
    }

    fn rocksLeft(self: *Game) usize {
        var rocks = self.world.query(&.{Rock});
        return rocks.count();
    }
};

fn wrap(position: math.Vec3, bounds: [2][2]f32) math.Vec3 {
    var result = position;
    for ([_]usize{ 0, 2 }, bounds[0], bounds[1]) |axis, low, high| {
        if (result[axis] > high) result[axis] -= high - low;
        if (result[axis] < low) result[axis] += high - low;
    }
    return result;
}

/// The tilted camera sees a trapezoid of the plane of play, wider at the far edge.
const Fit = enum {
    /// The rectangle around the trapezoid: nothing seen lies outside it.
    around,
    /// The widest rectangle inside it: everything in it is seen.
    within,
};

/// The rectangle of the plane of play the camera sees, as `fit` says, grown
/// by `margin` on every side: least and greatest X and Z.
fn visibleField(aspect: f32, margin: f32, fit: Fit) [2][2]f32 {
    const forward = math.normalize(math.sub(look_at, eye));
    const right = math.normalize(math.cross(forward, .{ 0, 1, 0 }));
    const up = math.cross(right, forward);
    const reach = @tan(fov_y / 2);
    var low: [2]f32 = .{ if (fit == .around) std.math.inf(f32) else -std.math.inf(f32), std.math.inf(f32) };
    var high: [2]f32 = .{ if (fit == .around) -std.math.inf(f32) else std.math.inf(f32), -std.math.inf(f32) };
    for ([_]f32{ -1, 1 }) |across| for ([_]f32{ -1, 1 }) |down| {
        const ray = math.add(forward, math.add(math.scale(right, across * reach * aspect), math.scale(up, down * reach)));
        const hit = math.add(eye, math.scale(ray, -eye[1] / ray[1]));
        if (across < 0) low[0] = if (fit == .around) @min(low[0], hit[0]) else @max(low[0], hit[0]);
        if (across > 0) high[0] = if (fit == .around) @max(high[0], hit[0]) else @min(high[0], hit[0]);
        low[1] = @min(low[1], hit[2]);
        high[1] = @max(high[1], hit[2]);
    };
    return .{ .{ low[0] - margin, low[1] - margin }, .{ high[0] + margin, high[1] + margin } };
}

fn touching(a: Body, b: Body) bool {
    const apart = math.sub(a.position, b.position);
    const reach = a.radius + b.radius;
    return apart[0] * apart[0] + apart[2] * apart[2] < reach * reach;
}

/// A shot's capsule lies along its flight.
fn shotTransform(position: math.Vec3, heading: f32) math.Mat4 {
    return math.mul(math.translation(position), math.mul(math.rotationY(heading), math.rotationX(-std.math.pi / 2.0)));
}

fn planetTransform(time: f32) math.Mat4 {
    const tilt = math.mul(math.rotationZ(0.35), math.rotationX(0.25));
    return math.mul(math.translation(.{ -135, -250, 85 }), math.mul(tilt, math.mul(math.rotationY(time * 0.01), math.uniformScaling(58))));
}

fn sparkDesc(position: math.Vec3) gfx.EmitterDesc {
    return .{
        .position = position,
        .radius = 0.6,
        .capacity = 1024,
        .rate = 0,
        .lifetime = .{ 0.25, 0.9 },
        .direction = .{ 0, 1, 0 },
        .spread = std.math.pi,
        .drag = 2.2,
        .size = .{ 0.22, 0.02 },
        .color_start = .{ 14, 6, 1.6, 1 },
        .color_end = .{ 3, 0.4, 0.05, 0 },
        .blend = .additive,
        .lit = false,
        .stretch = 0.04,
    };
}

fn dustDesc(position: math.Vec3) gfx.EmitterDesc {
    return .{
        .position = position,
        .radius = 1.0,
        .capacity = 1024,
        .rate = 0,
        .lifetime = .{ 0.8, 2.2 },
        .direction = .{ 0, 1, 0 },
        .spread = std.math.pi,
        .drag = 1.4,
        .color_start = .{ 0.32, 0.29, 0.26, 0.35 },
        .color_mid = .{ 0.24, 0.22, 0.2, 0.3 },
        .color_end = .{ 0.18, 0.17, 0.16, 0 },
        .softness = 0,
    };
}

fn flameDesc(position: math.Vec3, direction: math.Vec3) gfx.EmitterDesc {
    return .{
        .position = position,
        .radius = 0.12,
        .capacity = 512,
        .rate = 0,
        .lifetime = .{ 0.08, 0.2 },
        .direction = direction,
        .spread = 0.18,
        .speed = .{ 9, 14 },
        .drag = 0,
        .size = .{ 0.85, 0.1 },
        .color_start = .{ 3, 6, 14, 1 },
        .color_mid = .{ 10, 4, 1.2, 0.8 },
        .color_end = .{ 2, 0.3, 0.05, 0 },
        .blend = .additive,
        .lit = false,
        .softness = 0,
    };
}

/// Hands keybinds the keys that went down or up since the last frame.
fn feedKeys(stage: *const Stage, tracker: *Keymap.Tracker, held: *[watched_keys.len]bool, now: u64) !void {
    for (watched_keys, held) |watched, *was_down| {
        const down = stage.keyDown(watched.glfw);
        if (down == was_down.*) continue;
        was_down.* = down;
        if (down) try tracker.press(.key(watched.key), now) else try tracker.release(.key(watched.key), now);
    }
}

pub fn main(init: std.process.Init) !void {
    var demo = false;
    {
        var arguments = try init.minimal.args.iterateAllocator(init.gpa);
        defer arguments.deinit();
        while (arguments.next()) |argument| {
            if (std.mem.eql(u8, argument, "--demo")) demo = true;
        }
    }
    var stage = try Stage.create(init, "Asteroids", .{ .cache = .{ .assets = "zig-out/asset-cache" } });
    const renderer = stage.renderer;
    const scene = try renderer.scenes.create();
    const stars = try renderer.environments.load(.{ .path = "examples/assets/asteroids_game/starfield_4k.hdr", .max_radiance = 8 });
    renderer.scenes.setEnvironment(scene, .{ .environment = stars, .intensity = 0.7 });
    renderer.scenes.setSun(scene, .{ .direction = math.normalize(.{ -0.88, -0.3, -0.36 }), .color = .{ 1.0, 0.94, 0.85 }, .intensity = 4.5 });

    var keymap = Keymap.init(init.gpa, .{});
    defer keymap.deinit();
    try keymap.load(bindings, .replace_all, null);
    var tracker = Keymap.Tracker.init(init.gpa, &keymap, 0);
    defer tracker.deinit();
    var held: [watched_keys.len]bool = @splat(false);

    var prng = std.Random.DefaultPrng.init(0x5eed_a57e);
    var game = Game{
        .gpa = init.gpa,
        .renderer = renderer,
        .scene = scene,
        .world = slime.World.init(init.gpa, init.io),
        .rng = prng.random(),
        .demo = demo,
        .sounds = Sounds.init(init.gpa, init.io),
        .rock_models = undefined,
        .shot_model = try renderer.models.createPrimitive(.{
            .shape = .{ .capsule = .{ .radius = 0.11, .height = 1.3, .segments = 12, .rings = 4 } },
            .material = .{ .base_color = .{ 0, 0, 0, 1 }, .emissive = .{ 4, 14, 26 } },
        }),
        .ship = try renderer.entities.create(scene, .{ .model = try renderer.models.load("examples/assets/asteroids_game/ship.glb") }),
        .planet = try renderer.entities.create(scene, .{ .model = try renderer.models.load("examples/assets/asteroids_game/planet.glb"), .transform = planetTransform(0) }),
        .flame = try renderer.emitters.create(scene, flameDesc(.{ 0, 0, 0 }, .{ 0, 0, 1 })),
        .blasts = undefined,
    };
    defer game.world.deinit();
    defer if (game.sounds) |*sounds| sounds.engine.deinit();
    for (&game.rock_models, rock_files) |*model, path| model.* = try renderer.models.load(path);
    for (&game.blasts) |*blast| blast.* = .{
        .sparks = try renderer.emitters.create(scene, sparkDesc(.{ 0, 0, 0 })),
        .dust = try renderer.emitters.create(scene, dustDesc(.{ 0, 0, 0 })),
    };
    try game.startWave();
    try game.world.applyCommands();
    try renderer.waitUntilLoaded();

    var list = gfx.DrawList.init(init.gpa);
    defer list.deinit();
    const font = renderer.fonts.default();
    var text: [64]u8 = undefined;

    while (stage.begin()) |tick| {
        const dt = @min(tick.dt, 1.0 / 20.0);
        const now: u64 = @intFromFloat(@as(f64, tick.time) * std.time.ns_per_s);
        try feedKeys(&stage, &tracker, &held, now);
        try tracker.update(now);
        game.clock += dt;
        game.cooldown -= dt;
        game.invulnerable = @max(game.invulnerable - dt, 0);

        const game_over = !game.alive and game.lives == 0;
        if (game.alive) {
            const pilot: Pilot = if (demo) game.autopilot() else .{ .turn = tracker.value(.turn), .thrust = tracker.down(.thrust), .fire = tracker.down(.fire) };
            game.steerShip(pilot.turn, pilot.thrust, dt);
            if (pilot.fire and game.cooldown <= 0) try game.fire();
        } else if (game_over) {
            if (tracker.pressed(.start)) try game.restart();
        } else {
            game.respawn_in -= dt;
            if (game.respawn_in <= 0) _ = game.tryRespawn();
        }
        tracker.endFrame();

        game.moveBodies(dt);
        try game.ageShots(dt);
        try game.collide();
        try game.world.applyCommands();
        if (game.rocksLeft() == 0) {
            try game.startWave();
            try game.world.applyCommands();
        }
        game.spinRocks(dt);
        try game.updateEffects(dt);
        if (game.sounds) |*sounds| sounds.engine.update();

        list.clear();
        const size = tick.size;
        const width: f32 = @floatFromInt(size[0]);
        const height: f32 = @floatFromInt(size[1]);
        try list.text(font, try std.fmt.bufPrint(&text, "{d}", .{game.score}), .{ 28, 22 }, .{ .size = 34, .color = gfx.Color.hex(0xf3f1ea) });
        try list.text(font, try std.fmt.bufPrint(&text, "wave {d}", .{game.wave}), .{ 30, 64 }, .{ .size = 16, .color = gfx.Color.hex(0x9aa7d0) });
        for (0..game.lives) |life| {
            const x = width - 44 - 30 * @as(f32, @floatFromInt(life));
            try list.fillConvex(&.{ .{ x, 24 }, .{ x + 10, 50 }, .{ x, 44 }, .{ x - 10, 50 } }, gfx.Color.hex(0xff8a3d));
        }
        if (game_over) {
            const title = TextOptions{ .size = 44, .color = gfx.Color.hex(0xf3f1ea) };
            const hint = TextOptions{ .size = 18, .color = gfx.Color.hex(0x9aa7d0) };
            const title_size = try list.measureText(font, "GAME OVER", title);
            const hint_size = try list.measureText(font, "Enter to play again", hint);
            try list.text(font, "GAME OVER", .{ (width - title_size[0]) / 2, height / 2 - 48 }, title);
            try list.text(font, "Enter to play again", .{ (width - hint_size[0]) / 2, height / 2 + 12 }, hint);
        }
        if (demo) try list.text(font, "demo", .{ 30, height - 40 }, .{ .size = 15, .color = gfx.Color.hex(0x7c8499) });

        const shake: math.Vec3 = .{ (game.rng.float(f32) - 0.5) * game.shake, 0, (game.rng.float(f32) - 0.5) * game.shake };
        var camera = gfx.Camera.lookAt(math.add(eye, shake), math.add(look_at, shake));
        camera.fov_y = fov_y;
        try stage.end(try renderer.render(.{
            .views = &.{.{
                .scene = scene,
                .camera = camera,
                .draw_lists = &.{.{ .list = &list }},
                .target = stage.target(),
                .settings = .{
                    .shadows = .{ .distance = 90 },
                    .ambient_occlusion = null,
                    .global_illumination = null,
                    .post = .{ .bloom = 0.06, .automatic_exposure = false, .exposure_compensation = 0, .vignette = 0.25 },
                },
            }},
            .delta_time = dt,
        }));
    }
    try stage.finish();
}
