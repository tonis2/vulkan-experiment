const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const Vulkan = @import("vulkan");

const Buffer = Vulkan.Buffer;
const Window = Vulkan.Window;
const Camera = @import("camera.zig");

usingnamespace Vulkan.C;
usingnamespace Vulkan.Utils;
usingnamespace @import("zalgebra");

pub const Pipeline = @import("pipeline.zig");
pub const Renderpass = @import("renderpass.zig");

const Vertex = Pipeline.Vertex;

pub const log_level = .info;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const vertices = [_]Vertex{
    Vertex{ .pos = Vec3.new(50.0, 50.0, 1.0), .color = Vec3.new(1.0, 1.0, 1.0) },
    Vertex{ .pos = Vec3.new(400, 50.0, 1.0), .color = Vec3.new(1.0, 1.0, 1.0) },
    Vertex{ .pos = Vec3.new(400, 450, 1.0), .color = Vec3.new(1.0, 1.0, 1.0) },
    Vertex{ .pos = Vec3.new(50.0, 450, 1.0), .color = Vec3.new(1.0, 1.0, 1.0) },
};

const v_indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

// fn keyCallback(window: ?*GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
//     _ = window;
//     _ = action;
//     _ = scancode;
//     _ = mods;
//     log.info("{d} \n", .{key});
// }

pub fn main() !void {
    const allocator = &gpa.allocator;

    // defer std.debug.assert(!gpa.deinit());

    const WIDTH = 1400;
    const HEIGHT = 800;

    const window = try Window.init(WIDTH, HEIGHT);
    errdefer window.deinit();

    var vulkan = try Vulkan.init(allocator, window);
    errdefer vulkan.deinit();

    var syncronisation = try Vulkan.Synchronization.init(&vulkan, allocator, vulkan.swapchain.images.len);
    errdefer syncronisation.deinit();

    var camera = Camera.new(WIDTH, HEIGHT, 400);
    camera.translate(Vec3.new(0.0, 0.0, 0.0));

    // const renderpass = try Renderpass.init(vulkan);
    // const pipeline = try Pipeline.init(vulkan, renderpass.renderpass, camera);
    const vertex_buffer = try Buffer(Vertex, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT).init(vulkan, &vertices);
    const index_buffer = try Buffer(u16, VK_BUFFER_USAGE_INDEX_BUFFER_BIT).init(vulkan, &v_indices);

    _ = vertex_buffer;
    _ = index_buffer;

    defer {
        _ = vkDeviceWaitIdle(vulkan.device);

        vertex_buffer.deinit(vulkan);
        index_buffer.deinit(vulkan);
        // renderpass.deinit(vulkan);
        // pipeline.deinit(vulkan);
        syncronisation.deinit();
        vulkan.deinit();
        window.deinit();
    }

    // _ = glfwSetKeyCallback(window.window, keyCallback);

    // while (!window.shouldClose()) {
    //     window.pollEvents();
    //     for (vulkan.commandbuffers) |buffer, i| {
    //         const begin_info = VkCommandBufferBeginInfo{
    //             .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    //             .pNext = null,
    //             .flags = 0,
    //             .pInheritanceInfo = null,
    //         };

    //         try checkSuccess(vkBeginCommandBuffer(buffer, &begin_info), error.VulkanBeginCommandBufferFailure);

    //         const clear_color = [_]VkClearValue{VkClearValue{
    //             .color = VkClearColorValue{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } },
    //         }};

    //         const render_pass_info = VkRenderPassBeginInfo{
    //             .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
    //             .pNext = null,
    //             .renderPass = renderpass.renderpass,
    //             .framebuffer = renderpass.framebuffers[i],
    //             .renderArea = VkRect2D{
    //                 .offset = VkOffset2D{ .x = 0, .y = 0 },
    //                 .extent = vulkan.swapchain.extent,
    //             },
    //             .clearValueCount = 1,
    //             .pClearValues = &clear_color,
    //         };

    //         vkCmdBeginRenderPass(buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
    //         vkCmdBindPipeline(buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.pipeline);
    //         vkCmdBindDescriptorSets(buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.layout, 0, 1, &[_]VkDescriptorSet{pipeline.descriptor.sets[i]}, 0, null);
    //         vkCmdBindVertexBuffers(buffer, 0, 1, &[_]VkBuffer{vertex_buffer.buffer}, &[_]VkDeviceSize{0});
    //         vkCmdBindIndexBuffer(buffer, index_buffer.buffer, 0, VK_INDEX_TYPE_UINT16);

    //         vkCmdDrawIndexed(buffer, @intCast(u32, index_buffer.len), 1, 0, 0, 0);
    //         vkCmdEndRenderPass(buffer);

    //         try checkSuccess(vkEndCommandBuffer(buffer), error.VulkanCommandBufferEndFailure);
    //     }

    //     try syncronisation.drawFrame(vulkan.commandbuffers);
    // }
}
