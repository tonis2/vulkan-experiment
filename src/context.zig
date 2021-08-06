const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Vulkan = @import("vulkan.zig");
const Window = @import("window.zig");

usingnamespace @import("c.zig");
usingnamespace @import("utils.zig");

const Self = @This();

window: Window,
vulkan: Vulkan,
current_frame: usize,
framebuffer_resized: bool,

pub fn init(allocator: *Allocator) !Self {
    const window = try Window.init();
    errdefer window.deinit();

    var vulkan = try Vulkan.init(allocator, window);
    errdefer vulkan.deinit();

    return Self{
        .vulkan = vulkan,
        .window = window,
        .current_frame = 0,
        .framebuffer_resized = false,
    };
}

pub fn deinit(self: Self) void {
    self.vulkan.deinit();
    self.window.deinit();
}

pub fn renderFrame(self: *Self, command_buffers: []VkCommandBuffer) !void {
    self.window.pollEvents();
    try drawFrame(self, command_buffers);
    self.current_frame = (self.current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
}

pub fn shouldClose(self: Self) bool {
    return self.window.shouldClose();
}

pub fn drawFrame(self: *Self, command_buffers: []VkCommandBuffer) !void {
    var vulkan = &self.vulkan;

    var current_frame = self.current_frame;
    try checkSuccess(
        vkWaitForFences(vulkan.device, 1, &vulkan.sync.in_flight_fences[current_frame], VK_TRUE, MAX_UINT64),
        error.VulkanWaitForFencesFailure,
    );

    var image_index: u32 = 0;
    {
        const result = vkAcquireNextImageKHR(
            vulkan.device,
            vulkan.swap_chain.swap_chain,
            MAX_UINT64,
            vulkan.sync.image_available_semaphores[current_frame],
            null,
            &image_index,
        );
        if (result == VK_ERROR_OUT_OF_DATE_KHR) {
            // swap chain cannot be used (e.g. due to window resize)
            // try vulkan.recreateSwapChain(window);
            return;
        } else if (result != VK_SUCCESS and result != VK_SUBOPTIMAL_KHR) {
            return error.VulkanSwapChainAcquireNextImageFailure;
        } else {
            // swap chain may be suboptimal, but we go ahead and render anyways and recreate it later
        }
    }

    // check if a previous frame is using this image (i.e. it has a fence to wait on)
    if (vulkan.sync.images_in_flight[image_index]) |fence| {
        try checkSuccess(
            vkWaitForFences(vulkan.device, 1, &fence, VK_TRUE, MAX_UINT64),
            error.VulkanWaitForFenceFailure,
        );
    }
    // mark the image as now being in use by this frame
    vulkan.sync.images_in_flight[image_index] = vulkan.sync.in_flight_fences[current_frame];

    const wait_semaphores = [_]VkSemaphore{vulkan.sync.image_available_semaphores[current_frame]};
    const signal_semaphores = [_]VkSemaphore{vulkan.sync.render_finished_semaphores[current_frame]};
    const wait_stages = [_]VkPipelineStageFlags{VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const submit_info = VkSubmitInfo{
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &wait_semaphores,
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffers[image_index],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signal_semaphores,
    };

    try checkSuccess(
        vkResetFences(vulkan.device, 1, &vulkan.sync.in_flight_fences[current_frame]),
        error.VulkanResetFencesFailure,
    );

    try Vulkan.queueSubmit(vulkan.graphics_queue, 1, &submit_info, vulkan.sync.in_flight_fences[current_frame]);

    const swap_chains = [_]VkSwapchainKHR{vulkan.swap_chain.swap_chain};
    const present_info = VkPresentInfoKHR{
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signal_semaphores,
        .swapchainCount = 1,
        .pSwapchains = &swap_chains,
        .pImageIndices = &image_index,
        .pResults = null,
    };

    {
        const result = vkQueuePresentKHR(vulkan.present_queue, &present_info);
        if (result == VK_ERROR_OUT_OF_DATE_KHR or result == VK_SUBOPTIMAL_KHR or self.framebuffer_resized) {
            self.framebuffer_resized = false;
            // try vulkan.recreateSwapChain(window);
        } else if (result != VK_SUCCESS) {
            return error.VulkanQueuePresentFailure;
        }
    }
}

// pub fn recreateSwapChain(self: *Self, window: *const Window) !void {
//     while (window.isMinimized()) {
//         window.waitEvents();
//     }

//     try checkSuccess(vkDeviceWaitIdle(self.device), error.VulkanDeviceWaitIdleFailure);

//     self.cleanUpSwapChain();

//     self.vulkan.swap_chain = try SwapChain.init(
//         self.allocator,
//         self.physical_device,
//         self.device,
//         window,
//         self.surface,
//         self.queue_family_indices,
//     );

//     self.render_pass = try createRenderPass(
//         self.device,
//         self.swap_chain.image_format,
//         self.swap_chain.extent,
//     );

//     self.pipeline = try Pipeline.init(
//         self.device,
//         self.render_pass,
//         self.swap_chain.extent,
//     );

//     self.swap_chain_framebuffers = try createFramebuffers(
//         self.allocator,
//         self.device,
//         self.render_pass,
//         self.swap_chain,
//     );

//     self.command_buffers = try createCommandBuffers(
//         self.allocator,
//         self.device,
//         self.render_pass,
//         self.command_pool,
//         self.swap_chain_framebuffers,
//         self.swap_chain.extent,
//         self.pipeline.pipeline,
//         self.vertex_buffer,
//         self.index_buffer,
//     );
// }
