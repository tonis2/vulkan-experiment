const std = @import("std");

const engine = @import("engine");
const window = @import("window");

const pipelines = @import("../pipelines/default.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    defer std.debug.assert(!gpa.deinit());

    const win = try window.init("test", .{ .width = 1200, .height = 800 });
    defer win.deinit();

    const vkEngine = try engine.init(allocator, &win);
    defer vkEngine.deinit();

    std.debug.print("Using device: {s} \n", .{vkEngine.context.deviceName()});
}
