const std = @import("std");

const glfw = @import("glfw");
const vk = @import("vk");

const Self = @This();

pub const WindowError = error{
    InitFailed,
    CreationFailed,
};

pub const Size = struct {
    width: u32,
    height: u32,
};

window: *glfw.GLFWwindow,
name: [*c]const u8,
size: Size,

pub fn init(name: [*c]const u8, size: Size) !Self {
    _ = glfw.glfwSetErrorCallback(errorCallback);

    if (glfw.glfwInit() == glfw.GLFW_FALSE) {
        return WindowError.InitFailed;
    }

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);

    var window = glfw.glfwCreateWindow(
        @intCast(c_int, size.width),
        @intCast(c_int, size.height),
        name,
        null,
        null,
    ) orelse return error.WindowInitFailed;

    return Self{
        .window = window,
        .name = name,
        .size = size,
    };
}

pub fn createSurface(self: Self, instance: vk.Instance) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfw.glfwCreateWindowSurface(instance, self.window, null, &surface) != .success) {
        return WindowError.CreationFailed;
    }

    return surface;
}

// pub fn getInstanceProcAddress(self: Self) vk.PfnVoidFunction {
//     _ = self;
//     return glfw.glfwGetInstanceProcAddress();
// }

// pub fn getRequiredInstanceExtensions(count: *i32) !void {
//     glfw.glfwGetRequiredInstanceExtensions(count);
// }

pub fn deinit(self: Self) void {
    glfw.glfwDestroyWindow(self.window);
    glfw.glfwTerminate();
}

pub fn isRunning(self: Self) bool {
    return (glfw.glfwWindowShouldClose(self.window) == glfw.GLFW_FALSE);
}

pub fn update() void {
    glfw.glfwPollEvents();
}

//----- All Backends
fn errorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("{d} \n", .{err});
    std.debug.panic("Error: {s} \n", .{std.mem.span(description)});
}

// //----- Vulkan Specific
// fn vulkanFramebufferSizeCallback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {}
