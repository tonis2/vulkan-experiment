const std = @import("std");

const engine = @import("engine");
const window = @import("window");

const Pipeline = @import("pipelines/default.zig");
const Renderpass = @import("renderpass/default.zig");

const Context = engine.Context;
const Swapchain = engine.Swapchain;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = &gpa.allocator;

pub fn main() !void {
    defer std.debug.assert(!gpa.deinit());

    var win = try window.init("test", .{ .width = 1200, .height = 800 });
    defer win.deinit();

    var context = try Context.init(allocator, win);
    defer context.deinit();

    var swapchain = try Swapchain.init(context, win.size.Extent());
    defer swapchain.deinit();

    var renderpass = try Renderpass.new(context, swapchain.image_format);
    defer renderpass.deinit();

    var pipeline = try Pipeline.new(context, renderpass);
    defer pipeline.deinit();

    std.debug.print("Using device: {s} \n", .{context.deviceName()});
}
