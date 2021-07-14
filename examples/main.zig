const std = @import("std");

const engine = @import("engine");
const glfWindow = @import("window");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    defer std.debug.assert(!gpa.deinit());

    const window = try glfWindow.init("test", .{ .width = 400, .height = 500 });
    defer window.deinit();
    
    const vkEngine = try engine.init(allocator, &window);

    std.debug.print("Using device: {s} \n", .{vkEngine.context.deviceName()});
    
    defer vkEngine.deinit();
}
