const std = @import("std");
const mem = std.mem;
const Pool = @import("pool.zig").Pool;

usingnamespace @cImport({
    @cInclude("vulkan/vulkan.h");
});

pub const Config = struct {
    device: VkDevice,
    physicalDeviceProperties: VkPhysicalDeviceProperties,
    physicalDeviceMemoryProperties: VkPhysicalDeviceMemoryProperties,
    minBlockSize: VkDeviceSize,
    physicalDevice: VkPhysicalDevice,

    allocateMemory: fn (VkDevice, VkMemoryAllocateInfo, *VkDeviceMemory) !void,
    freeMemory: fn (VkDevice, *VkDeviceMemory) void,
    mapMemory: fn (VkDevice, *VkDeviceMemory, usize, VkDeviceSize, usize, ?*c_void) !void,
    unmapMemory: fn (VkDevice, *VkDeviceMemory) void,
};

pub const Allocator = struct {
    const Self = @This();
    allocator: *mem.Allocator,

    config: Config,
    device: VkDevice,

    memory_types: [VK_MAX_MEMORY_TYPES]VkMemoryType,
    memory_type_count: u32,

    pools: []Pool,

    pub fn init(allocator: *mem.Allocator, config: Config) !Self {
        var pools = try allocator.alloc(Pool, config.physicalDeviceMemoryProperties.memory_type_count);

        for (pools) |*pool| pool.* = Pool.init(allocator, config, @intCast(u32, i));

        return Self{
            .allocator = allocator,
            .config = Config,

            .memory_types = config.physicalDeviceMemoryProperties.memory_types,
            .memory_type_count = config.physicalDeviceMemoryProperties.memory_type_count,

            .pools = pools,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.pools) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }
        self.allocator.free(self.pools);
    }

    pub fn alloc(self: *Self, size: VkDeviceSize, alignment: VkDeviceSize, memory_type_bits: u32, usage: MemoryUsage, alloc_type: AllocationType) !Allocation {
        var required_flags: VkMemoryPropertyFlags = .{};
        var preferred_flags: VkMemoryPropertyFlags = .{};

        switch (usage) {
            .GpuOnly => preferred_flags = preferred_flags.merge(VkMemoryPropertyFlags{ .device_local_bit = true }),
            .CpuOnly => required_flags = required_flags.merge(VkMemoryPropertyFlags{ .host_visible_bit = true, .host_coherent_bit = true }),
            .GpuToCpu => {
                required_flags = required_flags.merge(VkMemoryPropertyFlags{ .host_visible_bit = true });
                preferred_flags = preferred_flags.merge(VkMemoryPropertyFlags{ .host_coherent_bit = true, .host_cached_bit = true });
            },
            .CpuToGpu => {
                required_flags = required_flags.merge(VkMemoryPropertyFlags{ .host_visible_bit = true });
                preferred_flags = preferred_flags.merge(VkMemoryPropertyFlags{ .device_local_bit = true });
            },
        }

        var memory_type_index: u32 = 0;
        var index_found = false;

        while (memory_type_index < self.memory_type_count) : (memory_type_index += 1) {
            if ((memory_type_bits >> @intCast(u5, memory_type_index)) & 1 == 0) {
                continue;
            }

            const properties = self.memory_types[memory_type_index].property_flags;

            if (!properties.contains(required_flags)) continue;
            if (!properties.contains(preferred_flags)) continue;

            index_found = true;
            break;
        }
        if (!index_found) {
            memory_type_index = 0;
            while (memory_type_index < self.memory_type_count) : (memory_type_index += 1) {
                if ((memory_type_bits >> @intCast(u5, memory_type_index)) & 1 == 0) {
                    continue;
                }

                const properties = self.memory_types[memory_type_index].property_flags;
                if (!properties.contains(required_flags)) continue;

                index_found = true;
                break;
            }
        }
        if (!index_found) return error.MemoryTypeIndexNotFound;

        var pool = self.pools[memory_type_index];
        return pool.alloc(size, alignment, usage, alloc_type);
    }

    pub fn free(self: *Self, allocation: Allocation) void {
        self.pools[allocation.memory_type_index].free(allocation);
    }
};

inline fn alignOffset(offset: VkDeviceSize, alignment: VkDeviceSize) VkDeviceSize {
    return ((offset + (alignment - 1)) & ~(alignment - 1));
}
