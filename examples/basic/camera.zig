const std = @import("std");
const math = std.math;

usingnamespace @import("zalgebra");
const Self = @This();

const OPENGL_VULKAN_MATRIX = Mat4.fromSlice(&[_]f32{
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    -1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.5,
    0.0,
    0.0,
    0.0,
    0.5,
    1.0,
});

projection: Mat4,
view: Mat4,

pub fn new(width: f32, height: f32, maxZoom: f32) Self {
    var projection = OPENGL_VULKAN_MATRIX.mult(Mat4.fromSlice(&[_]f32{
        2 / width, 0,           0,           0,
        0,         -2 / height, 0,           0,
        0,         0,           2 / maxZoom, 0,
        -1,        1,           0,           1,
    }));
    return Self{ .projection = projection, .view = Mat4.identity() };
}

pub fn translate(self: *Self, location: Vec3) void {
    self.view = self.view.translate(location);
}

pub fn scale(self: *Self, size: Vec3) void {
    self.view = self.view.scale(size);
}

pub fn rotate(self: *Self, degrees: f32, location: Vec3) void {
    self.view = self.view.rotate(degrees, location);
}
