const std = @import("std");
const vk = @import("vk");

pub const IN_FLIGHT_FRAMES = 2;

pub const BackendError = error{ NoValidDevices, ValidationLayersNotAvailable, CreateSurfaceFailed, AcquireImageFailed, PresentFailed, InvalidShader, UnknownResourceType };

pub const app_name = "vulkan-zig triangle example";

pub const enableValidationLayers = std.debug.runtime_safety;
pub const validationLayers = [_][*:0]const u8{"VK_LAYER_LUNARG_standard_validation"};
pub const deviceExtensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};
