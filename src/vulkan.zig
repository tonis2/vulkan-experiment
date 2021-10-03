const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const dbg = @import("debug.zig");
const log = std.log;

pub const SwapChain = @import("swapchain.zig");
pub const Window = @import("window.zig");
pub const Buffer = @import("buffer.zig").Buffer;
pub const C = @import("c.zig");
pub const Utils = @import("utils.zig");

const ZVA = @import("zva").Allocator;

usingnamespace C;
usingnamespace Utils;

const Self = @This();

allocator: *Allocator,
vAllocator: ZVA,
instance: VkInstance,
physical_device: VkPhysicalDevice,
device: VkDevice,
graphics_queue: VkQueue,
present_queue: VkQueue,
queue_family_indices: QueueFamilyIndices,
surface: VkSurfaceKHR,
swapchain: SwapChain,
command_pool: VkCommandPool,
commandbuffers: []VkCommandBuffer,
debug_messenger: ?VkDebugUtilsMessengerEXT,
window: Window,

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

    const swapchain = try SwapChain.init(
        allocator,
        physical_device,
        device,
        surface,
        window,
        indices,
    );

    const command_pool = try createCommandPool(device, indices);
    const commandbuffers = try createCommandBuffers(device, command_pool, allocator, swapchain.images.len);

    var deviceMemProperties: VkPhysicalDeviceMemoryProperties = undefined;
    vkGetPhysicalDeviceMemoryProperties(physical_device, &deviceMemProperties);
    var deviceProperties: VkPhysicalDeviceProperties = undefined;

    vkGetPhysicalDeviceProperties(physical_device, &deviceProperties);

    // zig fmt: off
    var zva = try ZVA.init(allocator, .{ 
        .device = device, 
        .physicalDevice = physical_device, 
        .physicalDeviceMemoryProperties = deviceMemProperties,
        .physicalDeviceProperties = deviceProperties,
        .minBlockSize = 128 * 1024 * 1024,

        .allocateMemory = allocateMemory,
        .freeMemory = freeMemory,
        .mapMemory = mapMemory,
        .unmapMemory = unmapMemory
    });
    // zig fmt: on

    return Self{
        .allocator = allocator,
        .vAllocator = zva,
        .instance = instance,
        .physical_device = physical_device,
        .device = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .queue_family_indices = indices,
        .surface = surface,
        .swapchain = swapchain,
        .command_pool = command_pool,
        .commandbuffers = commandbuffers,
        .window = window,
        .debug_messenger = debug_messenger,
    };
}

pub fn deinit(self: Self) void {
    self.swapchain.deinit(self.device);
    self.vAllocator.deinit();

    vkFreeCommandBuffers(
        self.device,
        self.command_pool,
        @intCast(u32, self.commandbuffers.len),
        self.commandbuffers.ptr,
    );
    self.allocator.free(self.commandbuffers);

    vkDestroyCommandPool(self.device, self.command_pool, null);
    vkDestroyDevice(self.device, null);

    if (self.debug_messenger) |messenger| {
        dbg.deinitDebugMessenger(self.instance, messenger);
    }

    vkDestroySurfaceKHR(self.instance, self.surface, null);
    vkDestroyInstance(self.instance, null);
}

pub fn createCommandBuffers(device: VkDevice, commandpool: VkCommandPool, allocator: *Allocator, len: usize) ![]VkCommandBuffer {
    var buffers = try allocator.alloc(VkCommandBuffer, len);
    errdefer allocator.free(buffers);

    try allocateCommandBuffers(device, &VkCommandBufferAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = commandpool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(u32, buffers.len),
    }, buffers.ptr);

    return buffers;
}

pub fn recreateSwapChain(self: *Self) !void {
    try checkSuccess(vkDeviceWaitIdle(self.device), error.WaitingIdleFailed);
    self.swapchain.deinit(self.device);
    self.swapchain = try SwapChain.init(
        self.allocator,
        self.physical_device,
        self.device,
        self.surface,
        self.window,
        self.queue_family_indices,
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

    var swapchain_adequate = false;
    if (extensions_supported) {
        const swapchain_support = try SwapChain.querySwapChainSupport(allocator, device, surface);
        defer swapchain_support.deinit();
        swapchain_adequate = swapchain_support.formats.len != 0 and swapchain_support.present_modes.len != 0;
    }

    return indices.isComplete() and extensions_supported and swapchain_adequate;
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

pub const Synchronization = struct {
    vulkan: *Self,
    allocator: *Allocator,
    image_available_semaphores: []VkSemaphore,
    render_finished_semaphores: []VkSemaphore,
    in_flight_fences: []VkFence,
    images_in_flight: []?VkFence,
    currentFrame: u32 = 0,

    pub fn init(vulkan: *Self, allocator: *Allocator, image_count: usize) !Synchronization {
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
            const semaphore = try createSemaphore(vulkan.device);
            errdefer vkDestroySemaphore(vulkan.device, semaphore);
            image_available_semaphores[i] = semaphore;
        }

        i = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            const semaphore = try createSemaphore(vulkan.device);
            errdefer vkDestroySemaphore(vulkan.device, semaphore);
            render_finished_semaphores[i] = semaphore;
        }

        i = 0;
        while (i < MAX_FRAMES_IN_FLIGHT) : (i += 1) {
            const fence = try createFence(vulkan.device);
            errdefer vkDestroyFence(vulkan.device, fence, null);
            in_flight_fences[i] = fence;
        }

        i = 0;
        while (i < image_count) : (i += 1) {
            images_in_flight[i] = null;
        }

        return Synchronization{
            .vulkan = vulkan,
            .allocator = allocator,
            .image_available_semaphores = image_available_semaphores,
            .render_finished_semaphores = render_finished_semaphores,
            .in_flight_fences = in_flight_fences,
            .images_in_flight = images_in_flight,
        };
    }

    pub fn deinit(self: Synchronization) void {
        const result = vkDeviceWaitIdle(self.vulkan.device);
        if (result != VK_SUCCESS) {
            log.warn("Unable to wait for Vulkan device to be idle before cleanup", .{});
        }

        for (self.render_finished_semaphores) |semaphore| {
            vkDestroySemaphore(self.vulkan.device, semaphore, null);
        }

        self.allocator.free(self.render_finished_semaphores);

        for (self.image_available_semaphores) |semaphore| {
            vkDestroySemaphore(self.vulkan.device, semaphore, null);
        }

        self.allocator.free(self.image_available_semaphores);

        for (self.in_flight_fences) |fence| {
            vkDestroyFence(self.vulkan.device, fence, null);
        }

        self.allocator.free(self.in_flight_fences);
        self.allocator.free(self.images_in_flight);
    }

    pub fn drawFrame(self: *Synchronization, commandBuffers: []VkCommandBuffer) !void {
        try checkSuccess(
            vkWaitForFences(self.vulkan.device, 1, &self.in_flight_fences[self.currentFrame], VK_TRUE, MAX_UINT64),
            error.VulkanWaitForFencesFailure,
        );

        var image_index: u32 = 0;
        {
            const result = vkAcquireNextImageKHR(
                self.vulkan.device,
                self.vulkan.swapchain.swapchain,
                MAX_UINT64,
                self.image_available_semaphores[self.currentFrame],
                null,
                &image_index,
            );
            if (result == VK_ERROR_OUT_OF_DATE_KHR) {
                // swap chain cannot be used (e.g. due to window resize)
                try self.vulkan.recreateSwapChain();
                return;
            } else if (result != VK_SUCCESS and result != VK_SUBOPTIMAL_KHR) {
                return error.VulkanSwapChainAcquireNextImageFailure;
            } else {
                // swap chain may be suboptimal, but we go ahead and render anyways and recreate it later
            }
        }

        // check if a previous frame is using this image (i.e. it has a fence to wait on)
        if (self.images_in_flight[image_index]) |fence| {
            try checkSuccess(
                vkWaitForFences(self.vulkan.device, 1, &fence, VK_TRUE, MAX_UINT64),
                error.VulkanWaitForFenceFailure,
            );
        }
        // mark the image as now being in use by this frame
        self.images_in_flight[image_index] = self.in_flight_fences[self.currentFrame];

        const wait_semaphores = [_]VkSemaphore{self.image_available_semaphores[self.currentFrame]};
        const signal_semaphores = [_]VkSemaphore{self.render_finished_semaphores[self.currentFrame]};
        const wait_stages = [_]VkPipelineStageFlags{VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const submit_info = VkSubmitInfo{
            .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &commandBuffers[image_index],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        };

        try checkSuccess(
            vkResetFences(self.vulkan.device, 1, &self.in_flight_fences[self.currentFrame]),
            error.VulkanResetFencesFailure,
        );

        try queueSubmit(self.vulkan.graphics_queue, 1, &submit_info, self.in_flight_fences[self.currentFrame]);

        const swapchains = [_]VkSwapchainKHR{self.vulkan.swapchain.swapchain};
        const present_info = VkPresentInfoKHR{
            .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &swapchains,
            .pImageIndices = &image_index,
            .pResults = null,
        };

        {
            const result = vkQueuePresentKHR(self.vulkan.present_queue, &present_info);
            if (result == VK_ERROR_OUT_OF_DATE_KHR or result == VK_SUBOPTIMAL_KHR) {
                try self.vulkan.recreateSwapChain();
            } else if (result != VK_SUCCESS) {
                return error.VulkanQueuePresentFailure;
            }
        }

        self.currentFrame = (self.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    }
};

pub const Descriptor = struct {
    layouts: []VkDescriptorSetLayout,
    poolSizes: []VkDescriptorPoolSize,
    sets: []VkDescriptorSet,
    pool: VkDescriptorPool,
    allocator: *Allocator,

    pub fn new(descriptorInfo: VkDescriptorSetLayoutCreateInfo, max_size: usize, device: VkDevice, allocator: *Allocator) !Descriptor {
        var layouts = try allocator.alloc(VkDescriptorSetLayout, max_size);
        var sets = try allocator.alloc(VkDescriptorSet, max_size);
        var poolSizes = try allocator.alloc(VkDescriptorPoolSize, descriptorInfo.bindingCount);
        var pool: VkDescriptorPool = undefined;

        for (poolSizes) |*poolSize, i| {
            poolSize.* = VkDescriptorPoolSize{
                .type = descriptorInfo.pBindings[i].descriptorType,
                .descriptorCount = @intCast(u32, max_size),
            };
        }

        const poolInfo = VkDescriptorPoolCreateInfo{
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = 1,
            .pPoolSizes = poolSizes.ptr,
            .maxSets = @intCast(u32, max_size),
            .pNext = null,
            .flags = 0,
        };

        try checkSuccess(vkCreateDescriptorPool(device, &poolInfo, null, &pool), error.VulkanDescriptorPoolFailed);

        for (layouts) |*layout| {
            try checkSuccess(
                vkCreateDescriptorSetLayout(device, &descriptorInfo, null, layout),
                error.VulkanPipelineLayoutCreationFailed,
            );
        }

        try checkSuccess(vkAllocateDescriptorSets(device, &VkDescriptorSetAllocateInfo{
            .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = pool,
            .descriptorSetCount = @intCast(u32, max_size),
            .pSetLayouts = layouts.ptr,
            .pNext = null,
        }, sets.ptr), error.DescriptorAllocationFailed);

        return Descriptor{
            .poolSizes = poolSizes,
            .pool = pool,
            .layouts = layouts,
            .sets = sets,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Descriptor, device: VkDevice) void {
        for (self.layouts) |layout| {
            vkDestroyDescriptorSetLayout(device, layout, null);
        }

        vkDestroyDescriptorPool(device, self.pool, null);

        self.allocator.free(self.poolSizes);
        self.allocator.free(self.layouts);
        self.allocator.free(self.sets);
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

pub fn allocateCommandBuffers(
    device: VkDevice,
    info: *const VkCommandBufferAllocateInfo,
    buffers: [*c]VkCommandBuffer,
) !void {
    try checkSuccess(
        vkAllocateCommandBuffers(device, @ptrCast([*c]const VkCommandBufferAllocateInfo, info), buffers),
        error.VulkanCommanbBufferAllocationFailure,
    );
}

pub fn beginCommandBuffer(buffer: VkCommandBuffer, info: *const VkCommandBufferBeginInfo) !void {
    try checkSuccess(vkBeginCommandBuffer(buffer, @ptrCast([*c]const VkCommandBufferBeginInfo, info)), error.VulkanBeginCommandBufferFailure);
}

pub fn endCommandBuffer(buffer: VkCommandBuffer) !void {
    try checkSuccess(vkEndCommandBuffer(buffer), error.VulkanCommandBufferEndFailure);
}

pub fn allocateMemory(device: VkDevice, allocation: VkMemoryAllocateInfo, memory: *VkDeviceMemory) anyerror!void {
    try checkSuccess(vkAllocateMemory(device, &allocation, null, memory), error.VulkanAllocateMemoryFailure);
}

pub fn mapMemory(device: VkDevice, memory: VkDeviceMemory, offset: usize, size: VkDeviceSize, flags: VkMemoryMapFlags, data: *?*c_void) anyerror!void {
    try checkSuccess(vkMapMemory(device, memory, offset, size, flags, data), error.VulkanMapMemoryError);
}

pub fn freeMemory(device: VkDevice, memory: VkDeviceMemory) void {
    vkFreeMemory(device, memory, null);
}

pub fn unmapMemory(device: VkDevice, memory: VkDeviceMemory) void {
    vkUnmapMemory(device, memory);
}
