const Vulkan = @import("vulkan");
const Context = Vulkan.Context;
usingnamespace Vulkan.C;
usingnamespace Vulkan.Utils;

const Self = @This();

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) Vec2 {
        return Vec2{
            .x = x,
            .y = y,
        };
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
};

pub const Vertex = struct {
    pos: Vec2,
    color: Vec3,

    pub fn getBindingDescription() VkVertexInputBindingDescription {
        return VkVertexInputBindingDescription{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn getAttributeDescriptions() [2]VkVertexInputAttributeDescription {
        return [2]VkVertexInputAttributeDescription{
            VkVertexInputAttributeDescription{
                .binding = 0,
                .location = 0,
                .format = VK_FORMAT_R32G32_SFLOAT,
                .offset = @offsetOf(Vertex, "pos"),
            },
            VkVertexInputAttributeDescription{
                .binding = 0,
                .location = 1,
                .format = VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    }
};

layout: VkPipelineLayout,
pipeline: VkPipeline,

pub fn init(ctx: Context, renderPass: VkRenderPass) !Self {
    const vert_code align(4) = @embedFile("../vert.spv").*;
    const frag_code align(4) = @embedFile("../frag.spv").*;

    const vert_module = try Vulkan.createShaderModule(ctx.vulkan.device, &vert_code);
    defer vkDestroyShaderModule(ctx.vulkan.device, vert_module, null);

    const frag_module = try Vulkan.createShaderModule(ctx.vulkan.device, &frag_code);
    defer vkDestroyShaderModule(ctx.vulkan.device, frag_module, null);

    const vert_stage_info = VkPipelineShaderStageCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = VK_SHADER_STAGE_VERTEX_BIT,
        .module = vert_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const frag_stage_info = VkPipelineShaderStageCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = frag_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const shader_stages = [_]VkPipelineShaderStageCreateInfo{ vert_stage_info, frag_stage_info };

    const binding_desc = Vertex.getBindingDescription();
    const attr_descs = Vertex.getAttributeDescriptions();
    const vertex_input_info = VkPipelineVertexInputStateCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &binding_desc,
        .vertexAttributeDescriptionCount = attr_descs.len,
        .pVertexAttributeDescriptions = &attr_descs,
    };

    const input_assembly_info = VkPipelineInputAssemblyStateCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = VK_FALSE,
    };

    const viewport = VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @intToFloat(f32, ctx.vulkan.swapchain.extent.width),
        .height = @intToFloat(f32, ctx.vulkan.swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = VkRect2D{
        .offset = VkOffset2D{ .x = 0, .y = 0 },
        .extent = ctx.vulkan.swapchain.extent,
    };

    const viewport_state = VkPipelineViewportStateCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    const rasterizer = VkPipelineRasterizationStateCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = VK_FALSE,
        .rasterizerDiscardEnable = VK_FALSE,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = VK_CULL_MODE_BACK_BIT,
        .frontFace = VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
    };

    const multisampling = VkPipelineMultisampleStateCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .sampleShadingEnable = VK_FALSE,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = VK_FALSE,
        .alphaToOneEnable = VK_FALSE,
    };

    const color_blend_attachment = VkPipelineColorBlendAttachmentState{
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT |
            VK_COLOR_COMPONENT_G_BIT |
            VK_COLOR_COMPONENT_B_BIT |
            VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = VK_TRUE,
        .srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = VK_BLEND_OP_ADD,
    };

    const color_blending = VkPipelineColorBlendStateCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = VK_FALSE,
        .logicOp = VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    // const dynamic_states = [_]VkDynamicState{
    //     VkDynamicState.VK_DYNAMIC_STATE_VIEWPORT,
    //     VkDynamicState.VK_DYNAMIC_STATE_LINE_WIDTH,
    // };
    // const dynamic_state = VkPipelineDynamicStateCreateInfo{
    //     .sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    //     .pNext = null,
    //     .flags = 0,
    //     .dynamicStateCount = 2,
    //     .pDynamicStates = &dynamic_states,
    // };

    const pipeline_layout_info = VkPipelineLayoutCreateInfo{
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    var pipeline_layout: VkPipelineLayout = undefined;
    try checkSuccess(
        vkCreatePipelineLayout(ctx.vulkan.device, &pipeline_layout_info, null, &pipeline_layout),
        error.VulkanPipelineLayoutCreationFailed,
    );

    const pipeline_info = VkGraphicsPipelineCreateInfo{
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_input_info,
        .pInputAssemblyState = &input_assembly_info,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = null,
        .pTessellationState = null,
        .layout = pipeline_layout,
        .renderPass = renderPass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };
    var pipeline: VkPipeline = undefined;
    try checkSuccess(
        vkCreateGraphicsPipelines(ctx.vulkan.device, null, 1, &pipeline_info, null, &pipeline),
        error.VulkanPipelineCreationFailed,
    );

    return Self{
        .layout = pipeline_layout,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: Self, ctx: Context) void {
    vkDestroyPipeline(ctx.vulkan.device, self.pipeline, null);
    vkDestroyPipelineLayout(ctx.vulkan.device, self.layout, null);
}
