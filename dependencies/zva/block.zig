const std = @import("std");
const mem = std.mem;
const Config = @import("allocator.zig").Config;

usingnamespace @cImport({
    @cInclude("vulkan/vulkan.h");
});

const AllocationType = enum {
    Free,
    Buffer,
    Image,
    ImageLinear,
    ImageOptimal,
};

const MemoryUsage = enum {
    GpuOnly,
    CpuOnly,
    CpuToGpu,
    GpuToCpu,
};

pub const FunctionPointers = struct {
    allocateMemory: fn (VkDevice, VkMemoryAllocateInfo, *VkDeviceMemory) !void,
    freeMemory: fn (VkDevice, *VkDeviceMemory) void,
    mapMemory: fn (VkDevice, *VkDeviceMemory, usize, VkDeviceSize, usize, ?*c_void) !void,
    unmapMemory: fn (VkDevice, *VkDeviceMemory) void,
};

const Block = struct {
    const Layout = struct { offset: VkDeviceSize, size: VkDeviceSize, alloc_type: AllocationType, id: usize };

    config: Config,
    device: VkDevice,

    memory: VkDeviceMemory,
    usage: MemoryUsage,
    size: VkDeviceSize,
    allocated: VkDeviceSize,

    data: []align(8) u8,

    layout: std.ArrayList(Layout),
    layout_id: usize,

    pub fn init(allocator: *mem.Allocator, config: Config, device: VkDevice, size: VkDeviceSize, usage: MemoryUsage, memory_type_index: u32) !Block {
        var layout = std.ArrayList(Layout).init(allocator);
        try layout.append(.{ .offset = 0, .size = size, .alloc_type = .Free, .id = 0 });

        const allocation_info = VkMemoryAllocateInfo{
            .allocation_size = size,

            .memory_type_index = memory_type_index,
        };

        var memory: VkDeviceMemory = undefined;
        try config.allocateMemory(device, &allocation_info, null, &memory);

        var data: []align(8) u8 = undefined;
        try config.mapMemory(device, memory, 0, size, 0, @ptrCast(*?*c_void, &data));

        return Block{
            .config = config,
            .device = device,

            .memory = memory,
            .usage = usage,
            .size = size,
            .allocated = 0,

            .data = data,

            .layout = layout,
            .layout_id = 1,
        };
    }

    pub fn deinit(self: Block) void {
        self.layout.deinit();

        if (self.usage != .GpuOnly) {
            self.config.unmapMemory(self.device, self.memory);
        }

        self.config.freeMemory(self.device, self.memory, null);
    }
};
