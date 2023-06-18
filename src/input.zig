const std = @import("std");
const events = @import("events.zig");
const c = @import("c_includes.zig").imported;

var quit = false;
var pid: std.Thread = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(allocator_pointer: std.mem.Allocator) !void {
    allocator = allocator_pointer;
    pid = try std.Thread.spawn(.{}, input_run, .{});
}

pub fn deinit() void {
    quit = true;
    std.io.getStdIn().close();
    pid.join();
}

fn input_run() !void {
    var stdout = std.io.getStdOut().writer();
    var stdin = std.io.getStdIn().reader();
    var buf = try allocator.alloc(u8, 4096);
    defer allocator.free(buf);
    var fds = [1]std.os.pollfd{
        .{ .fd = 0, .events = std.os.POLL.IN, .revents = 0 },
    };
    set_signal();
    while (!quit) {
        const data = try std.os.poll(&fds, 1);
        if (data == 0) continue;
        const len = stdin.read(buf) catch break;
        if (len == 0) break;
        if (len >= buf.len - 1) {
            try stdout.print("error: line too long!\n", .{});
            continue;
        }
        var line: [:0]u8 = try allocator.allocSentinel(u8, len, 0);
        std.mem.copyForwards(u8, line, buf[0..len]);
        if (std.mem.eql(u8, line, "quit\n")) {
            allocator.free(line);
            quit = true;
            continue;
        }
        const event = .{ .Exec_Code_Line = .{ .line = line } };
        events.post(event);
    }
    events.post(.{ .Quit = {} });
}

fn set_signal() void {
    _ = c.signal(c.SIGINT, signal_handler);
}

fn signal_handler(signal: c_int) callconv(.C) void {
    _ = signal;
    quit = true;
}
