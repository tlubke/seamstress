const std = @import("std");
const events = @import("events.zig");
const lo = @import("c_includes.zig").imported;

var server_thread: lo.lo_server_thread = undefined;
var dnssd_ref: lo.DNSServiceRef = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(local_port: [:0]const u8, alloc: std.mem.Allocator) !void {
    allocator = alloc;
    server_thread = lo.lo_server_thread_new(local_port, lo_error_handler);
    if (server_thread == null) return error.Fail;
    _ = lo.lo_server_thread_add_method(server_thread, null, null, osc_receive, null);
    _ = lo.lo_server_thread_start(server_thread);
    const port = @intCast(u16, lo.lo_server_thread_get_port(server_thread));
    _ = lo.DNSServiceRegister(&dnssd_ref, 0, 0, "seamstress", "_osc._udp", null, null, port, 0, null, null, null);
}

pub fn deinit() void {
    _ = lo.DNSServiceRefDeallocate(dnssd_ref);
    lo.lo_server_thread_free(server_thread);
}

pub fn send(to_host: [*:0]const u8, to_port: [*:0]const u8, path: [*:0]const u8, msg: []Lo_Arg) void {
    const address: lo.lo_address = lo.lo_address_new(to_host, to_port);
    if (address == null) {
        std.debug.print("failed to create lo_address\n", .{});
        return;
    }
    var message: lo.lo_message = lo.lo_message_new();
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        switch (msg[i]) {
            Lo_Arg_t.Lo_Int32 => |a| _ = lo.lo_message_add_int32(message, a),
            Lo_Arg_t.Lo_Float => |a| _ = lo.lo_message_add_float(message, a),
            Lo_Arg_t.Lo_String => |a| _ = lo.lo_message_add_string(message, a),
            Lo_Arg_t.Lo_Blob => |a| {
                const blob = lo.lo_blob_new(a.datasize, a.dataptr);
                _ = lo.lo_message_add_blob(message, blob);
            },
            Lo_Arg_t.Lo_Int64 => |a| _ = lo.lo_message_add_int64(message, a),
            Lo_Arg_t.Lo_Double => |a| _ = lo.lo_message_add_double(message, a),
            Lo_Arg_t.Lo_Symbol => |a| _ = lo.lo_message_add_symbol(message, a),
            Lo_Arg_t.Lo_Midi => |a| _ = lo.lo_message_add_midi(message, @ptrCast([*c]u8, @constCast(a[0..4]))),
            Lo_Arg_t.Lo_True => |a| {
                _ = a;
                _ = lo.lo_message_add_true(message);
            },
            Lo_Arg_t.Lo_False => |a| {
                _ = a;
                _ = lo.lo_message_add_false(message);
            },
            Lo_Arg_t.Lo_Nil => |a| {
                _ = a;
                _ = lo.lo_message_add_nil(message);
            },
            Lo_Arg_t.Lo_Infinitum => |a| {
                _ = a;
                _ = lo.lo_message_add_infinitum(message);
            },
        }
    }
    _ = lo.lo_send_message(address, path, message);
    lo.lo_address_free(address);
    lo.lo_message_free(message);
}

fn lo_error_handler(num: c_int, m: [*c]const u8, path: [*c]const u8) callconv(.C) void {
    if (path == null) {
        std.debug.print("liblo error {d}: {s}\n", .{ num, m });
    } else {
        std.debug.print("liblo error {d} in path {s}: {s}\n", .{ num, path, m });
    }
}

fn osc_receive(path: [*c]const u8, types: [*c]const u8, argv: [*c][*c]lo.lo_arg, argc: c_int, msg: lo.lo_message, user_data: lo.lo_message) callconv(.C) c_int {
    _ = path;
    _ = user_data;
    defer lo.lo_message_free(msg);
    const source = lo.lo_message_get_source(msg);
    _ = source;
    // const c_host: [*c]const u8 = lo.lo_address_get_hostname(source);
    // const host: [:0]const u8 = std.mem.span(c_host);
    // const c_port: [*c]const u8 = lo.lo_address_get_port(source);
    // const port: [:0]const u8 = std.mem.span(c_port);
    // const path_copy: [:0]const u8 = std.mem.span(path);
    const arg_size = @intCast(usize, argc);
    var message: []Lo_Arg = allocator.alloc(Lo_Arg, arg_size) catch unreachable;

    var i: usize = 0;
    while (i < argc) : (i += 1) {
        switch (types[i]) {
            lo.LO_INT32 => {
                message[i] = Lo_Arg{ .Lo_Int32 = argv[i].*.i };
            },
            lo.LO_FLOAT => {
                message[i] = Lo_Arg{ .Lo_Float = argv[i].*.f };
            },
            // lo.LO_STRING => {
            //    message[i] = Lo_Arg{ .Lo_String = std.mem.span(argv[i].*.s) };
            // },
            lo.LO_BLOB => {
                const arg = argv[i];
                message[i] = Lo_Arg{ .Lo_Blob = Lo_Blob_t{
                    .dataptr = lo.lo_blob_dataptr(arg),
                    .datasize = @intCast(i32, lo.lo_blob_datasize(arg)),
                } };
            },
            lo.LO_INT64 => {
                message[i] = Lo_Arg{ .Lo_Int64 = argv[i].*.h };
            },
            lo.LO_DOUBLE => {
                message[i] = Lo_Arg{ .Lo_Double = argv[i].*.d };
            },
            // lo.LO_SYMBOL => {
            //     message[i] = Lo_Arg{ .Lo_Symbol = std.mem.span(argv[i].*.S) };
            // },
            lo.LO_MIDI => {
                message[i] = Lo_Arg{ .Lo_Midi = argv[i].*.m };
            },
            lo.LO_TRUE => {
                message[i] = Lo_Arg{ .Lo_True = true };
            },
            lo.LO_FALSE => {
                message[i] = Lo_Arg{ .Lo_False = false };
            },
            lo.LO_NIL => {
                message[i] = Lo_Arg{ .Lo_Nil = false };
            },
            lo.LO_INFINITUM => {
                message[i] = Lo_Arg{ .Lo_Infinitum = true };
            },
            else => {
                std.debug.print("unknown osc typetag: {c}\n", .{types[i]});
                message[i] = Lo_Arg{ .Lo_Nil = false };
            },
        }
    }

    var event = events.new(events.Event.OSC) catch {
        return -1;
    };
    event.OSC.msg = message;
    event.OSC.from_host = "";
    event.OSC.from_port = "";
    event.OSC.path = "";

    events.post(event) catch {
        return -1;
    };
    return 0;
}

pub const Lo_Arg_t = enum {
    Lo_Int32,
    Lo_Float,
    Lo_String,
    Lo_Blob,
    Lo_Int64,
    Lo_Double,
    Lo_Symbol,
    Lo_Midi,
    Lo_True,
    Lo_False,
    Lo_Nil,
    Lo_Infinitum,
    // lo_msg arg types
};

pub const Lo_Blob_t = struct { dataptr: ?*anyopaque, datasize: i32 };

pub const Lo_Arg = union(Lo_Arg_t) {
    Lo_Int32: i32,
    Lo_Float: f32,
    Lo_String: [:0]const u8,
    Lo_Blob: Lo_Blob_t,
    Lo_Int64: i64,
    Lo_Double: f64,
    Lo_Symbol: [:0]const u8,
    Lo_Midi: [4]u8,
    Lo_True: bool,
    Lo_False: bool,
    Lo_Nil: bool,
    Lo_Infinitum: bool,
    // Lo_Arg union
};
