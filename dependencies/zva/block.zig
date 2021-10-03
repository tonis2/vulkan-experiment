const std = @import("std");
const mem = std.mem;

usingnamespace @import("allocator.zig");
usingnamespace @import("cImports");

pub const Block = struct {
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
            .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .pNext = null,
            .allocationSize = size,
            .memoryTypeIndex = memory_type_index,
        };

        var memory: VkDeviceMemory = undefined;
        try config.allocateMemory(device, allocation_info, &memory);

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

        self.config.freeMemory(self.device, self.memory);
    }
};
