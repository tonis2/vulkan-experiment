const std = @import("std");
const Vulkan = @import("vulkan");
const Buffer = Vulkan.Buffer;
const Camera = @import("camera.zig");

usingnamespace @import("zalgebra");
usingnamespace Vulkan.C;
usingnamespace Vulkan.Utils;


const Self = @This();

pub const Vertex = struct {
    pos: Vec3,
    color: Vec3,
};

layout: VkPipelineLayout,
pipeline: VkPipeline,
descriptorLayouts: []VkDescriptorSetLayout,
descriptorSets: []VkDescriptorSet,
descriptorPool: VkDescriptorPool,
buffers: [3]Buffer.From(Camera, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT),

pub fn init(vulkan: Vulkan, renderPass: VkRenderPass, camera: Camera) !Self {
    const max_images = 3;

    var buffers: [max_images]Buffer.From(Camera, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT) = undefined;

    buffers[0] = try Buffer.From(Camera, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT).init(vulkan, &[_]Camera{camera});
    buffers[1] = try Buffer.From(Camera, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT).init(vulkan, &[_]Camera{camera});
    buffers[2] = try Buffer.From(Camera, VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT).init(vulkan, &[_]Camera{camera});

    var descriptorLayouts = try vulkan.allocator.alloc(VkDescriptorSetLayout, max_images);
    var descriptorSets = try vulkan.allocator.alloc(VkDescriptorSet, max_images);
    var descriptorPool: VkDescriptorPool = undefined;

    // Create descriptor pool

    const poolInfo = VkDescriptorPoolCreateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .poolSizeCount = 1,
        .pPoolSizes = &[_]VkDescriptorPoolSize{VkDescriptorPoolSize{
            .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = max_images,
        }},
        .maxSets = @intCast(u32, max_images),
        .pNext = null,
        .flags = 0,
    };

    try checkSuccess(vkCreateDescriptorPool(vulkan.device, &poolInfo, null, &descriptorPool), error.VulkanDescriptorPoolFailed);

    // Create descriptor layout

    const descriptorBindings = [_]VkDescriptorSetLayoutBinding{VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
        .pImmutableSamplers = null,
    }};

    const layoutInfo = VkDescriptorSetLayoutCreateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &descriptorBindings,
        .pNext = null,
        .flags = 0,
    };

    for (descriptorLayouts) |*layout| {
        try checkSuccess(
            vkCreateDescriptorSetLayout(vulkan.device, &layoutInfo, null, layout),
            error.VulkanPipelineLayoutCreationFailed,
        );
    }

    try checkSuccess(vkAllocateDescriptorSets(vulkan.device, &VkDescriptorSetAllocateInfo{
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptorPool,
        .descriptorSetCount = max_images,
        .pSetLayouts = descriptorLayouts.ptr,
        .pNext = null,
    }, descriptorSets.ptr), error.DescriptorAllocationFailed);

    for (descriptorSets) |set, i| {
        vkUpdateDescriptorSets(vulkan.device, 1, &[_]VkWriteDescriptorSet{VkWriteDescriptorSet{
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = set,
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &VkDescriptorBufferInfo{
                .buffer = buffers[i].buffer,
                .offset = 0,
                .range = @sizeOf(Camera),
            },
            .pImageInfo = null,
            .pTexelBufferView = null,
            .pNext = null,
        }}, 0, null);
    }

    // Pipeline

    const vert_code align(4) = @embedFile("./vert.spv").*;
    const frag_code align(4) = @embedFile("./frag.spv").*;

    const vert_module = try Vulkan.createShaderModule(vulkan.device, &vert_code);
    defer vkDestroyShaderModule(vulkan.device, vert_module, null);

    const frag_module = try Vulkan.createShaderModule(vulkan.device, &frag_code);
    defer vkDestroyShaderModule(vulkan.device, frag_module, null);

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

    const binding_desc = VkVertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const attr_descs = [2]VkVertexInputAttributeDescription{
        VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(Vertex, "pos"),
        },
        VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(Vertex, "color"),
        },
    };
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
        .width = @intToFloat(f32, vulkan.swapchain.extent.width),
        .height = @intToFloat(f32, vulkan.swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = VkRect2D{
        .offset = VkOffset2D{ .x = 0, .y = 0 },
        .extent = vulkan.swapchain.extent,
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
        .setLayoutCount = 2,
        .pSetLayouts = descriptorLayouts.ptr,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };
    var pipeline_layout: VkPipelineLayout = undefined;
    try checkSuccess(
        vkCreatePipelineLayout(vulkan.device, &pipeline_layout_info, null, &pipeline_layout),
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
        vkCreateGraphicsPipelines(vulkan.device, null, 1, &pipeline_info, null, &pipeline),
        error.VulkanPipelineCreationFailed,
    );

    return Self{
        .descriptorLayouts = descriptorLayouts,
        .descriptorPool = descriptorPool,
        .descriptorSets = descriptorSets,
        .buffers = buffers,
        .layout = pipeline_layout,
        .pipeline = pipeline,
    };
}

pub fn deinit(self: Self, vulkan: Vulkan) void {
    for (self.buffers) |buffer| buffer.deinit(vulkan);

    for (self.descriptorLayouts) |layout| vkDestroyDescriptorSetLayout(vulkan.device, layout, null);

    vulkan.allocator.free(self.descriptorLayouts);
    vulkan.allocator.free(self.descriptorSets);

    vkDestroyDescriptorPool(vulkan.device, self.descriptorPool, null);

    // vkDestroyDescriptorSetLayout(vulkan.device, self.descriptorLayout, null);
    // vkDestroyDescriptorPool(vulkan.device, self.descriptorPool, null);
    vkDestroyPipeline(vulkan.device, self.pipeline, null);
    vkDestroyPipelineLayout(vulkan.device, self.layout, null);
}
