const std = @import("std");
const vk = @import("vk");

const Allocator = std.mem.Allocator;

const Context = @import("./context.zig");
const Swapchain = @import("./swapchain.zig").Swapchain;
const Window = @import("window");
const Pipeline = @import("./pipelines/default.zig");

usingnamespace @import("./settings.zig");

const Self = @This();

context: Context,

pub fn init(allocator: *Allocator, window: *Window) !void {
    const context = try Context.init(allocator, window);
    std.debug.print("Using device: {s}\n", .{context.deviceName()});

    // const extent = vk.Extent2D{ .width = 800, .height = 600 };
    // var swapchain = try Swapchain.init(&context, allocator, extent);
    // defer swapchain.deinit();

    // var pipeline = Pipeline.new(&context);
    // defer pipeline.deinit();
}

pub fn deinit(self: *Self) !void {
    self.context.deinit();
}
