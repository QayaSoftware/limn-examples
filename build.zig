const std = @import("std");
const limn_build = @import("qaya").limn;

const Shader = limn_build.Shader;

/// What `zig build cross` builds for; Android gets APKs.
const cross_targets = [_][]const u8{ "x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-windows-gnu", "x86_64-macos", "aarch64-macos", "aarch64-linux-android" };

/// Where NixOS keeps the GPU driver's libraries, which are on no default path;
/// DLSS needs them on the library path of what it runs in.
const nixos_drivers = "/run/opengl-driver/lib";

/// One picture `verify` renders: `frames` of `example` with `arguments`,
/// saved as verify_<name>.png.
const Shot = struct { example: []const u8, name: []const u8, frames: []const u8, arguments: []const []const u8 = &.{} };

const Example = struct {
    name: []const u8,
    root: []const u8,
    description: []const u8,
    windowed: bool,
    shaders: []const Shader = &.{},
};

const examples: []const Example = &.{
    .{
        .name = "triangle",
        .root = "examples/triangle/main.zig",
        .description = "Draw a triangle with the bare RHI",
        .windowed = true,
        .shaders = &.{
            .{ .src = "examples/triangle/triangle.slang", .name = "triangle.vert.spv", .entry = "vertexMain", .stage = "vertex" },
            .{ .src = "examples/triangle/triangle.slang", .name = "triangle.frag.spv", .entry = "fragmentMain", .stage = "fragment" },
        },
    },
    .{
        .name = "canvas",
        .root = "examples/canvas.zig",
        .description = "A 2D-only application: shapes, sprites and text",
        .windowed = true,
        .shaders = &.{
            .{ .src = "examples/shaders/scanlines.slang", .name = "scanlines.frag.spv", .entry = "fragmentMain", .stage = "fragment" },
        },
    },
    .{
        .name = "meadow",
        .root = "examples/meadow.zig",
        .description = "An open meadow to walk through: grass, trees, a pond, clouds, sun and sky",
        .windowed = true,
    },
    .{
        .name = "materials",
        .root = "examples/materials.zig",
        .description = "A grid of metals and plastics, glass, lacquer, velvet and wax, lit by a studio photograph",
        .windowed = true,
    },
    .{
        .name = "lights",
        .root = "examples/lights.zig",
        .description = "A hall at night: many drifting lamps, a shadowed spot light and a glowing panel",
        .windowed = true,
    },
    .{
        .name = "isometric",
        .root = "examples/isometric.zig",
        .description = "A terraced diorama through an orthographic camera, with markers drawn into the scene",
        .windowed = true,
    },
    .{
        .name = "decals",
        .root = "examples/decals.zig",
        .description = "Markings, stains and glowing signs projected onto a floor, a wall and a ball",
        .windowed = true,
    },
    .{
        .name = "text",
        .root = "examples/text.zig",
        .description = "Text at any size, ligatures, right-to-left and complex scripts, rich text, text in 3D",
        .windowed = true,
    },
    .{
        .name = "views",
        .root = "examples/views.zig",
        .description = "A split screen, a camera rendered to a texture and a 2D layer in one frame",
        .windowed = true,
    },
    .{
        .name = "post",
        .root = "examples/post.zig",
        .description = "Bloom, depth of field, motion blur, grading and the other effects, one key each",
        .windowed = true,
    },
    .{
        .name = "shader",
        .root = "examples/shader.zig",
        .description = "A material written by the application: molten rock that cools per object",
        .windowed = true,
        .shaders = &.{
            .{ .src = "examples/shaders/lava.slang", .name = "lava.frag.spv", .entry = "fragmentMain", .stage = "fragment" },
            .{ .src = "examples/shaders/lava.slang", .name = "lava_plain.frag.spv", .defines = &.{"PLAIN"}, .entry = "fragmentMain", .stage = "fragment" },
        },
    },
    .{
        .name = "rtx",
        .root = "examples/rtx.zig",
        .description = "Ray tracing a feature at a time in Sponza: bounce light, reflections, soft shadows, path tracing",
        .windowed = true,
    },
    .{
        .name = "pathtrace",
        .root = "examples/pathtrace.zig",
        .description = "Path tracing by the GPU's ray tracing or by a shader, beside the usual picture",
        .windowed = true,
    },
    .{
        .name = "particles",
        .root = "examples/particles.zig",
        .description = "GPU particle emitters: fire, smoke, a fountain, snow and a moving spark",
        .windowed = true,
    },
    .{
        .name = "animation",
        .root = "examples/animation.zig",
        .description = "Clip cross-fades, masked layers and additive layers on one character",
        .windowed = true,
    },
    .{
        .name = "instancing",
        .root = "examples/instancing.zig",
        .description = "A forest placed as one instance group, with picking",
        .windowed = true,
    },
    .{
        .name = "lightweight",
        .root = "examples/lightweight.zig",
        .description = "Simple 3D at its smallest cost, with a HUD of what each frame records",
        .windowed = true,
    },
    .{
        .name = "passes",
        .root = "examples/passes.zig",
        .description = "The application's own compute, geometry, tone curve and ink lines inside a lit scene",
        .windowed = true,
        .shaders = &.{
            .{ .src = "examples/shaders/passes.slang", .name = "passes_move.comp.spv", .entry = "moveMain", .stage = "compute" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_fullscreen.vert.spv", .entry = "fullscreenMain", .stage = "vertex" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_blob.frag.spv", .entry = "orbsMain", .stage = "fragment" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_copy.frag.spv", .entry = "copyMain", .stage = "fragment" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_curve.frag.spv", .entry = "curveMain", .stage = "fragment" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_outline.frag.spv", .entry = "outlineMain", .stage = "fragment" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_shadow.frag.spv", .entry = "shadowMain", .stage = "fragment" },
            .{ .src = "examples/shaders/passes.slang", .name = "passes_light_shadow.frag.spv", .entry = "lightShadowMain", .stage = "fragment" },
        },
    },
    .{
        .name = "reflections",
        .root = "examples/reflections.zig",
        .description = "Polished floor, spheres from mirror to rough, metals and lacquer, with reflections",
        .windowed = true,
    },
    .{
        .name = "clouds",
        .root = "examples/clouds.zig",
        .description = "Volumetric clouds over a landscape, with time of day",
        .windowed = true,
    },
    .{
        .name = "fluid",
        .root = "examples/fluid.zig",
        .description = "Simulated smoke and fire, in the scene and as a 2D picture",
        .windowed = true,
    },
    .{
        .name = "water",
        .root = "examples/water.zig",
        .description = "A pool of simulated water with ripples, rain, reflection and refraction",
        .windowed = true,
    },
    .{
        .name = "liquid",
        .root = "examples/liquid.zig",
        .description = "A volume of liquid that pours, sloshes and splashes in a tank",
        .windowed = true,
    },
    .{
        .name = "world",
        .root = "examples/world.zig",
        .description = "Walk a skinned character through Sponza",
        .windowed = true,
    },
    .{
        .name = "asteroids",
        .root = "examples/asteroids.zig",
        .description = "A belt of millions of rocks, culled and drawn by the GPU",
        .windowed = true,
    },
    .{
        .name = "shadows",
        .root = "examples/shadows.zig",
        .description = "Virtual shadow maps beside the sun's cascades, down a long avenue of fine shadows",
        .windowed = true,
    },
    .{
        .name = "bistro",
        .root = "examples/bistro.zig",
        .description = "Amazon Lumberyard Bistro: a full street scene by day and by night",
        .windowed = true,
    },
    .{
        .name = "upscaling",
        .root = "examples/upscaling.zig",
        .description = "Drawing fewer pixels: bicubic, temporal and FidelityFX upscaling, and coarse shading",
        .windowed = true,
    },
    .{
        .name = "lightmap",
        .root = "examples/lightmap.zig",
        .description = "A room whose bounce light is baked into lightmaps by rays while you watch",
        .windowed = true,
    },
    .{
        .name = "stereo",
        .root = "examples/stereo.zig",
        .description = "A stereo pair: the scene once for each eye, side by side",
        .windowed = true,
    },
    .{
        .name = "hair",
        .root = "examples/hair.zig",
        .description = "Ten thousand strands of hair that hang, swing and blow about",
        .windowed = true,
    },
    .{
        .name = "voxels",
        .root = "examples/voxels.zig",
        .description = "Fly round a small planet of fifty million voxels as its chunks stream in",
        .windowed = true,
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const thread_sanitizer = b.option(bool, "tsan", "Build with the thread sanitizer, with -Dtarget=x86_64-linux-gnu") orelse false;
    const android = target.result.abi.isAndroid();
    const qaya = b.dependency("qaya", .{
        .target = target,
        .optimize = optimize,
        .tsan = thread_sanitizer,
        .system_tools = b.option(bool, "system_tools", "Run slangc and glslangValidator from PATH instead of fetched builds (default: false)"),
        .fidelityfx = b.option(bool, "fidelityfx", "Build AMD's FidelityFX SDK in, for FSR 2 and FSR 3 upscaling (default: true, false with -Dtsan)"),
        .dlss = b.option(bool, "dlss", "Build NVIDIA DLSS upscaling and ray reconstruction in (default: true where the SDK is found)"),
        .dlss_sdk = sdkPath(b, "dlss_sdk", "Where NVIDIA's DLSS SDK is (default: dlss_sdk)"),
        .nrd = b.option(bool, "nrd", "Build NVIDIA's NRD denoiser in, for path tracing (default: true where the SDK is found)"),
        .nrd_sdk = sdkPath(b, "nrd_sdk", "Where NVIDIA's NRD SDK is, built (default: nrd_sdk)"),
        .slime = false,
    });
    const renderer = qaya.builder.modules.get("limn") orelse return;
    const apk_packer = qaya.builder.named_lazy_paths.get("apk") orelse return;

    const glfw_module = if (android) b.createModule(.{ .root_source_file = b.path("examples/android/glfw.zig"), .target = target, .optimize = optimize }) else glfw: {
        const glfw_source = b.lazyDependency("glfw", .{}) orelse return;
        const glfw = b.addTranslateC(.{
            .root_source_file = b.path("examples/glfw_native.h"),
            .target = target,
            .optimize = optimize,
        });
        glfw.addIncludePath(glfw_source.path("include"));
        const module = glfw.createModule();
        if (!addGlfw(b, module, target, glfw_source)) return;
        break :glfw module;
    };
    const window_module = b.createModule(.{
        .root_source_file = b.path("examples/window.zig"),
        .target = target,
        .optimize = optimize,
    });
    window_module.addImport("limn", renderer);
    window_module.addImport("glfw", glfw_module);
    var moltenvk_dir: ?[]const u8 = null;
    if (target.result.os.tag == .macos) {
        const moltenvk = b.lazyDependency("moltenvk", .{}) orelse return;
        const dylib = moltenvk.path("MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib");
        b.getInstallStep().dependOn(&b.addInstallBinFile(dylib, "libMoltenVK.dylib").step);
        moltenvk_dir = moltenvk.path("MoltenVK/dynamic/dylib/macOS").getPath(b);
    }
    const nixos = if (b.build_root.handle.access(b.graph.io, nixos_drivers, .{})) |_| true else |_| false;

    const check_step = b.step("check", "Compile the examples without running them");
    var example_exes: std.StringHashMapUnmanaged(*std.Build.Step.Compile) = .empty;
    for (examples) |example| {
        const module = b.createModule(.{
            .root_source_file = b.path(example.root),
            .target = target,
            .optimize = optimize,
            .sanitize_thread = thread_sanitizer,
        });
        module.addImport("limn", renderer);
        if (example.windowed) {
            module.addImport("glfw", glfw_module);
            module.addImport("window", window_module);
        }
        limn_build.addShaders(b, qaya, module, example.shaders);
        if (android) {
            if (example.windowed) if (addAndroidExample(b, example, module, glfw_module, target, optimize, apk_packer)) |packed_apk| b.getInstallStep().dependOn(packed_apk);
            continue;
        }
        const exe = b.addExecutable(.{ .name = example.name, .root_module = module, .use_llvm = true });
        example_exes.put(b.allocator, example.name, exe) catch @panic("OOM");
        b.installArtifact(exe);
        check_step.dependOn(&exe.step);
        const run = b.addRunArtifact(exe);
        run.setCwd(b.path("."));
        if (nixos) run.setEnvironmentVariable("LD_LIBRARY_PATH", b.fmt("{s}:{s}", .{ b.graph.environ_map.get("LD_LIBRARY_PATH") orelse "", nixos_drivers }));
        if (moltenvk_dir) |dir| run.setEnvironmentVariable("DYLD_LIBRARY_PATH", dir);
        if (b.args) |args| run.addArgs(args);
        b.step(example.name, example.description).dependOn(&run.step);
        if (std.mem.eql(u8, example.name, "meadow")) b.step("run", example.description).dependOn(&run.step);
    }

    const format_check = b.addSystemCommand(&.{
        b.graph.zig_exe, "fmt", "--check", "build.zig", "examples",
    });
    format_check.setCwd(b.path("."));
    const verify_step = b.step("verify", "Check formatting and render the examples with validation enabled");
    verify_step.dependOn(&format_check.step);
    const cross_step = b.step("cross", "Build the examples for every target, into zig-out/cross/<target>, without running them");
    var previous_cross: ?*std.Build.Step = null;
    for (cross_targets) |cross_target| {
        const cross = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "install", b.fmt("-Dtarget={s}", .{cross_target}), "--prefix", b.pathFromRoot(b.fmt("zig-out/cross/{s}", .{cross_target})) });
        cross.setCwd(b.path("."));
        cross.has_side_effects = true;
        if (previous_cross) |previous| cross.step.dependOn(previous);
        previous_cross = &cross.step;
        cross_step.dependOn(&cross.step);
    }
    if (android) return limn_build.applyAndroidLibc(b);

    for ([_]Shot{
        .{ .example = "particles", .name = "particles", .frames = "90" },
        .{ .example = "animation", .name = "animation", .frames = "60" },
        .{ .example = "instancing", .name = "instancing", .frames = "60" },
        .{ .example = "reflections", .name = "reflections", .frames = "60" },
        .{ .example = "clouds", .name = "clouds", .frames = "60" },
        .{ .example = "fluid", .name = "fluid", .frames = "60" },
        .{ .example = "water", .name = "water", .frames = "60" },
        .{ .example = "liquid", .name = "liquid", .frames = "90" },
        .{ .example = "shadows", .name = "shadows", .frames = "30" },
        .{ .example = "stereo", .name = "stereo", .frames = "30" },
        .{ .example = "lightmap", .name = "lightmap", .frames = "30" },
        .{ .example = "voxels", .name = "voxels", .frames = "30" },
        .{ .example = "asteroids", .name = "asteroids", .frames = "30" },
        .{ .example = "shadows", .name = "virtual_shadows", .frames = "30", .arguments = &.{ "--vsm", "1" } },
        .{ .example = "upscaling", .name = "fsr2", .frames = "30", .arguments = &.{ "--mode", "4" } },
        .{ .example = "upscaling", .name = "fsr3", .frames = "30", .arguments = &.{ "--mode", "5" } },
        .{ .example = "upscaling", .name = "coarse_shading", .frames = "30", .arguments = &.{ "--mode", "2", "--vrs" } },
        .{ .example = "meadow", .name = "meadow", .frames = "60" },
        .{ .example = "materials", .name = "materials", .frames = "60" },
        .{ .example = "lights", .name = "lights", .frames = "60" },
        .{ .example = "decals", .name = "decals", .frames = "60" },
        .{ .example = "text", .name = "text", .frames = "60" },
        .{ .example = "views", .name = "views", .frames = "60" },
        .{ .example = "post", .name = "post", .frames = "60" },
        .{ .example = "shader", .name = "shader", .frames = "60" },
        .{ .example = "rtx", .name = "rtx", .frames = "40" },
        .{ .example = "rtx", .name = "rtx_path", .frames = "40", .arguments = &.{ "--path", "1" } },
        .{ .example = "pathtrace", .name = "pathtrace", .frames = "60" },
        .{ .example = "pathtrace", .name = "pathtrace_software", .frames = "60", .arguments = &.{ "--software", "1" } },
        .{ .example = "water", .name = "dive", .frames = "60", .arguments = &.{ "--dive", "1" } },
        .{ .example = "clouds", .name = "storm", .frames = "60", .arguments = &.{ "--storm", "1" } },
    }) |shot| {
        const run = b.addRunArtifact(example_exes.get(shot.example).?);
        run.setCwd(b.path("."));
        run.has_side_effects = true;
        run.addArgs(shot.arguments);
        run.addArgs(&.{ "--frames", shot.frames, "--screenshot" });
        _ = run.addOutputFileArg(b.fmt("verify_{s}.png", .{shot.name}));
        verify_step.dependOn(&run.step);
    }
}

/// A path option resolved against this build's root, so the SDKs can sit
/// beside the examples or anywhere else.
fn sdkPath(b: *std.Build, name: []const u8, description: []const u8) []const u8 {
    return b.pathResolve(&.{ b.build_root.path orelse ".", b.option([]const u8, name, description) orelse name });
}

/// Builds GLFW from source into `module` for `target`, with the platform
/// headers and macOS frameworks fetched rather than taken from the system.
/// On Linux it has both X11 and Wayland, and loads their libraries at run
/// time. Returns false while a dependency is being fetched.
fn addGlfw(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, source: *std.Build.Dependency) bool {
    module.link_libc = true;
    module.addIncludePath(source.path("include"));
    const common = [_][]const u8{ "context.c", "init.c", "input.c", "monitor.c", "platform.c", "vulkan.c", "window.c", "egl_context.c", "osmesa_context.c", "null_init.c", "null_monitor.c", "null_window.c", "null_joystick.c" };
    module.addCSourceFiles(.{ .root = source.path("src"), .files = &common, .flags = &.{"-w"} });
    switch (target.result.os.tag) {
        .windows => {
            const files = [_][]const u8{ "win32_init.c", "win32_joystick.c", "win32_module.c", "win32_monitor.c", "win32_thread.c", "win32_time.c", "win32_window.c", "wgl_context.c" };
            module.addCSourceFiles(.{ .root = source.path("src"), .files = &files, .flags = &.{"-w"} });
            module.addCMacro("_GLFW_WIN32", "1");
            for ([_][]const u8{ "gdi32", "user32", "shell32" }) |system| module.linkSystemLibrary(system, .{});
        },
        .macos => {
            const sdk = b.lazyDependency("xcode_frameworks", .{}) orelse return false;
            module.addSystemFrameworkPath(sdk.path("Frameworks"));
            module.addSystemIncludePath(sdk.path("include"));
            module.addLibraryPath(sdk.path("lib"));
            module.addCMacro("_GLFW_COCOA", "1");
            module.addCMacro("__kernel_ptr_semantics", "");
            const files = [_][]const u8{ "cocoa_time.c", "posix_module.c", "posix_thread.c", "cocoa_init.m", "cocoa_joystick.m", "cocoa_monitor.m", "cocoa_window.m", "nsgl_context.m" };
            module.addCSourceFiles(.{ .root = source.path("src"), .files = &files, .flags = &.{"-w"} });
            module.linkSystemLibrary("objc", .{});
            for ([_][]const u8{ "Cocoa", "IOKit", "CoreFoundation", "QuartzCore", "AppKit", "CoreGraphics", "CoreServices", "Foundation", "ApplicationServices", "CFNetwork", "ColorSync", "CoreText", "ImageIO" }) |framework| module.linkFramework(framework, .{});
        },
        else => {
            const x11 = b.lazyDependency("x11_headers", .{}) orelse return false;
            const wayland = b.lazyDependency("wayland_headers", .{}) orelse return false;
            module.addSystemIncludePath(x11.path(""));
            module.addSystemIncludePath(wayland.path("wayland"));
            module.addSystemIncludePath(wayland.path("wayland-protocols"));
            module.addCMacro("_GLFW_X11", "1");
            module.addCMacro("_GLFW_WAYLAND", "1");
            module.addCMacro("HAVE_MEMFD_CREATE", "1");
            const files = [_][]const u8{ "linux_joystick.c", "posix_module.c", "posix_poll.c", "posix_thread.c", "posix_time.c", "xkb_unicode.c", "glx_context.c", "x11_init.c", "x11_monitor.c", "x11_window.c", "wl_init.c", "wl_monitor.c", "wl_window.c" };
            module.addCSourceFiles(.{ .root = source.path("src"), .files = &files, .flags = &.{ "-w", "-Wno-implicit-function-declaration" } });
        },
    }
    return true;
}

/// Wraps a windowed example as an Android `NativeActivity` and packs it,
/// with the assets its source names, into zig-out/apk/<name>.apk. Null for
/// an example whose assets would make the package over `android_asset_limit`.
fn addAndroidExample(b: *std.Build, example: Example, module: *std.Build.Module, glfw_module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, packer: std.Build.LazyPath) ?*std.Build.Step {
    const assets = exampleAssets(b, example);
    var bytes: u64 = 0;
    for (assets) |asset| bytes += if (b.build_root.handle.statFile(b.graph.io, asset, .{})) |stat| stat.size else |_| 0;
    if (bytes > android_asset_limit) return null;
    const host = b.createModule(.{ .root_source_file = b.path("examples/android/host.zig"), .target = target, .optimize = optimize, .link_libc = true });
    host.addImport("example", module);
    host.addImport("glfw", glfw_module);
    for ([_][]const u8{ "android", "log", "dl" }) |system| host.linkSystemLibrary(system, .{});
    const library = b.addLibrary(.{ .name = "main", .linkage = .dynamic, .root_module = host, .use_llvm = true });
    const pack = std.Build.Step.Run.create(b, b.fmt("pack {s}.apk", .{example.name}));
    pack.addFileArg(packer);
    const apk = pack.addOutputFileArg(b.fmt("{s}.apk", .{example.name}));
    pack.addArgs(&.{ b.fmt("org.limn.{s}", .{example.name}), b.fmt("limn {s}", .{example.name}) });
    if (target.result.cpu.arch == .x86_64) pack.addPrefixedFileArg("x86_64:", library.getEmittedBin()) else pack.addFileArg(library.getEmittedBin());
    for (assets) |asset| {
        pack.addArg(b.fmt("assets/{s}", .{asset}));
        pack.addFileArg(b.path(asset));
    }
    const install = b.addInstallFile(apk, b.fmt("apk/{s}.apk", .{example.name}));
    return &install.step;
}

/// The files under examples/assets that an example's source, or a source
/// file next to it that it imports, names; a named directory gives all of
/// its files, and so does the folder of a named `.gltf`, for its buffers and
/// images.
fn exampleAssets(b: *std.Build, example: Example) []const []const u8 {
    const io = b.graph.io;
    var assets: std.ArrayList([]const u8) = .empty;
    var sources: std.ArrayList([]const u8) = .empty;
    sources.appendSlice(b.allocator, &.{ example.root, "examples/window.zig" }) catch @panic("OOM");
    var read: usize = 0;
    while (read < sources.items.len) : (read += 1) {
        const text = b.build_root.handle.readFileAlloc(io, sources.items[read], b.allocator, .unlimited) catch continue;
        var quoted = std.mem.splitScalar(u8, text, '"');
        var inside = false;
        while (quoted.next()) |piece| : (inside = !inside) {
            if (!inside) continue;
            if (std.mem.endsWith(u8, piece, ".zig") and std.mem.indexOfScalar(u8, piece, '/') == null) {
                const local = b.fmt("examples/{s}", .{piece});
                for (sources.items) |known| {
                    if (std.mem.eql(u8, known, local)) break;
                } else sources.append(b.allocator, local) catch @panic("OOM");
                continue;
            }
            if (!std.mem.startsWith(u8, piece, "examples/assets/")) continue;
            const folder = if (std.mem.endsWith(u8, piece, ".gltf")) piece[0 .. std.mem.lastIndexOfScalar(u8, piece, '/').? + 1] else piece;
            if (!std.mem.endsWith(u8, folder, "/")) {
                appendNew(b, &assets, piece);
                continue;
            }
            var directory = b.build_root.handle.openDir(io, folder, .{ .iterate = true }) catch continue;
            defer directory.close(io);
            var walker = directory.walk(b.allocator) catch @panic("OOM");
            defer walker.deinit();
            while (walker.next(io) catch null) |entry| {
                if (entry.kind == .file) appendNew(b, &assets, b.fmt("{s}{s}", .{ folder, entry.path }));
            }
        }
    }
    return assets.items;
}

fn appendNew(b: *std.Build, list: *std.ArrayList([]const u8), item: []const u8) void {
    for (list.items) |known| {
        if (std.mem.eql(u8, known, item)) return;
    }
    list.append(b.allocator, item) catch @panic("OOM");
}

/// The most asset bytes an APK is packed with; the Bistro scene is left out.
const android_asset_limit = 1 << 30;
