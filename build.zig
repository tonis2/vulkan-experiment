const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Pkg = std.build.Pkg;
const FileSource = std.build.FileSource;

const examples = [_][2][]const u8{
    .{ "main", "examples/main.zig" },
};

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const Vulkan = Pkg{ .name = "vulkan", .path = FileSource{ .path = "src/vulkan.zig" } };
    for (examples) |example| {
        const name = example[0];
        const path = example[1];
        const exe = b.addExecutable(name, path);

        exe.setTarget(target);
        exe.setBuildMode(mode);

        exe.linkLibC();
        exe.linkSystemLibrary("glfw");
        exe.linkSystemLibrary("vulkan");
        exe.addPackage(Vulkan);
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step(name, "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}
