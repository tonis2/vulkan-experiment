const std = @import("std");

usingnamespace @import("c.zig");

pub const MAX_FRAMES_IN_FLIGHT = 2;
pub const Size = struct { width: u32, height: u32 };
pub const MAX_UINT64 = @as(c_ulong, 18446744073709551615);

pub fn checkSuccess(result: VkResult, comptime E: anytype) @TypeOf(E)!void {
    switch (result) {
        VK_SUCCESS => {},
        else => return E,
    }
}
