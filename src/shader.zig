const std = @import("std");
const vk = @import("vk");
const Context = @import("context.zig");
const Self = @This();

module: vk.ShaderModule,
ctx: Context,
bytes: []u8,

pub fn load(source: []const u8, ctx: Context) !Self {
    const bytes = try std.fs.cwd().readFileAllocOptions(ctx.allocator, source, std.math.maxInt(u32), null, @alignOf(u32), 0);
    const create_info = vk.ShaderModuleCreateInfo{
        .code_size = bytes.len,
        .p_code = @ptrCast([*]const u32, bytes),
        .flags = .{},
    };

    return Self{ .module = try ctx.vkd.createShaderModule(ctx.device, create_info, null), .ctx = ctx, .bytes = bytes };
}

pub fn deinit(self: Self) void {
    self.ctx.vkd.destroyShaderModule(self.ctx.device, self.module, null);
    self.ctx.allocator.free(self.bytes);
}
