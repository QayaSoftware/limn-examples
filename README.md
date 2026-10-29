# limn examples

The examples for [limn](https://github.com/QayaSoftware/sdk/tree/master/libs/limn),
the renderer of the [Qaya SDK](https://github.com/QayaSoftware/sdk). Every
picture in limn's README is one of them.

## Build

Requires Zig 0.16 and a Vulkan 1.3 driver. The assets are stored with Git
LFS: run `git lfs install` before cloning, or `git lfs pull` afterwards.
Everything else is fetched by the build: limn, GLFW and its platform headers,
the macOS SDK headers, MoltenVK and the Android NDK.

```sh
zig build            # every example
zig build run        # the meadow example
zig build <name>     # one example, such as `zig build materials`
zig build check      # compile them all without running them
zig build verify     # formatting, and the examples rendered under Vulkan validation
zig build cross      # every desktop target and Android, into zig-out/cross
```

For `-Dtarget=aarch64-linux-android` each example becomes an APK in
`zig-out/apk`, signed with a fixed debug key: `adb install` it. macOS
builds put `libMoltenVK.dylib` beside the examples.

Add `-Doptimize=ReleaseFast` for full speed. Every example takes `--frames N`
and `--screenshot file.png`, and lists its keys at the top of its source
file.

limn's options pass through: `-Dfidelityfx`, `-Ddlss`, `-Dnrd`,
`-Dsystem_tools` and `-Dtsan`. DLSS and NRD are built in when their SDKs are
at `dlss_sdk/` and `nrd_sdk/` here, or wherever `-Ddlss_sdk` and `-Dnrd_sdk`
point; `zig build limn-dlss-sdk` and `zig build limn-nrd-sdk` in the SDK fetch them.

## Working on limn and the examples together

The build depends on the SDK's published package. To build against a local
checkout of the SDK instead:

```sh
zig build --fork=../sdk
```

## License

Apache-2.0; see [`LICENSE`](LICENSE). The assets keep their own terms, some
for non-commercial use only: [`examples/assets/README.md`](examples/assets/README.md).
