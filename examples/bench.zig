//! A benchmark: Emerald Square without a window, through the frames
//! that gather its lighting, at a fixed viewpoint, and flying between
//! viewpoints. Prints the GPU time of each pass in each phase, and with
//! `--out` writes them to a file that a later run can `--compare` against.
//!
//! The scene is not kept with these sources; see examples/assets/README.md.
//!
//!   --dusk           the dusk scene, path traced, instead of day
//!   --size WxH       resolution to render at (default 1280x720)
//!   --view N         viewpoint of the steady phase (default 0)
//!   --frames N       frames in each timed phase (default 300)
//!   --out file       write the results, tab separated
//!   --compare file   print each pass against an earlier `--out`
//!
//! Phases:
//!   warmup   the first frames after loading, while probes are first traced
//!            and textures still stream in
//!   steady   one viewpoint, once streaming has finished and lighting settled
//!   moving   the camera flies through every viewpoint and back
const std = @import("std");
const gfx = @import("limn");
const math = gfx.math;

const root = "examples/assets/emerald_square/";
const unzipped = root ++ "EmeraldSquare_v4_1/";
const scene_paths = [2][]const u8{ unzipped ++ "EmeraldSquare_Day.fbx", unzipped ++ "EmeraldSquare_Dusk.fbx" };
const night_sky = unzipped ++ "night_sky.hdr";
const sun_direction = math.Vec3{ 0.498, -0.747, -0.441 };

/// The viewpoints of the emerald_square example.
const views = [_][2]math.Vec3{
    .{ .{ -38.4, 1.5, 75.7 }, .{ 0.12, 0, -0.99 } },
    .{ .{ -28.5, 2, 36.3 }, .{ -0.97, -0.13, -0.19 } },
    .{ .{ -2.1, 1.5, -29.3 }, .{ -0.61, 0.03, 0.79 } },
    .{ .{ 21.8, 1.5, 1.5 }, .{ -0.56, -0.09, 0.83 } },
    .{ .{ -70, 40, 70 }, .{ 0.64, -0.42, -0.64 } },
};

/// Frames of the warm-up phase: as many as GI traces every probe for.
const warmup_frames = 200;
/// Most frames rendered untimed after warm-up, waiting for streaming.
const settle_limit = 3000;
/// Frames rendered untimed after streaming ends, before `steady`.
const settle_frames = 120;

const Phase = enum { warmup, steady, moving };

/// Pass times summed over a phase, by nesting depth and name.
const Passes = struct {
    names: [max][]const u8 = undefined,
    depths: [max]u8 = undefined,
    totals: [max]f64 = undefined,
    count: usize = 0,

    const max = 160;

    fn add(self: *Passes, name: []const u8, depth: u8, milliseconds: f64) void {
        for (self.names[0..self.count], self.depths[0..self.count], self.totals[0..self.count]) |known, known_depth, *total| {
            if (known_depth == depth and std.mem.eql(u8, known, name)) {
                total.* += milliseconds;
                return;
            }
        }
        if (self.count == max) return;
        self.names[self.count] = name;
        self.depths[self.count] = depth;
        self.totals[self.count] = milliseconds;
        self.count += 1;
    }
};

const Results = struct {
    passes: Passes = .{},
    /// GPU time of each frame, depth-0 passes summed.
    frames: std.ArrayList(f64) = .empty,
    cpu: f64 = 0,

    fn note(self: *Results, gpa: std.mem.Allocator, renderer: *gfx.Renderer) !void {
        var frame: f64 = 0;
        for (renderer.device.passTimings()) |timing| {
            self.passes.add(timing.name, timing.depth, timing.milliseconds);
            if (timing.depth == 0) frame += timing.milliseconds;
        }
        try self.frames.append(gpa, frame);
        self.cpu += renderer.stats().cpu_ms;
    }

    fn mean(self: *const Results, total: f64) f64 {
        return total / @as(f64, @floatFromInt(@max(self.frames.items.len, 1)));
    }

    /// The frame time below which `fraction` of frames fall.
    fn percentile(self: *Results, fraction: f64) f64 {
        if (self.frames.items.len == 0) return 0;
        std.mem.sortUnstable(f64, self.frames.items, {}, std.sort.asc(f64));
        const at: usize = @intFromFloat(@as(f64, @floatFromInt(self.frames.items.len - 1)) * fraction);
        return self.frames.items[at];
    }

    fn frameMean(self: *const Results) f64 {
        var total: f64 = 0;
        for (self.frames.items) |value| total += value;
        return self.mean(total);
    }
};

/// One row of a results file: a phase, a pass (or a whole-frame figure,
/// at depth 255) and its mean milliseconds.
const Row = struct { phase: []const u8, depth: u8, name: []const u8, milliseconds: f64 };

const frame_rows = [_][]const u8{ "frame gpu mean", "frame gpu p95", "frame gpu max", "frame cpu mean" };
const frame_depth = 255;

fn rows(gpa: std.mem.Allocator, results: *std.EnumArray(Phase, Results)) ![]Row {
    var list: std.ArrayList(Row) = .empty;
    errdefer list.deinit(gpa);
    for (std.enums.values(Phase)) |phase| {
        const result = results.getPtr(phase);
        const figures = [frame_rows.len]f64{ result.frameMean(), result.percentile(0.95), result.percentile(1), result.mean(result.cpu) };
        for (frame_rows, figures) |name, value| try list.append(gpa, .{ .phase = @tagName(phase), .depth = frame_depth, .name = name, .milliseconds = value });
        const passes = &result.passes;
        for (passes.names[0..passes.count], passes.depths[0..passes.count], passes.totals[0..passes.count]) |name, depth, total| {
            try list.append(gpa, .{ .phase = @tagName(phase), .depth = depth, .name = name, .milliseconds = result.mean(total) });
        }
    }
    return list.toOwnedSlice(gpa);
}

fn writeRows(io: std.Io, path: []const u8, heading: []const u8, all: []const Row) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;
    try out.print("# {s}\n", .{heading});
    for (all) |row| try out.print("{s}\t{d}\t{s}\t{d:.4}\n", .{ row.phase, row.depth, row.name, row.milliseconds });
    try out.flush();
}

/// Rows of an earlier `--out`; names point into `text`.
fn parseRows(gpa: std.mem.Allocator, text: []const u8) ![]Row {
    var list: std.ArrayList(Row) = .empty;
    errdefer list.deinit(gpa);
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "#")) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const phase = fields.next() orelse continue;
        const depth = std.fmt.parseInt(u8, fields.next() orelse continue, 10) catch continue;
        const name = fields.next() orelse continue;
        const milliseconds = std.fmt.parseFloat(f64, fields.next() orelse continue) catch continue;
        try list.append(gpa, .{ .phase = phase, .depth = depth, .name = name, .milliseconds = milliseconds });
    }
    return list.toOwnedSlice(gpa);
}

fn indent(depth: u8) []const u8 {
    return "          "[0..@min(@as(usize, if (depth == frame_depth) 0 else depth) * 2 + 2, 10)];
}

fn printRows(heading: []const u8, all: []const Row, earlier: ?[]const Row) void {
    std.debug.print("{s}\n", .{heading});
    var phase: []const u8 = "";
    for (all) |row| {
        if (!std.mem.eql(u8, row.phase, phase)) {
            phase = row.phase;
            std.debug.print("\n{s}\n", .{phase});
        }
        const before = if (earlier) |list| for (list) |old| {
            if (old.depth == row.depth and std.mem.eql(u8, old.phase, row.phase) and std.mem.eql(u8, old.name, row.name)) break old.milliseconds;
        } else null else null;
        if (before) |old| {
            const change = if (old > 0) (row.milliseconds - old) / old * 100 else 0;
            std.debug.print("{d:9.3} ms {d:9.3} ms {d:7.1}%  {s}{s}\n", .{ old, row.milliseconds, change, indent(row.depth), row.name });
        } else {
            std.debug.print("{s}{d:9.3} ms  {s}{s}\n", .{ if (earlier != null) "             " else "", row.milliseconds, indent(row.depth), row.name });
        }
    }
    if (earlier) |list| for (list) |old| {
        for (all) |row| {
            if (old.depth == row.depth and std.mem.eql(u8, old.phase, row.phase) and std.mem.eql(u8, old.name, row.name)) break;
        } else std.debug.print("{d:9.3} ms      gone          {s} {s}\n", .{ old.milliseconds, old.phase, old.name });
    };
}

/// Position and direction `t` of the way (0 to 1) through every viewpoint
/// and back to the first.
fn flight(t: f32) [2]math.Vec3 {
    const legs: f32 = @floatFromInt(views.len);
    const along = @min(t * legs, legs - 0.0001);
    const leg: usize = @intFromFloat(along);
    const s = along - @floor(along);
    const from = views[leg];
    const to = views[(leg + 1) % views.len];
    const eye = math.add(math.scale(from[0], 1 - s), math.scale(to[0], s));
    const direction = math.normalize(math.add(math.scale(from[1], 1 - s), math.scale(to[1], s)));
    return .{ eye, direction };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var dusk = false;
    var size = [2]u32{ 1280, 720 };
    var view: usize = 0;
    var timed_frames: u32 = 300;
    var out_path: ?[]const u8 = null;
    var compare_path: ?[]const u8 = null;
    var arguments = try init.minimal.args.iterateAllocator(gpa);
    defer arguments.deinit();
    _ = arguments.skip();
    while (arguments.next()) |argument| {
        if (std.mem.eql(u8, argument, "--dusk")) {
            dusk = true;
        } else if (std.mem.eql(u8, argument, "--size")) {
            var parts = std.mem.splitScalar(u8, arguments.next() orelse return error.MissingArgument, 'x');
            size[0] = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidArgument, 10);
            size[1] = try std.fmt.parseInt(u32, parts.next() orelse return error.InvalidArgument, 10);
        } else if (std.mem.eql(u8, argument, "--view")) {
            view = try std.fmt.parseInt(usize, arguments.next() orelse return error.MissingArgument, 10) % views.len;
        } else if (std.mem.eql(u8, argument, "--frames")) {
            timed_frames = try std.fmt.parseInt(u32, arguments.next() orelse return error.MissingArgument, 10);
        } else if (std.mem.eql(u8, argument, "--out")) {
            out_path = arguments.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, argument, "--compare")) {
            compare_path = arguments.next() orelse return error.MissingArgument;
        } else return error.InvalidArgument;
    }
    for (scene_paths) |path| std.Io.Dir.cwd().access(io, path, .{}) catch {
        std.debug.print("Emerald Square is missing; see `zig build emerald_square` for how to fetch it.\n", .{});
        return;
    };

    const renderer = try gfx.Renderer.init(gpa, io, .{
        .application_name = "Limn bench",
        .ray_tracing = .{ .software_path_tracing = true },
        .cache = .{ .assets = "zig-out/asset-cache", .pipelines = "zig-out/pipeline.cache" },
        .textures = .{ .streaming = .{ .budget_bytes = 2 << 30 } },
    });
    defer renderer.deinit();
    const target = try renderer.views.createTarget(size[0], size[1]);
    defer renderer.views.destroyTarget(target);

    const scene = try renderer.scenes.create();
    const sky = gfx.SkyDesc{ .sun_direction = sun_direction };
    const sun = gfx.skySun(sky);
    if (dusk) {
        renderer.scenes.setEnvironment(scene, .{ .environment = try renderer.environments.load(.{ .path = night_sky, .max_radiance = 16 }), .intensity = 1 });
        renderer.scenes.setSun(scene, .{ .direction = sun.direction, .color = sun.color, .intensity = 0 });
    } else {
        renderer.scenes.setEnvironment(scene, .{ .environment = try renderer.environments.createSky(sky), .intensity = 1 });
        renderer.scenes.setSun(scene, .{ .direction = sun.direction, .color = sun.color, .intensity = 0 });
        try renderer.scenes.setLights(scene, &.{.{ .kind = .directional, .position = .{ 0, 0, 0 }, .direction = sun.direction, .color = sun.color, .intensity = sun.intensity, .cast_shadows = true, .source_radius = 0.005 }});
    }

    const load_start = std.Io.Clock.Timestamp.now(io, .awake);
    const model = try renderer.models.loadWith(scene_paths[@intFromBool(dusk)], .{ .directx_normal_maps = true, .packed_specular = true, .emissive_strength = if (dusk) 5 else 1 });
    try renderer.waitUntilLoaded();
    const load_seconds = @as(f64, @floatFromInt(load_start.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.nanoseconds)) / 1e9;
    _ = try renderer.entities.create(scene, .{ .model = model });

    var results: std.EnumArray(Phase, Results) = .initFill(.{});
    defer for (&results.values) |*result| result.frames.deinit(gpa);

    var frame: u32 = 0;
    var settle_left: u32 = settle_frames;
    var phase_frame: u32 = 0;
    var phase: ?Phase = .warmup;
    var settling = false;
    while (phase != null or settling) {
        const at = if (phase == .moving) flight(@as(f32, @floatFromInt(phase_frame)) / @as(f32, @floatFromInt(@max(timed_frames, 1)))) else views[view];
        var camera = gfx.Camera.lookAt(at[0], math.add(at[0], at[1]));
        camera.fov_y = 0.75;
        _ = try renderer.render(.{
            .views = &.{.{
                .scene = scene,
                .camera = camera,
                .target = .{ .texture = target },
                .settings = .{
                    .shadows = .{ .distance = 120 },
                    .resolution = .{ .scale = 0.67, .upscaler = .fsr3 },
                    .global_illumination = .{ .probes = .{ .rays = 64 } },
                    .path_tracing = if (dusk) .{ .bounces = 2 } else null,
                    .post = .{ .automatic_exposure = dusk, .exposure_compensation = if (dusk) 0 else 1.3 },
                },
            }},
            .delta_time = 1.0 / 60.0,
        });
        frame += 1;
        if (settling) {
            const stats = renderer.stats();
            const streaming = stats.streamed_textures_pending != 0 or stats.models_loading != 0;
            if (!streaming) settle_left -|= 1;
            if (settle_left == 0 or frame > warmup_frames + settle_limit) {
                if (streaming) std.log.warn("textures still streaming after {d} frames; steady numbers include it", .{settle_limit});
                settling = false;
                phase = .steady;
                phase_frame = 0;
            }
            continue;
        }
        try results.getPtr(phase.?).note(gpa, renderer);
        phase_frame += 1;
        const length = if (phase == .warmup) warmup_frames else timed_frames;
        if (phase_frame < length) continue;
        phase_frame = 0;
        phase = switch (phase.?) {
            .warmup => null,
            .steady => .moving,
            .moving => null,
        };
        if (phase == null and results.getPtr(.steady).frames.items.len == 0) settling = true;
    }
    try renderer.device.waitIdle();

    const all = try rows(gpa, &results);
    defer gpa.free(all);
    var heading_buffer: [256]u8 = undefined;
    const heading = try std.fmt.bufPrint(&heading_buffer, "limn bench · emerald_square {s} · {d}x{d} · {s} · load {d:.2} s · {d} frames a phase", .{ if (dusk) "dusk" else "day", size[0], size[1], renderer.device.name(), load_seconds, timed_frames });

    var earlier_text: ?[]u8 = null;
    defer if (earlier_text) |text| gpa.free(text);
    var earlier: ?[]Row = null;
    defer if (earlier) |list| gpa.free(list);
    if (compare_path) |path| {
        earlier_text = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 << 20));
        earlier = try parseRows(gpa, earlier_text.?);
        std.debug.print("compared against {s}: {s}\n", .{ path, std.mem.sliceTo(earlier_text.?, '\n') });
    }
    printRows(heading, all, earlier);
    if (out_path) |path| {
        try writeRows(io, path, heading, all);
        std.debug.print("\nwrote {s}\n", .{path});
    }
}
