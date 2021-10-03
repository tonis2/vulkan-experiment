const std = @import("std");
const mem = std.mem;
const Block = @import("block.zig").Block;

usingnamespace @import("allocator.zig");
usingnamespace @import("cImports");

pub const Pool = struct {
    config: Config,

    allocator: *mem.Allocator,
    device: VkDevice,

    image_granularity: VkDeviceSize,
    min_block_size: VkDeviceSize,
    memory_type_index: u32,

    blocks: std.ArrayList(?Block),

    pub fn init(allocator: *mem.Allocator, config: Config, memory_type_index: u32) Pool {
        return Pool{
            .allocator = allocator,

            .config = config,
            .device = config.device,

            .image_granularity = config.physicalDeviceProperties.limits.bufferImageGranularity,
            .min_block_size = config.minBlockSize,
            .memory_type_index = memory_type_index,

            .blocks = std.ArrayList(?Block).init(allocator),
        };
    }

    pub fn deinit(self: Pool) void {
        for (self.blocks.items) |b| {
            if (b) |block| block.deinit();
        }
        self.blocks.deinit();
    }

    pub fn alloc(self: *Pool, size: VkDeviceSize, alignment: VkDeviceSize, usage: MemoryUsage, alloc_type: AllocationType) !Allocation {
        var found = false;
        var location: struct { bid: usize, sid: usize, offset: VkDeviceSize, size: VkDeviceSize } = undefined;
        outer: for (self.blocks.items) |b, i| if (b) |block| {
            if (block.usage == .GpuOnly and usage != .GpuOnly) continue;
            const block_free = block.size - block.allocated;

            var offset: VkDeviceSize = 0;
            var aligned_size: VkDeviceSize = 0;

            for (block.layout.items) |span, j| {
                if (span.alloc_type != .Free) continue;
                if (span.size < size) continue;

                offset = alignOffset(span.offset, alignment);

                if (j >= 1 and self.image_granularity > 1) {
                    const prev = block.layout.items[j - 1];
                    if ((prev.offset + prev.size - 1) & ~(self.image_granularity - 1) == offset & ~(self.image_granularity - 1)) {
                        const atype = if (@enumToInt(prev.alloc_type) > @enumToInt(alloc_type)) prev.alloc_type else alloc_type;

                        switch (atype) {
                            .Buffer => {
                                if (alloc_type == .Image or alloc_type == .ImageOptimal) offset = alignOffset(offset, self.image_granularity);
                            },
                            .Image => {
                                if (alloc_type == .Image or alloc_type == .ImageLinear or alloc_type == .ImageOptimal) offset = alignOffset(offset, self.image_granularity);
                            },
                            .ImageLinear => {
                                if (alloc_type == .ImageOptimal) offset = alignOffset(offset, self.image_granularity);
                            },
                            else => {},
                        }
                    }
                }

                var padding = offset - span.offset;
                aligned_size = padding + size;

                if (aligned_size > span.size) continue;
                if (aligned_size > block_free) continue :outer;

                if (j + 1 < block.layout.items.len and self.image_granularity > 1) {
                    const next = block.layout.items[j + 1];
                    if ((next.offset + next.size - 1) & ~(self.image_granularity - 1) == offset & ~(self.image_granularity - 1)) {
                        const atype = if (@enumToInt(next.alloc_type) > @enumToInt(alloc_type)) next.alloc_type else alloc_type;

                        switch (atype) {
                            .Buffer => if (alloc_type == .Image or alloc_type == .ImageOptimal) continue,
                            .Image => if (alloc_type == .Image or alloc_type == .ImageLinear or alloc_type == .ImageOptimal) continue,
                            .ImageLinear => if (alloc_type == .ImageOptimal) continue,
                            else => {},
                        }
                    }
                }

                found = true;
                location = .{ .bid = i, .sid = j, .offset = offset, .size = aligned_size };
                break :outer;
            }
        };

        if (!found) {
            var block_size: usize = 0;
            while (block_size < size) {
                block_size += self.min_block_size;
            }

            try self.blocks.append(try Block.init(self.allocator, self.config, self.device, block_size, usage, self.memory_type_index));

            location = .{ .bid = self.blocks.items.len - 1, .sid = 0, .offset = 0, .size = size };
        }

        const allocation = Allocation{
            .block_id = location.bid,
            .span_id = self.blocks.items[location.bid].?.layout.items[location.sid].id,
            .memory_type_index = self.memory_type_index,

            .memory = self.blocks.items[location.bid].?.memory,

            .offset = location.offset,
            .size = location.size,

            .data = if (usage != .GpuOnly) self.blocks.items[location.bid].?.data[location.offset .. location.offset + size] else undefined,
        };

        var block = self.blocks.items[location.bid].?;

        try block.layout.append(.{ .offset = block.layout.items[location.sid].offset + location.size, .size = block.layout.items[location.sid].size - location.size, .alloc_type = .Free, .id = block.layout_id });
        block.layout.items[location.sid].size = location.size;
        block.layout.items[location.sid].alloc_type = alloc_type;
        block.allocated += location.size;
        block.layout_id += 1;

        return allocation;
    }

    pub fn free(self: *Pool, allocation: Allocation) void {
        var block = self.blocks.items[allocation.block_id];
        for (block.?.layout.items) |*layout| {
            if (layout.id == allocation.span_id) {
                layout.alloc_type = .Free;
                break;
            }
        }
    }
};
inline fn alignOffset(offset: VkDeviceSize, alignment: VkDeviceSize) VkDeviceSize {
    return ((offset + (alignment - 1)) & ~(alignment - 1));
}
