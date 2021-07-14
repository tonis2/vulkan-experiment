const std = @import("std");
const testing = std.testing;
const panic = std.debug.panic;

const glfw = @import("glfw");
const vk = @import("vk");

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

pub fn init(name: [*c]const u8, size: Size) !void {
    _ = glfw.glfwSetErrorCallback(errorCallback);
    if (glfw.glfwInit() == glfw.GLFW_FALSE) {
        return WindowError.InitFailed;
    }

    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);

    var window = glfw.glfwCreateWindow(@intCast(c_int, size.width), @intCast(c_int, size.height), name, null, null) orelse {
        return WindowError.CreationFailed;
    };

    return Window{
        .window = window,
        .name = name,
        .size = side,
    };
}

pub fn createSurface(instance: vk.Instance, surface: *vk.SurfaceKHR) !void {
    if (glfw.glfwCreateWindowSurface(instance, self.window, null, surface) != vk.Result.success) {
        return error.SurfaceFailed;
    }
}

pub fn getInstanceProcAddress() vk.PfnVoidFunction {
    return glfw.glfwGetInstanceProcAddress;
}

pub fn getRequiredInstanceExtensions(count: *i32) !void {
    glfw.glfwGetRequiredInstanceExtensions(count);
}

pub fn deinit(self: Window) void {
    glfw.glfwDestroyWindow(self.window);
    glfw.glfwTerminate();
}

pub fn isRunning(self: *Window) bool {
    return (glfw.glfwWindowShouldClose(self.window) == glfw.GLFW_FALSE);
}

pub fn update() void {
    glfw.glfwPollEvents();
}

//----- All Backends
fn errorCallback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("{d} \n", .{err});
    panic("Error: {}\n", .{std.mem.span(description)});
}

// //----- Vulkan Specific
// fn vulkanFramebufferSizeCallback(window: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {}
