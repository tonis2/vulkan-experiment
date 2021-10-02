const std = @import("std");

usingnamespace @import("c.zig");

pub const MAX_FRAMES_IN_FLIGHT = 2;
pub const Size = struct { width: u32, height: u32 };
pub const MAX_UINT64 = @as(c_ulong, 18446744073709551615);

pub const enable_validation_layers = std.debug.runtime_safety;
pub const device_extensions = [_][*:0]const u8{
    VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

pub fn checkSuccess(result: VkResult, comptime E: anytype) @TypeOf(E)!void {
    switch (result) {
        VK_SUCCESS => {},
        else => return E,
    }
}
