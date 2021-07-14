const std = @import("std");

const engine = @import("engine");
const glfWindow = @import("window");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    defer std.debug.assert(!gpa.deinit());

    const window = glfWindow.init("test", .{ .width = 400, .height = 500 });
    const vkEngine = try engine.init(allocator, &window);

    defer vkEngine.deinit();
}
