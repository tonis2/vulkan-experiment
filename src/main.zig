const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Context = @import("context.zig");
const Pipeline = @import("pipeline.zig");
const log = std.log;

usingnamespace @import("c.zig");
usingnamespace @import("utils.zig");
usingnamespace @import("window.zig");
usingnamespace @import("buffer.zig");

pub const log_level: std.log.Level = .warn;

const vertices = [_]Vertex{
    Vertex{ .pos = Vec2.new(-0.5, -0.5), .color = Vec3.new(1.0, 0.0, 0.0) },
    Vertex{ .pos = Vec2.new(0.5, -0.5), .color = Vec3.new(0.0, 1.0, 0.0) },
    Vertex{ .pos = Vec2.new(0.5, 0.5), .color = Vec3.new(0.0, 0.0, 1.0) },
    Vertex{ .pos = Vec2.new(-0.5, 0.5), .color = Vec3.new(1.0, 1.0, 1.0) },
};

const v_indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const allocator = &gpa.allocator;

    defer std.debug.assert(!gpa.deinit());

    var context = try Context.init(allocator);
    defer context.deinit();

    const pipeline = try Pipeline.init(context.vulkan.device, context.vulkan.render_pass, context.vulkan.swap_chain.extent);
    const vertex_buffer = try VertexBuffer.init(context.vulkan.physical_device, context.vulkan.device, context.vulkan.graphics_queue, context.vulkan.command_pool, &vertices);
    const index_buffer = try IndexBuffer.init(context.vulkan.physical_device, context.vulkan.device, context.vulkan.graphics_queue, context.vulkan.command_pool, &v_indices);

    const command_buffers = try createCommandBuffers(
        allocator,
        context.vulkan.device,
        context.vulkan.render_pass,
        context.vulkan.command_pool,
        context.vulkan.swap_chain_framebuffers,
        context.vulkan.swap_chain.extent,
        pipeline.pipeline,
        vertex_buffer,
        index_buffer,
    );

    defer {
        vertex_buffer.deinit(context.vulkan.device);
        index_buffer.deinit(context.vulkan.device);
        pipeline.deinit(context.vulkan.device);

        vkFreeCommandBuffers(
            context.vulkan.device,
            context.vulkan.command_pool,
            @intCast(u32, command_buffers.len),
            command_buffers.ptr,
        );
        allocator.free(command_buffers);
    }

    var callback = ResizeCallback{
        .data = &context,
        .cb = framebufferResizeCallback,
    };

    context.window.registerResizeCallback(&callback);

    while (!context.shouldClose()) {
        try context.renderFrame(command_buffers);
    }
}

fn framebufferResizeCallback(data: *c_void) void {
    var context = @ptrCast(*Context, @alignCast(@alignOf(*Context), data));
    context.framebuffer_resized = true;
}
