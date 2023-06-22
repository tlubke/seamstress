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

    var win = c.initscr();
    defer _ = c.endwin();

    // Try new term
    // 1. Haven't tried yet

    // Try new window:
    // 1. same issues with std.debug.print
    //
    // var win = c.newwin(1, 80, 0, 0);
    // defer _ = c.delwin(win);

    _ = c.keypad(win, true);
    _ = c.noecho();
    
    var col: c_int =  0;
    
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    
    var fds = [1]std.os.pollfd{
        .{ .fd = 0, .events = std.os.POLL.IN, .revents = 0 },
    };
    
    set_signal();
    
    while (!quit) {
        const data = try std.os.poll(&fds, 1);
        if (data == 0) continue;
        
        const key: c_int = c.getch();
        _ = switch( key ){
            c.KEY_LEFT  => col -= 1,
            c.KEY_RIGHT => { 
                col = std.math.clamp(col + 1, 0, @min(buf.items.len, 80)); 
            },
            c.KEY_UP    => {}, // History Previous
            c.KEY_DOWN  => {}, // History Next
            c.KEY_BACKSPACE, 127 => {
                col -= 1;
                if( buf.items.len > 0 ){
                    _ = buf.orderedRemove(@intCast(usize, col));
                }
            },
            c.KEY_ENTER, 10 => {
                if (std.mem.eql(u8, buf.items, "quit")) {
                    quit = true;
                    continue;
                }

                var line: [:0]u8 = try allocator.allocSentinel(u8, buf.items.len + 1, 0);
                std.mem.copyForwards(u8, line, buf.items);
                
                const event = .{ .Exec_Code_Line = .{ .line = line} };
                events.post(event);
                
                buf.clearRetainingCapacity();
                col = 0;
            },
            else => {
                try buf.insert(@intCast(usize, col), @intCast(u8, key & 0xFF));
                col += 1;
            }
        };

        var str_from_buf: [:0]u8 = try allocator.allocSentinel(u8, buf.items.len + 1, 0);
        std.mem.copyForwards(u8, str_from_buf, buf.items);

        _ = c.mvaddstr(0,0, str_from_buf);
        _ = c.move(0, col);
        _ = c.refresh();

        allocator.free(str_from_buf);
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
