const std = @import("std");
const Allocator = std.mem.Allocator;

usingnamespace @import("c.zig");
usingnamespace @import("utils.zig");

const Vulkan = @import("vulkan.zig");

pub const BufferInfo = struct { buffer: VkBuffer, size: VkSize, range: VkSize };
pub const ImageInfo = struct { layout: VkImageLayout, imageView: VkImageView, sampler: VkSampler };

const Self = @This();

pool: VkDescriptorPool,
set: VkDescriptorSet,

pub fn new(descriptorWrites: []VkWriteDescriptorSet, layout: *VkDescriptorSetLayout, vulkan: Vulkan) !Self {
    var descriptor: Self = undefined;

    var poolSizes = try vulkan.allocator.alloc(VkDescriptorPoolSize, vulkan.swapchain.images.len);
    defer vulkan.allocator.free(poolSizes);

    var uniformBuffersLen: usize = 0;
    var imageSamplersLen: usize = 0;

    for (descriptorWrites) |set| {
        if (set.pBufferInfo != null) uniformBuffersLen += 1;
        if (set.pImageInfo != null) imageSamplersLen += 1;
    }

    if (uniformBuffersLen > 0) {
        poolSizes[0] = VkDescriptorPoolSize{
            .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = @intCast(u32, uniformBuffersLen),
        };
    }

    if (imageSamplersLen > 0) {
        poolSizes[1] = VkDescriptorPoolSize{
            .type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = @intCast(u32, imageSamplersLen),
        };
    }

    for (descriptorWrites) |*set| {
        set.dstSet = descriptor.set;
    }

    const poolInfo = VkDescriptorPoolCreateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = @intCast(u32, poolSizes.len),
        .pPoolSizes = poolSizes.ptr,
        .maxSets = @intCast(u32, vulkan.swapchain.images.len),
        .pNext = null,
        .flags = 0,
    };

    try checkSuccess(vkCreateDescriptorPool(vulkan.device, &poolInfo, null, &descriptor.pool), error.VulkanDescriptorPoolFailed);

    const descriptorAllocation = VkDescriptorSetAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor.pool,
        .descriptorSetCount = @intCast(u32, descriptorWrites.len),
        .pSetLayouts = layout,
        .pNext = null,
    };

    try checkSuccess(vkAllocateDescriptorSets(vulkan.device, &descriptorAllocation, &descriptor.set), error.DescriptorAllocationFailed);
    vkUpdateDescriptorSets(vulkan.device, @intCast(u32, descriptorWrites.len), @ptrCast([*c]const VkWriteDescriptorSet, &descriptorWrites), 0, null);

    return descriptor;
}

pub fn deinit(self: Self, vulkan: Vulkan) void {
    vkDestroyDescriptorPool(vulkan.device, self.pool, null);
}

// fn createDescriptorPool(size: u32, device: VkDevice) !VkDescriptorPool {
//     const poolSizeUniform = VkDescriptorPoolSize{
//         .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
//         .descriptorCount = size,
//     };

//     const poolSizes = [_]VkDescriptorPoolSize{poolSizeUniform};

//     const poolInfo = VkDescriptorPoolCreateInfo{
//         .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
//         .poolSizeCount = poolSizes.len,
//         .pPoolSizes = &poolSizes,
//         .maxSets = size,
//         .pNext = null,
//         .flags = 0,
//     };

//     var descriptorPool: VkDescriptorPool = undefined;
//     try checkSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &descriptorPool), error.VulkanDescriptorPoolFailed);
//     return descriptorPool;
// }
