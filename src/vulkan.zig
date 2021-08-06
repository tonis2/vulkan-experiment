const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const dbg = @import("debug.zig");
const Pipeline = @import("pipeline.zig");
const SwapChain = @import("swapchain.zig");
const Window = @import("window.zig");
const log = std.log;

usingnamespace @import("c.zig");
usingnamespace @import("utils.zig");
usingnamespace @import("buffer.zig");


 // Couldn't use UINT64_MAX for some reason

const enable_validation_layers = std.debug.runtime_safety;

const device_extensions = [_][*:0]const u8{
    VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

const Self = @This();

allocator: *Allocator,
instance: VkInstance,
physical_device: VkPhysicalDevice,
device: VkDevice,
graphics_queue: VkQueue,
present_queue: VkQueue,
queue_family_indices: QueueFamilyIndices,
surface: VkSurfaceKHR,
swap_chain: SwapChain,
render_pass: VkRenderPass,
swap_chain_framebuffers: []VkFramebuffer,
command_pool: VkCommandPool,
sync: VulkanSynchronization,
debug_messenger: ?VkDebugUtilsMessengerEXT,

// TODO: use errdefer to clean up stuff in case of errors
pub fn init(allocator: *Allocator, window: Window) !Self {
    if (enable_validation_layers) {
        if (!try dbg.checkValidationLayerSupport(allocator)) {
            return error.ValidationLayerRequestedButNotAvailable;
        }
    }

    const app_info = VkApplicationInfo{
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Hello Triangle",
        .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = VK_API_VERSION_1_0,
    };

    const extensions = try getRequiredExtensions(allocator);
    defer allocator.free(extensions);

    var create_info = VkInstanceCreateInfo{
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = @intCast(u32, extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
    };

    // placed outside scope to ensure it's not destroyed before the call to vkCreateInstance
    var debug_create_info: VkDebugUtilsMessengerCreateInfoEXT = undefined;
    if (enable_validation_layers) {
        debug_create_info = dbg.createDebugMessengerCreateInfo();
        dbg.fillDebugMessengerInInstanceCreateInfo(&create_info, &debug_create_info);
    }

    var instance: VkInstance = undefined;
    const result = vkCreateInstance(&create_info, null, &instance);
    if (result != VK_SUCCESS) {
        return error.VulkanInitializationFailed;
    }

    var debug_messenger: VkDebugUtilsMessengerEXT = null;
    if (enable_validation_layers) {
        debug_messenger = try dbg.initDebugMessenger(instance);
    }

    const surface = try window.createSurface(instance);

    const physical_device = try pickPhysicalDevice(allocator, instance, surface);
    const indices = try findQueueFamilies(allocator, physical_device, surface);
    if (!indices.isComplete()) {
        return error.VulkanSuitableQueuFamiliesNotFound;
    }

    const device = try createLogicalDevice(allocator, physical_device, indices);

    var graphics_queue: VkQueue = undefined;
    vkGetDeviceQueue(
        device,
        indices.graphics_family.?,
        0,
        &graphics_queue,
    );

    var present_queue: VkQueue = undefined;
    vkGetDeviceQueue(
        device,
        indices.present_family.?,
        0,
        &present_queue,
    );

    const swap_chain = try SwapChain.init(
        allocator,
        physical_device,
        device,
        window,
        surface,
        indices,
    );

    const render_pass = try createRenderPass(device, swap_chain.image_format, swap_chain.extent);
    const swap_chain_framebuffers = try createFramebuffers(allocator, device, render_pass, swap_chain);
    const command_pool = try createCommandPool(device, indices);

    var sync = try VulkanSynchronization.init(allocator, device, swap_chain.images.len);
    errdefer sync.deinit(device);

    return Self{
        .allocator = allocator,
        .instance = instance,
        .physical_device = physical_device,
        .device = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .queue_family_indices = indices,
        .surface = surface,
        .swap_chain = swap_chain,
        .render_pass = render_pass,
        .swap_chain_framebuffers = swap_chain_framebuffers,
        .command_pool = command_pool,
        .sync = sync,
        .debug_messenger = debug_messenger,
    };
}

pub fn deinit(self: Self) void {
    const result = vkDeviceWaitIdle(self.device);
    if (result != VK_SUCCESS) {
        log.warn("Unable to wait for Vulkan device to be idle before cleanup", .{});
    }

    self.cleanUpSwapChain();

    self.sync.deinit(self.device);

    vkDestroyCommandPool(self.device, self.command_pool, null);
    vkDestroyDevice(self.device, null);
    if (self.debug_messenger) |messenger| {
        dbg.deinitDebugMessenger(self.instance, messenger);
    }
    vkDestroySurfaceKHR(self.instance, self.surface, null);
    vkDestroyInstance(self.instance, null);
}

fn cleanUpSwapChain(self: Self) void {
    for (self.swap_chain_framebuffers) |framebuffer| {
        vkDestroyFramebuffer(self.device, framebuffer, null);
    }
    self.allocator.free(self.swap_chain_framebuffers);

    vkDestroyRenderPass(self.device, self.render_pass, null);
    self.swap_chain.deinit(self.device);
}

const VulkanSynchronization = struct {
    allocator: *Allocator,
    image_available_semaphores: []VkSemaphore,
    render_finished_semaphores: []VkSemaphore,
    in_flight_fences: []VkFence,
    images_in_flight: []?VkFence,

    fn init(allocator: *Allocator, device: VkDevice, image_count: usize) !VulkanSynchronization {
        var image_available_semaphores = try allocator.alloc(VkSemaphore, MAX_FRAMES_IN_FLIGHT);
        errdefer allocator.free(image_available_semaphores);

        var render_finished_semaphores = try allocator.alloc(VkSemaphore, MAX_FRAMES_IN_FLIGHT);
        errdefer allocator.free(render_finished_semaphores);

        var in_flight_fences = try allocator.alloc(VkFence, MAX_FRAMES_IN_FLIGHT);
        errdefer allocator.free(in_flight_fences);

        var images_in_flight = try allocator.alloc(?VkFence, image_count);
        errdefer allocator.free(images_in_flight);

        var i: usize = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            const semaphore = try createSemaphore(device);
            errdefer vkDestroySemaphore(device, semaphore);
            image_available_semaphores[i] = semaphore;
        }

        i = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            const semaphore = try createSemaphore(device);
            errdefer vkDestroySemaphore(device, semaphore);
            render_finished_semaphores[i] = semaphore;
        }

        i = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            const fence = try createFence(device);
            errdefer vkDestroyFence(device, fence, null);
            in_flight_fences[i] = fence;
        }

        i = 0;
        while (i < image_count) : (i += 1) {
            images_in_flight[i] = null;
        }

        return VulkanSynchronization{
            .allocator = allocator,
            .image_available_semaphores = image_available_semaphores,
            .render_finished_semaphores = render_finished_semaphores,
            .in_flight_fences = in_flight_fences,
            .images_in_flight = images_in_flight,
        };
    }

    fn deinit(self: VulkanSynchronization, device: VkDevice) void {
        for (self.render_finished_semaphores) |semaphore| {
            vkDestroySemaphore(device, semaphore, null);
        }
        self.allocator.free(self.render_finished_semaphores);

        for (self.image_available_semaphores) |semaphore| {
            vkDestroySemaphore(device, semaphore, null);
        }
        self.allocator.free(self.image_available_semaphores);

        for (self.in_flight_fences) |fence| {
            vkDestroyFence(device, fence, null);
        }
        self.allocator.free(self.in_flight_fences);

        self.allocator.free(self.images_in_flight);
    }
};

pub fn queueSubmit(queue: VkQueue, submit_count: u32, submit_info: *const VkSubmitInfo, fence: ?VkFence) !void {
    try checkSuccess(
        vkQueueSubmit(queue, submit_count, submit_info, fence orelse null),
        error.VulkanQueueSubmitFailure,
    );
}

pub fn queueWaitIdle(queue: VkQueue) !void {
    try checkSuccess(vkQueueWaitIdle(queue), error.VulkanQueueWaitIdleFailure);
}

pub fn beginCommandBuffer(buffer: VkCommandBuffer, info: *const VkCommandBufferBeginInfo) !void {
    try checkSuccess(vkBeginCommandBuffer(buffer, info), error.VulkanBeginCommandBufferFailure);
}

pub fn endCommandBuffer(buffer: VkCommandBuffer) !void {
    try checkSuccess(vkEndCommandBuffer(buffer), error.VulkanCommandBufferEndFailure);
}

pub fn allocateCommandBuffers(
    device: VkDevice,
    info: *const VkCommandBufferAllocateInfo,
    buffers: [*c]VkCommandBuffer,
) !void {
    try checkSuccess(
        vkAllocateCommandBuffers(device, info, buffers),
        error.VulkanCommanbBufferAllocationFailure,
    );
}

/// caller must free returned memory
fn getRequiredExtensions(allocator: *Allocator) ![][*:0]const u8 {
    var extensions = try Window.getWindowRequiredExtensions(allocator);
    if (enable_validation_layers) {
        try extensions.append(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    }
    return extensions.toOwnedSlice();
}

fn pickPhysicalDevice(
    allocator: *Allocator,
    instance: VkInstance,
    surface: VkSurfaceKHR,
) !VkPhysicalDevice {
    var device_count: u32 = 0;
    try checkSuccess(
        vkEnumeratePhysicalDevices(instance, &device_count, null),
        error.VulkanPhysicalDeviceEnumerationFailed,
    );

    if (device_count == 0) {
        return error.VulkanFailedToFindSupportedGPU;
    }

    const devices = try allocator.alloc(VkPhysicalDevice, device_count);
    defer allocator.free(devices);
    try checkSuccess(
        vkEnumeratePhysicalDevices(instance, &device_count, devices.ptr),
        error.VulkanPhysicalDeviceEnumerationFailed,
    );

    const physical_device = for (devices) |device| {
        if (try isDeviceSuitable(allocator, device, surface)) {
            break device;
        }
    } else return error.VulkanFailedToFindSuitableGPU;

    return physical_device;
}

fn isDeviceSuitable(allocator: *Allocator, device: VkPhysicalDevice, surface: VkSurfaceKHR) !bool {
    const indices = try findQueueFamilies(allocator, device, surface);
    const extensions_supported = try checkDeviceExtensionSupport(allocator, device);

    var swap_chain_adequate = false;
    if (extensions_supported) {
        const swap_chain_support = try SwapChain.querySwapChainSupport(allocator, device, surface);
        defer swap_chain_support.deinit();
        swap_chain_adequate = swap_chain_support.formats.len != 0 and swap_chain_support.present_modes.len != 0;
    }

    return indices.isComplete() and extensions_supported and swap_chain_adequate;
}

fn checkDeviceExtensionSupport(allocator: *Allocator, device: VkPhysicalDevice) !bool {
    var count: u32 = 0;
    _ = try checkSuccess(vkEnumerateDeviceExtensionProperties(device, null, &count, null), error.NotCorrecteExtensions);

    const availableExtensions = try allocator.alloc(VkExtensionProperties, count);
    defer allocator.free(availableExtensions);

    _ = try checkSuccess(vkEnumerateDeviceExtensionProperties(device, null, &count, availableExtensions.ptr), error.NotCorrecteExtensions);

    for (device_extensions) |deviceExt| {
        for (availableExtensions) |extension| {
            if (std.cstr.cmp(deviceExt, @ptrCast([*c]const u8, &extension.extensionName)) == 0) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

fn createLogicalDevice(
    allocator: *Allocator,
    physical_device: VkPhysicalDevice,
    indices: QueueFamilyIndices,
) !VkDevice {
    const all_queue_families = [_]u32{ indices.graphics_family.?, indices.present_family.? };
    const unique_queue_families = if (indices.graphics_family.? == indices.present_family.?)
        all_queue_families[0..1]
    else
        all_queue_families[0..2];

    var queue_create_infos = ArrayList(VkDeviceQueueCreateInfo).init(allocator);
    defer queue_create_infos.deinit();

    var queue_priority: f32 = 1.0;
    for (unique_queue_families) |queue_family| {
        const queue_create_info = VkDeviceQueueCreateInfo{
            .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = queue_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        try queue_create_infos.append(queue_create_info);
    }

    const device_features = VkPhysicalDeviceFeatures{
        .robustBufferAccess = 0,
        .fullDrawIndexUint32 = 0,
        .imageCubeArray = 0,
        .independentBlend = 0,
        .geometryShader = 0,
        .tessellationShader = 0,
        .sampleRateShading = 0,
        .dualSrcBlend = 0,
        .logicOp = 0,
        .multiDrawIndirect = 0,
        .drawIndirectFirstInstance = 0,
        .depthClamp = 0,
        .depthBiasClamp = 0,
        .fillModeNonSolid = 0,
        .depthBounds = 0,
        .wideLines = 0,
        .largePoints = 0,
        .alphaToOne = 0,
        .multiViewport = 0,
        .samplerAnisotropy = 0,
        .textureCompressionETC2 = 0,
        .textureCompressionASTC_LDR = 0,
        .textureCompressionBC = 0,
        .occlusionQueryPrecise = 0,
        .pipelineStatisticsQuery = 0,
        .vertexPipelineStoresAndAtomics = 0,
        .fragmentStoresAndAtomics = 0,
        .shaderTessellationAndGeometryPointSize = 0,
        .shaderImageGatherExtended = 0,
        .shaderStorageImageExtendedFormats = 0,
        .shaderStorageImageMultisample = 0,
        .shaderStorageImageReadWithoutFormat = 0,
        .shaderStorageImageWriteWithoutFormat = 0,
        .shaderUniformBufferArrayDynamicIndexing = 0,
        .shaderSampledImageArrayDynamicIndexing = 0,
        .shaderStorageBufferArrayDynamicIndexing = 0,
        .shaderStorageImageArrayDynamicIndexing = 0,
        .shaderClipDistance = 0,
        .shaderCullDistance = 0,
        .shaderFloat64 = 0,
        .shaderInt64 = 0,
        .shaderInt16 = 0,
        .shaderResourceResidency = 0,
        .shaderResourceMinLod = 0,
        .sparseBinding = 0,
        .sparseResidencyBuffer = 0,
        .sparseResidencyImage2D = 0,
        .sparseResidencyImage3D = 0,
        .sparseResidency2Samples = 0,
        .sparseResidency4Samples = 0,
        .sparseResidency8Samples = 0,
        .sparseResidency16Samples = 0,
        .sparseResidencyAliased = 0,
        .variableMultisampleRate = 0,
        .inheritedQueries = 0,
    };
    var create_info = VkDeviceCreateInfo{
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .queueCreateInfoCount = @intCast(u32, queue_create_infos.items.len),
        .pEnabledFeatures = &device_features,
        .ppEnabledExtensionNames = &device_extensions,
        .enabledExtensionCount = @intCast(u32, device_extensions.len),
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
    };

    if (enable_validation_layers) {
        dbg.fillDebugMessengerInDeviceCreateInfo(&create_info);
    }

    var device: VkDevice = undefined;

    try checkSuccess(
        vkCreateDevice(physical_device, &create_info, null, &device),
        error.VulkanLogicalDeviceCreationFailed,
    );

    return device;
}

pub fn createShaderModule(device: VkDevice, code: []align(@alignOf(u32)) const u8) !VkShaderModule {
    const create_info = VkShaderModuleCreateInfo{
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = code.len,
        .pCode = std.mem.bytesAsSlice(u32, code).ptr,
    };

    var shader_module: VkShaderModule = undefined;
    try checkSuccess(
        vkCreateShaderModule(device, &create_info, null, &shader_module),
        error.VulkanShaderCreationFailed,
    );

    return shader_module;
}

fn createRenderPass(
    device: VkDevice,
    swap_chain_image_format: VkFormat,
    swap_chain_extent: VkExtent2D,
) !VkRenderPass {
    _ = swap_chain_extent;

    const color_attachment = VkAttachmentDescription{
        .flags = 0,
        .format = swap_chain_image_format,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = VkAttachmentReference{
        .attachment = 0,
        .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass = VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    const dependency = VkSubpassDependency{
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    var render_pass: VkRenderPass = undefined;
    const render_pass_info = VkRenderPassCreateInfo{
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &color_attachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency,
    };
    try checkSuccess(
        vkCreateRenderPass(device, &render_pass_info, null, &render_pass),
        error.VulkanRenderPassCreationFailed,
    );

    return render_pass;
}

fn createFramebuffers(
    allocator: *Allocator,
    device: VkDevice,
    render_pass: VkRenderPass,
    swap_chain: SwapChain,
) ![]VkFramebuffer {
    var framebuffers = try allocator.alloc(VkFramebuffer, swap_chain.image_views.len);
    errdefer allocator.free(framebuffers);

    for (swap_chain.image_views) |image_view, i| {
        var attachments = [_]VkImageView{image_view};
        const frame_buffer_info = VkFramebufferCreateInfo{
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = swap_chain.extent.width,
            .height = swap_chain.extent.height,
            .layers = 1,
        };

        try checkSuccess(
            vkCreateFramebuffer(device, &frame_buffer_info, null, &framebuffers[i]),
            error.VulkanFramebufferCreationFailed,
        );
    }

    return framebuffers;
}

fn createCommandPool(device: VkDevice, indices: QueueFamilyIndices) !VkCommandPool {
    const pool_info = VkCommandPoolCreateInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = indices.graphics_family.?,
    };

    var command_pool: VkCommandPool = undefined;
    try checkSuccess(
        vkCreateCommandPool(device, &pool_info, null, &command_pool),
        error.VulkanCommandPoolCreationFailure,
    );

    return command_pool;
}

fn createSemaphore(device: VkDevice) !VkSemaphore {
    var semaphore: VkSemaphore = undefined;
    const semaphore_info = VkSemaphoreCreateInfo{
        .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };
    try checkSuccess(
        vkCreateSemaphore(device, &semaphore_info, null, &semaphore),
        error.VulkanSemaphoreCreationFailure,
    );

    return semaphore;
}

fn createFence(device: VkDevice) !VkFence {
    var fence: VkFence = undefined;
    const info = VkFenceCreateInfo{
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = VK_FENCE_CREATE_SIGNALED_BIT,
    };

    try checkSuccess(vkCreateFence(device, &info, null, &fence), error.VulkanFenceCreationFailed);

    return fence;
}

pub const QueueFamilyIndices = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    pub fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

pub fn findQueueFamilies(allocator: *Allocator, device: VkPhysicalDevice, surface: VkSurfaceKHR) !QueueFamilyIndices {
    var indices = QueueFamilyIndices{ .graphics_family = null, .present_family = null };

    var queue_family_count: u32 = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, null);

    const queue_families = try allocator.alloc(VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);
    vkGetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, queue_families.ptr);

    // OPTIMIZE: use queue that supports all features if one is available
    var i: u32 = 0;
    for (queue_families) |family| {
        if (family.queueFlags & @intCast(u32, VK_QUEUE_GRAPHICS_BIT) != 0) {
            indices.graphics_family = @intCast(u32, i);
        }

        var present_support: VkBool32 = VK_FALSE;
        try checkSuccess(
            vkGetPhysicalDeviceSurfaceSupportKHR(device, i, surface, &present_support),
            error.VulkanPresentSupportCheckFailed,
        );
        if (present_support == VK_TRUE) {
            indices.present_family = @intCast(u32, i);
        }

        if (indices.isComplete()) {
            break;
        }
        i += 1;
    }

    return indices;
}
