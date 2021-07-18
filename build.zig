const Builder = @import("std").build.Builder;
const std = @import("std");

const fmt = std.fmt;
const Pkg = std.build.Pkg;
const FileSource = std.build.FileSource;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const examples = [_][2][]const u8{
        .{ "main", "examples/main.zig" },
    };

    for (examples) |example| {
        const name = example[0];
        const path = example[1];
        const exe = b.addExecutable(name, path);

        exe.setTarget(target);
        exe.setBuildMode(mode);

        const vk = Pkg{ .name = "vk", .path = FileSource{ .path = "./dependencies/vk.zig" } };
        const glfw = Pkg{ .name = "glfw", .path = FileSource{ .path = "./dependencies/glfw.zig" }, .dependencies = &.{vk} };
        const window = Pkg{ .name = "window", .path = FileSource{ .path = "./dependencies/window.zig" }, .dependencies = &.{ glfw, vk } };

        const engine = Pkg{ .name = "engine", .path = FileSource{ .path = "src/engine.zig" }, .dependencies = &.{ window, vk, glfw, Pkg{ .name = "zva", .path = FileSource{ .path = "./dependencies/zva.zig" }, .dependencies = &.{vk} } } };

        exe.addPackage(window);
        exe.addPackage(engine);

        exe.linkLibC();
        exe.linkSystemLibrary("glfw");
        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step(name, "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
}