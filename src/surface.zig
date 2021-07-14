const vk = @import("vk");
const Context = @import("./context.zig");

const Self = @This();

surface: vk.SurfaceKHR,
context: *Context,

pub fn deinit(self: Self) void {
    self.vki.destroySurfaceKHR(self.context.instance, self.surface, null);
}

// Creates a surface for vulkan to draw on
// Currently uses glfw
fn createSurface(self: *Self) !void {
    if (glfw.glfwCreateWindowSurface(self.instance, self.window.window, null, &self.surface) != vk.Result.success) {
        return BackendError.CreateSurfaceFailed;
    }
}

fn checkSurfaceSupport(vki: InstanceDispatch, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}
