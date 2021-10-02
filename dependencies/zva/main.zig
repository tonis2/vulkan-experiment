// Vulkan allocator, code taken from https://github.com/zetaframe/zva, thanks zetaframe

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
pub const Block = @import("block.zig").Block;

usingnamespace @cImport({
    @cInclude("vulkan/vulkan.h");
});


