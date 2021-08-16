const Self = @This();
const Vulkan = @import("vulkan");

const Context = Vulkan.Context;
usingnamespace Vulkan.C;
usingnamespace Vulkan.Utils;

framebuffers: []VkFramebuffer,
renderpass: VkRenderPass,

pub fn init(ctx: Context) !Self {
    const color_attachment = VkAttachmentDescription{
        .flags = 0,
        .format = ctx.vulkan.swapchain.image_format,
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

    var renderpass: VkRenderPass = undefined;
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
        vkCreateRenderPass(ctx.vulkan.device, &render_pass_info, null, &renderpass),
        error.VulkanRenderPassCreationFailed,
    );

    var framebuffers = try ctx.allocator.alloc(VkFramebuffer, ctx.vulkan.swapchain.image_views.len);
    errdefer ctx.allocator.free(framebuffers);

    for (ctx.vulkan.swapchain.image_views) |image_view, i| {
        var attachments = [_]VkImageView{image_view};
        const frame_buffer_info = VkFramebufferCreateInfo{
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = renderpass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = ctx.vulkan.swapchain.extent.width,
            .height = ctx.vulkan.swapchain.extent.height,
            .layers = 1,
        };

        try checkSuccess(
            vkCreateFramebuffer(ctx.vulkan.device, &frame_buffer_info, null, &framebuffers[i]),
            error.VulkanFramebufferCreationFailed,
        );
    }

    return Self{
        .framebuffers = framebuffers,
        .renderpass = renderpass,
    };
}

pub fn deinit(self: Self, ctx: Context) void {
    for (self.framebuffers) |framebuffer| {
        vkDestroyFramebuffer(ctx.vulkan.device, framebuffer, null);
    }

    ctx.allocator.free(self.framebuffers);
    vkDestroyRenderPass(ctx.vulkan.device, self.renderpass, null);
}
