const std = @import("std");
const mem = std.mem;
const Pool = @import("pool.zig").Pool;

usingnamespace @import("cImports");

pub const Config = struct {
    device: VkDevice,
    physicalDeviceProperties: VkPhysicalDeviceProperties,
    physicalDeviceMemoryProperties: VkPhysicalDeviceMemoryProperties,
    minBlockSize: VkDeviceSize,
    physicalDevice: VkPhysicalDevice,

    allocateMemory: fn (VkDevice, VkMemoryAllocateInfo, *VkDeviceMemory) anyerror!void,
    mapMemory: fn (VkDevice, VkDeviceMemory, usize, VkDeviceSize, VkMemoryMapFlags, *?*c_void) anyerror!void,
    unmapMemory: fn (VkDevice, VkDeviceMemory) void,
    freeMemory: fn (VkDevice, VkDeviceMemory) void,
};

pub const AllocationType = enum {
    Free,
    Buffer,
    Image,
    ImageLinear,
    ImageOptimal,
};

pub const MemoryUsage = enum {
    GpuOnly,
    CpuOnly,
    CpuToGpu,
    GpuToCpu,
};

pub const Allocation = struct {
    block_id: VkDeviceSize,
    span_id: VkDeviceSize,
    memory_type_index: u32,

    memory: VkDeviceMemory,

    offset: VkDeviceSize,
    size: VkDeviceSize,

    data: []align(8) u8,
};

pub const Allocator = struct {
    const Self = @This();
    allocator: *mem.Allocator,

    config: Config,

    memory_types: [VK_MAX_MEMORY_TYPES]VkMemoryType,
    memory_type_count: u32,

    pools: []Pool,

    pub fn init(allocator: *mem.Allocator, config: Config) !Self {
        var pools = try allocator.alloc(Pool, config.physicalDeviceMemoryProperties.memoryTypeCount);

        for (pools) |*pool, i| pool.* = Pool.init(allocator, config, @intCast(u32, i));

        return Self{
            .allocator = allocator,
            .config = config,

            .memory_types = config.physicalDeviceMemoryProperties.memoryTypes,
            .memory_type_count = config.physicalDeviceMemoryProperties.memoryTypeCount,

            .pools = pools,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.pools) |pool| pool.deinit();
        self.allocator.free(self.pools);
    }

    pub fn alloc(self: Self, size: VkDeviceSize, alignment: VkDeviceSize, memoryTypeIndex: u32, usage: MemoryUsage, alloc_type: AllocationType) !Allocation {
        return self.pools[memoryTypeIndex].alloc(size, alignment, usage, alloc_type);
    }

    pub fn free(self: Self, allocation: Allocation) void {
        self.pools[allocation.memory_type_index].free(allocation);
    }
};
