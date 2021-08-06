const std = @import("std");
const Allocator = std.mem.Allocator;

usingnamespace @import("c.zig");
usingnamespace @import("utils.zig");

const vk = @import("vulkan.zig");

pub const VertexBuffer = Buffer(Vertex, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
pub const IndexBuffer = Buffer(u16, VK_BUFFER_USAGE_INDEX_BUFFER_BIT);

fn Buffer(comptime T: type, usage: c_int) type {
    return struct {
        const Self = @This();

        buffer: VkBuffer,
        memory: VkDeviceMemory,
        len: usize,

        pub fn init(
            physical_device: VkPhysicalDevice,
            device: VkDevice,
            graphics_queue: VkQueue,
            command_pool: VkCommandPool,
            content: []const T,
        ) !Self {
            const buffer_size = @sizeOf(T) * content.len;

            var staging_buffer: VkBuffer = undefined;
            var staging_memory: VkDeviceMemory = undefined;
            try createBuffer(
                physical_device,
                device,
                buffer_size,
                VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                &staging_buffer,
                &staging_memory,
            );
            defer {
                vkDestroyBuffer(device, staging_buffer, null);
                vkFreeMemory(device, staging_memory, null);
            }

            var data: ?*c_void = undefined;
            try checkSuccess(vkMapMemory(device, staging_memory, 0, buffer_size, 0, &data), error.VulkanMapMemoryError);
            const bytes = @ptrCast([*]const u8, @alignCast(@alignOf(T), std.mem.sliceAsBytes(content)));
            @memcpy(@ptrCast([*]u8, data), bytes, buffer_size);
            vkUnmapMemory(device, staging_memory);

            var buffer: VkBuffer = undefined;
            var memory: VkDeviceMemory = undefined;
            try createBuffer(
                physical_device,
                device,
                buffer_size,
                VK_BUFFER_USAGE_TRANSFER_DST_BIT | usage,
                VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                &buffer,
                &memory,
            );
            errdefer {
                vkDestroyBuffer(device, buffer, null);
                vkFreeMemory(device, memory, null);
            }

            try copyBuffer(device, graphics_queue, command_pool, staging_buffer, buffer, buffer_size);

            return Self{
                .buffer = buffer,
                .memory = memory,
                .len = content.len,
            };
        }

        pub fn deinit(self: Self, device: VkDevice) void {
            vkDestroyBuffer(device, self.buffer, null);
            vkFreeMemory(device, self.memory, null);
        }
    };
}

pub fn copyBuffer(
    device: VkDevice,
    graphics_queue: VkQueue,
    command_pool: VkCommandPool,
    src: VkBuffer,
    dst: VkBuffer,
    size: VkDeviceSize,
) !void {
    // OPTIMIZE: Create separate command pool for short lived buffers
    const alloc_info = VkCommandBufferAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandPool = command_pool,
        .commandBufferCount = 1,
    };
    var command_buffer: VkCommandBuffer = undefined;
    try vk.allocateCommandBuffers(device, &alloc_info, &command_buffer);
    defer vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);

    const begin_info = VkCommandBufferBeginInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    };

    try vk.beginCommandBuffer(command_buffer, &begin_info);

    const copy_region = VkBufferCopy{ .srcOffset = 0, .dstOffset = 0, .size = size };
    vkCmdCopyBuffer(command_buffer, src, dst, 1, &copy_region);
    try vk.endCommandBuffer(command_buffer);

    const submit_info = VkSubmitInfo{
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer,
        .waitSemaphoreCount = 0,
        .pWaitSemaphores = null,
        .pWaitDstStageMask = null,
        .signalSemaphoreCount = 0,
        .pSignalSemaphores = null,
    };

    try vk.queueSubmit(graphics_queue, 1, &submit_info, null);
    try vk.queueWaitIdle(graphics_queue);
}

fn findMemoryType(physical_device: VkPhysicalDevice, type_filter: u32, properties: VkMemoryPropertyFlags) !u32 {
    var mem_props: VkPhysicalDeviceMemoryProperties = undefined;
    vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_props);

    var i: u32 = 0;
    while (i < mem_props.memoryTypeCount) : (i += 1) {
        if (type_filter & (@intCast(u32, 1) << @intCast(u5, i)) != 0 and
            (mem_props.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return i;
        }
    }

    return error.VulkanSuitableMemoryTypeNotFound;
}

fn createBuffer(
    physical_device: VkPhysicalDevice,
    device: VkDevice,
    size: VkDeviceSize,
    usage: VkBufferUsageFlags,
    properties: VkMemoryPropertyFlags,
    buffer: *VkBuffer,
    buffer_memory: *VkDeviceMemory,
) !void {
    const info = VkBufferCreateInfo{
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
    };

    try checkSuccess(vkCreateBuffer(device, &info, null, buffer), error.VulkanVertexBufferCreationFailed);
    errdefer vkDestroyBuffer(device, buffer.*, null);

    var mem_reqs: VkMemoryRequirements = undefined;
    vkGetBufferMemoryRequirements(device, buffer.*, &mem_reqs);

    const alloc_info = VkMemoryAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = mem_reqs.size,
        .memoryTypeIndex = try findMemoryType(physical_device, mem_reqs.memoryTypeBits, properties),
    };

    // OPTIMIZE: should not allocate for every individual buffer.
    // allocate a single big chunk of memory and a single buffer, and use offsets instead
    // (or use VulkanMemoryAllocator).
    // see: https://developer.nvidia.com/vulkan-memory-management
    try checkSuccess(vkAllocateMemory(device, &alloc_info, null, buffer_memory), error.VulkanAllocateMemoryFailure);
    errdefer vkFreeMemory(device, buffer_memory.*, null);

    try checkSuccess(vkBindBufferMemory(device, buffer.*, buffer_memory.*, 0), error.VulkanBindBufferMemoryFailure);
}

pub fn createCommandBuffers(
    allocator: *Allocator,
    device: VkDevice,
    render_pass: VkRenderPass,
    command_pool: VkCommandPool,
    framebuffers: []VkFramebuffer,
    swap_chain_extent: VkExtent2D,
    graphics_pipeline: VkPipeline,
    vertex_buffer: VertexBuffer,
    index_buffer: IndexBuffer,
) ![]VkCommandBuffer {
    var buffers = try allocator.alloc(VkCommandBuffer, framebuffers.len);
    errdefer allocator.free(buffers);

    const alloc_info = VkCommandBufferAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(u32, buffers.len),
    };

    try vk.allocateCommandBuffers(device, &alloc_info, buffers.ptr);

    for (buffers) |buffer, i| {
        const begin_info = VkCommandBufferBeginInfo{
            .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = 0,
            .pInheritanceInfo = null,
        };
        try vk.beginCommandBuffer(buffer, &begin_info);

        const clear_color = [_]VkClearValue{VkClearValue{
            .color = VkClearColorValue{ .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 } },
        }};
        const render_pass_info = VkRenderPassBeginInfo{
            .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = render_pass,
            .framebuffer = framebuffers[i],
            .renderArea = VkRect2D{
                .offset = VkOffset2D{ .x = 0, .y = 0 },
                .extent = swap_chain_extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };

        vkCmdBeginRenderPass(buffer, &render_pass_info, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline(buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

        const vertex_buffers = [_]VkBuffer{vertex_buffer.buffer};
        const offsets = [_]VkDeviceSize{0};
        vkCmdBindVertexBuffers(buffer, 0, 1, &vertex_buffers, &offsets);
        vkCmdBindIndexBuffer(buffer, index_buffer.buffer, 0, VK_INDEX_TYPE_UINT16);
        vkCmdDrawIndexed(buffer, @intCast(u32, index_buffer.len), 1, 0, 0, 0);
        vkCmdEndRenderPass(buffer);

        try vk.endCommandBuffer(buffer);
    }

    return buffers;
}
