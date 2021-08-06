const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const Vulkan = @import("vulkan");
const Context = Vulkan.Context;
const Buffer = Vulkan.Buffer;

usingnamespace Vulkan.C;
usingnamespace Vulkan.Utils;

pub const Pipeline = @import("pipeline.zig");

pub const log_level: std.log.Level = .warn;
const Vertex = Pipeline.Vertex;
const Vec2 = Pipeline.Vec2;
const Vec3 = Pipeline.Vec3;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const vertices = [_]Vertex{
    Vertex{ .pos = Vec2.new(-0.5, -0.5), .color = Vec3.new(1.0, 0.0, 0.0) },
    Vertex{ .pos = Vec2.new(0.5, -0.5), .color = Vec3.new(0.0, 1.0, 0.0) },
    Vertex{ .pos = Vec2.new(0.5, 0.5), .color = Vec3.new(0.0, 0.0, 1.0) },
    Vertex{ .pos = Vec2.new(-0.5, 0.5), .color = Vec3.new(1.0, 1.0, 1.0) },
};

const v_indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

pub fn main() !void {
    const allocator = &gpa.allocator;

    defer std.debug.assert(!gpa.deinit());

    var context = try Context.init(allocator);
    defer context.deinit();

    const pipeline = try Pipeline.init(context);
    const vertex_buffer = try Buffer(Vertex, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT).init(context, &vertices);
    const index_buffer = try Buffer(u16, VK_BUFFER_USAGE_INDEX_BUFFER_BIT).init(context, &v_indices);

    const command_buffers = try context.vulkan.createCommandBuffers();

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

    var callback = Vulkan.ResizeCallback{
        .data = &context,
        .cb = framebufferResizeCallback,
    };

    context.window.registerResizeCallback(&callback);

    while (!context.shouldClose()) {
        for (command_buffers) |buffer, i| {
            const begin_info = VkCommandBufferBeginInfo{
                .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                .pNext = null,
                .flags = 0,
                .pInheritanceInfo = null,
            };

            try checkSuccess(vkBeginCommandBuffer(buffer, &begin_info), error.VulkanBeginCommandBufferFailure);

            const clear_color = [_]VkClearValue{VkClearValue{
                .color = VkClearColorValue{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } },
            }};

            const render_pass_info = VkRenderPassBeginInfo{
                .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .pNext = null,
                .renderPass = context.vulkan.render_pass,
                .framebuffer = context.vulkan.swap_chain_framebuffers[i],
                .renderArea = VkRect2D{
                    .offset = VkOffset2D{ .x = 0, .y = 0 },
                    .extent = context.vulkan.swap_chain.extent,
                },
                .clearValueCount = 1,
                .pClearValues = &clear_color,
            };

            vkCmdBeginRenderPass(buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
            vkCmdBindPipeline(buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);

            const vertex_buffers = [_]VkBuffer{vertex_buffer.buffer};
            const offsets = [_]VkDeviceSize{0};
            vkCmdBindVertexBuffers(buffer, 0, 1, &vertex_buffers, &offsets);
            vkCmdBindIndexBuffer(buffer, index_buffer.buffer, 0, VK_INDEX_TYPE_UINT16);
            vkCmdDrawIndexed(buffer, @intCast(u32, index_buffer.len), 1, 0, 0, 0);
            vkCmdEndRenderPass(buffer);

            try checkSuccess(vkEndCommandBuffer(buffer), error.VulkanCommandBufferEndFailure);
        }

        try context.renderFrame(command_buffers);
    }
}

fn framebufferResizeCallback(data: *c_void) void {
    var context = @ptrCast(*Context, @alignCast(@alignOf(*Context), data));
    context.framebuffer_resized = true;
}
