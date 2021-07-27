const std = @import("std");
const engine = @import("engine");
const vk = @import("vk");

const Context = engine.Context;
const Self = @This();

pass: vk.RenderPass,
ctx: Context,

pub fn new(ctx: Context, format: vk.Format) !Self {
    const color_attachment = vk.AttachmentDescription{
        .flags = .{},
        .format = format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .@"undefined",
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .flags = .{},
        .pipeline_bind_point = .graphics,
        .input_attachment_count = 0,
        .p_input_attachments = undefined,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, &color_attachment_ref),
        .p_resolve_attachments = null,
        .p_depth_stencil_attachment = null,
        .preserve_attachment_count = 0,
        .p_preserve_attachments = undefined,
    };

    var renderpass = try ctx.vkd.createRenderPass(ctx.device, .{
        .flags = .{},
        .attachment_count = 1,
        .p_attachments = @ptrCast([*]const vk.AttachmentDescription, &color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast([*]const vk.SubpassDescription, &subpass),
        .dependency_count = 0,
        .p_dependencies = undefined,
    }, null);

    return Self{
        .pass = renderpass,
        .ctx = ctx,
    };
}

pub fn deinit(self: Self) void {
    self.ctx.vkd.destroyRenderPass(self.ctx.device, self.pass, null);
}
