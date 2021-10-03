const std = @import("std");

usingnamespace @import("c.zig");
usingnamespace @import("utils.zig");
usingnamespace @import("zva");

const Vulkan = @import("vulkan.zig");

pub fn Buffer(comptime T: type, usage: c_int) type {
    return struct {
        const Self = @This();

        buffer: VkBuffer,
        allocation: Allocation,
        len: usize,

        pub fn init(vulkan: Vulkan, content: []const T) !Self {
            const bufferSize = @sizeOf(T) * content.len;
            var stagingBuffer: VkBuffer = undefined;

            var stage_allocation = try createBuffer(
                .CpuToGpu,
                VkBufferCreateInfo{
                    .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .size = bufferSize,
                    .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                    .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
                    .queueFamilyIndexCount = 0,
                    .pQueueFamilyIndices = null,
                },
                VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                vulkan.device,
                vulkan.physical_device,
                vulkan.vAllocator,
                &stagingBuffer,
            );
            //  var data: []const T = undefined;
            // std.mem.copy(T, std.mem.bytesAsSlice(T, stage_allocation.data), data);

            defer {
                vkDestroyBuffer(vulkan.device, stagingBuffer, null);
                vulkan.vAllocator.free(stage_allocation);
            }

            var memoryBuffer: VkBuffer = undefined;
            var memoryAllocation = try createBuffer(
                .GpuOnly,
                VkBufferCreateInfo{
                    .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .size = bufferSize,
                    .usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | usage,
                    .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
                    .queueFamilyIndexCount = 0,
                    .pQueueFamilyIndices = null,
                },
                VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                vulkan.device,
                vulkan.physical_device,
                vulkan.vAllocator,
                &memoryBuffer,
            );

            errdefer {
                vkDestroyBuffer(vulkan.device, memoryBuffer, null);
                vulkan.vAllocator.free(memoryAllocation);
            }

            try copyBuffer(vulkan.device, vulkan.graphics_queue, vulkan.command_pool, stagingBuffer, memoryBuffer, bufferSize);

            return Self{
                .buffer = memoryBuffer,
                .allocation = memoryAllocation,
                .len = bufferSize,
            };
        }

        pub fn deinit(self: Self, vulkan: Vulkan) void {
            vkDestroyBuffer(vulkan.device, self.buffer, null);
            vulkan.vAllocator.free(self.allocation);
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

    var command_buffer: VkCommandBuffer = undefined;

    try Vulkan.allocateCommandBuffers(device, &VkCommandBufferAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandPool = command_pool,
        .commandBufferCount = 1,
    }, &command_buffer);

    defer vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);

    try Vulkan.beginCommandBuffer(command_buffer, &VkCommandBufferBeginInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        .pInheritanceInfo = null,
    });

    vkCmdCopyBuffer(command_buffer, src, dst, 1, &VkBufferCopy{ .srcOffset = 0, .dstOffset = 0, .size = size });
    try Vulkan.endCommandBuffer(command_buffer);

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

    try Vulkan.queueSubmit(graphics_queue, 1, &submit_info, null);
    try Vulkan.queueWaitIdle(graphics_queue);
}

pub fn createBuffer(
    memoryUsage: MemoryUsage,
    info: VkBufferCreateInfo,
    propertyFlags: VkMemoryPropertyFlags,
    device: VkDevice,
    pDevice: VkPhysicalDevice,
    allocator: Allocator,
    buffer: *VkBuffer,
) !Allocation {
    try checkSuccess(vkCreateBuffer(device, &info, null, buffer), error.VulkanVertexBufferCreationFailed);
    errdefer vkDestroyBuffer(device, buffer.*, null);

    var mem_reqs: VkMemoryRequirements = undefined;
    vkGetBufferMemoryRequirements(device, buffer.*, &mem_reqs);
    var memoryType = try findMemoryType(pDevice, mem_reqs.memoryTypeBits, propertyFlags);

    var allocation = try allocator.alloc(mem_reqs.size, mem_reqs.alignment, memoryType, memoryUsage, .Buffer);

    try checkSuccess(vkBindBufferMemory(device, buffer.*, allocation.memory, allocation.offset), error.VulkanBindBufferMemoryFailure);

    return allocation;
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
