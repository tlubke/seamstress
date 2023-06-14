const std = @import("std");

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    _ = alloc_pointer;
}

pub fn deinit() void {}
