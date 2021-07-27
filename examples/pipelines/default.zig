const std = @import("std");
const engine = @import("engine");
const vk = @import("vk");

const Context = engine.Context;
const Shader = engine.Shader;
const Self = @This();

const Renderpass = @import("../renderpass/default.zig");

pub const Vertex = struct {
    pos: [2]f32,
    color: [3]f32,

    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };
};

layout: vk.PipelineLayout,
pipeline: vk.Pipeline,
context: Context,
fragment: Shader,
vertex: Shader,

pub fn new(ctx: Context, renderpass: Renderpass) !Self {
    const pipeline_layout = try ctx.vkd.createPipelineLayout(ctx.device, .{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);

    const vert = try Shader.load("./shaders/triangle.vert", ctx);
    const frag = try Shader.load("./shaders/triangle.frag", ctx);

    const shaderStages = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .flags = .{},
            .stage = .{ .vertex_bit = true },
            .module = vert.module,
            .p_name = "main",
            .p_specialization_info = null,
        },
        .{
            .flags = .{},
            .stage = .{ .fragment_bit = true },
            .module = frag.module,
            .p_name = "main",
            .p_specialization_info = null,
        },
    };

    const colorBlendState = vk.PipelineColorBlendStateCreateInfo{
        .flags = .{},
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast([*]const vk.PipelineColorBlendAttachmentState, &vk.PipelineColorBlendAttachmentState{
            .blend_enable = vk.FALSE,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        }),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };

    const pipelineInfo = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &shaderStages,
        .p_vertex_input_state = &vk.PipelineVertexInputStateCreateInfo{
            .flags = .{},
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = @ptrCast([*]const vk.VertexInputBindingDescription, &Vertex.binding_description),
            .vertex_attribute_description_count = Vertex.attribute_description.len,
            .p_vertex_attribute_descriptions = &Vertex.attribute_description,
        },
        .p_input_assembly_state = &vk.PipelineInputAssemblyStateCreateInfo{
            .flags = .{},
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        },
        .p_tessellation_state = null,
        .p_viewport_state = &vk.PipelineViewportStateCreateInfo{
            .flags = .{},
            .viewport_count = 1,
            .p_viewports = undefined,
            .scissor_count = 1,
            .p_scissors = undefined,
        },
        .p_rasterization_state = &vk.PipelineRasterizationStateCreateInfo{
            .flags = .{},
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        },
        .p_multisample_state = &vk.PipelineMultisampleStateCreateInfo{
            .flags = .{},
            .rasterization_samples = .{ .@"1_bit" = true },
            .sample_shading_enable = vk.FALSE,
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        },
        .p_depth_stencil_state = null,
        .p_color_blend_state = &colorBlendState,
        .p_dynamic_state = &vk.PipelineDynamicStateCreateInfo{
            .flags = .{},
            .dynamic_state_count = dynstate.len,
            .p_dynamic_states = &dynstate,
        },
        .layout = pipeline_layout,
        .render_pass = renderpass.pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try ctx.vkd.createGraphicsPipelines(
        ctx.device,
        .null_handle,
        1,
        @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &pipelineInfo),
        null,
        @ptrCast([*]vk.Pipeline, &pipeline),
    );

    return Self{
        .pipeline = pipeline,
        .layout = pipeline_layout,
        .context = ctx,
        .fragment = frag,
        .vertex = vert,
    };
}

pub fn deinit(self: *Self) void {
    self.vertex.deinit();
    self.fragment.deinit();
    self.context.vkd.destroyPipelineLayout(self.context.device, self.layout, null);
    self.context.vkd.destroyPipeline(self.context.device, self.pipeline, null);
}
