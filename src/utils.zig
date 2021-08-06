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

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) Vec2 {
        return Vec2{
            .x = x,
            .y = y,
        };
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
};

pub const Vertex = struct {
    pos: Vec2,
    color: Vec3,

    pub fn getBindingDescription() VkVertexInputBindingDescription {
        return VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn getAttributeDescriptions() [2]VkVertexInputAttributeDescription {
        return [2]VkVertexInputAttributeDescription{
            VkVertexInputAttributeDescription{
                .binding = 0,
                .location = 0,
                .format = VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "pos"),
            },
            VkVertexInputAttributeDescription{
                .binding = 0,
                .location = 1,
                .format = VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    }
};
