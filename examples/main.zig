const std = @import("std");

const engine = @import("engine");
const window = @import("window");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    defer std.debug.assert(!gpa.deinit());

    const win = try window.init("test", .{ .width = 400, .height = 500 });
    defer win.deinit();
    
    const vkEngine = try engine.init(allocator, &win);

    std.debug.print("Using device: {s} \n", .{vkEngine.context.deviceName()});
    
    defer vkEngine.deinit();
}
