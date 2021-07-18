const std = @import("std");
const vk = @import("vk");

const Allocator = std.mem.Allocator;

const Context = @import("./context.zig");
const Swapchain = @import("./swapchain.zig");
const Window = @import("window");
const Pipeline = @import("./pipelines/default.zig");

usingnamespace @import("./settings.zig");

const Self = @This();

context: Context,
swapchain: Swapchain,

pub fn init(allocator: *Allocator, window: *const Window) !Self {
    var context = try Context.init(allocator, window);
    var swapchain = try Swapchain.init(&context, allocator, .{ .width = 800, .height = 600 });
    defer swapchain.deinit();

    // var pipeline = Pipeline.new(&context);
    // defer pipeline.deinit();

    return Self{
        .context = context,
        .swapchain = swapchain,
    };
}

pub fn deinit(self: Self) void {
    self.context.deinit();
}
