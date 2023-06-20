const std = @import("std");
const c = @import("c_includes.zig").imported;
const events = @import("events.zig");

var allocator: std.mem.Allocator = undefined;
var thread: std.Thread = undefined;
var quit = false;
var in_list = List{ .head = null, .tail = null, .size = 0 };
var out_list = List{ .head = null, .tail = null, .size = 0 };
var midi_in: *c.RtMidiWrapper = undefined;
var midi_out: *c.RtMidiWrapper = undefined;
var id_counter: u32 = 0;

pub const Dev_t = enum { Input, Output };

const RtMidiPrefix = "seamstress";

pub const Device = union(Dev_t) {
    const input_dev = struct {
        id: u32,
        quit: bool,
        ptr: *c.RtMidiWrapper,
        thread: std.Thread = undefined,
        buf: [1024]u8 = undefined,
        name: [:0]const u8,
        fn read(self: *input_dev) !void {
            var len: usize = 1024;
            while (len > 0) {
                len = 1024;
                const timestamp = c.rtmidi_in_get_message(self.ptr, &self.buf, &len);
                if (self.ptr.*.ok != true) {
                    const err = std.mem.span(self.ptr.*.msg);
                    std.debug.print("error in device {s}: {s}\n", .{ self.name, err });
                    self.quit = true;
                    return;
                }
                if (len == 0) break;
                var line = try allocator.alloc(u8, len);
                std.mem.copyForwards(u8, line, self.buf[0..len]);
                const event = .{ .MIDI = .{ .message = line, .timestamp = timestamp, .id = self.id } };
                events.post(event);
            }
        }
        fn loop(self: *input_dev) !void {
            while (!self.quit) {
                try self.read();
                std.time.sleep(std.time.ns_per_ms);
            }
            Device.deinit(Dev_t.Input, self.id);
        }
    };
    const output_dev = struct {
        id: u32,
        ptr: *c.RtMidiWrapper,
        name: [:0]const u8,
        pub fn write(self: *output_dev, message: []const u8) void {
            _ = c.rtmidi_out_send_message(self.ptr, message.ptr, @intCast(c_int, message.len));
            if (self.ptr.*.ok != true) {
                const err = std.mem.span(self.ptr.*.msg);
                std.debug.print("error in device {s}: {s}\n", .{ self.name, err });
                Device.deinit(Dev_t.Output, self.id);
            }
        }
    };
    Input: input_dev,
    Output: output_dev,
    fn deinit(dev_type: Dev_t, id: u32) void {
        switch (dev_type) {
            .Input => {
                const dev = in_list.remove(id);
                if (dev) |d| {
                    d.Input.quit = true;
                    d.Input.thread.join();
                    const event = .{ .MIDI_Remove = .{ .id = d.Input.id, .dev_type = .Input } };
                    events.post(event);
                    allocator.free(d.Input.name);
                    c.rtmidi_close_port(d.Input.ptr);
                    c.rtmidi_in_free(d.Input.ptr);
                    allocator.destroy(d);
                }
            },
            .Output => {
                const dev = out_list.remove(id);
                if (dev) |d| {
                    const event = .{ .MIDI_Remove = .{ .id = d.Output.id, .dev_type = .Output } };
                    events.post(event);
                    allocator.free(d.Output.name);
                    c.rtmidi_close_port(d.Output.ptr);
                    c.rtmidi_out_free(d.Output.ptr);
                    allocator.destroy(d);
                }
            },
        }
    }
};

const List = struct {
    const Node = struct {
        next: ?*Node,
        prev: ?*Node,
        dev: *Device,
        // node
    };
    head: ?*Node,
    tail: ?*Node,
    size: u32,
    fn find(self: *List, name: []const u8) bool {
        var node = self.head;
        while (node) |n| {
            switch (n.dev.*) {
                .Input => if (std.mem.eql(u8, name, n.dev.Input.name)) return true,
                .Output => if (std.mem.eql(u8, name, n.dev.Output.name)) return true,
            }
            node = n.next;
        }
        return false;
    }
    fn search(self: *List, id: u32) ?*Node {
        var node = self.head;
        while (node) |n| {
            switch (n.dev.*) {
                .Input => if (n.dev.Input.id == id) return n,
                .Output => if (n.dev.Output.id == id) return n,
            }
            node = n.next;
        }
        return null;
    }
    fn add(self: *List, dev: *Device) !void {
        var new_node = try allocator.create(Node);
        new_node.* = Node{ .next = null, .prev = null, .dev = dev };
        if (self.tail) |n| {
            n.next = new_node;
            new_node.prev = n;
        } else {
            std.debug.assert(self.size == 0);
            self.head = new_node;
        }
        self.tail = new_node;
        self.size += 1;
    }
    fn remove(self: *List, id: u32) ?*Device {
        const node = self.search(id);
        if (node == null) return null;
        const dev = node.?.dev;
        const prev = node.?.prev;
        const next = node.?.next;
        if (self.head == node.?) self.head = next;
        if (self.tail == node.?) self.tail = prev;
        if (next) |n| n.prev = prev;
        if (prev) |p| p.next = next;
        self.size -= 1;
        allocator.destroy(node.?);
        return dev;
    }
};

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    allocator = alloc_pointer;
    midi_in = c.rtmidi_in_create( //
        c.RTMIDI_API_UNSPECIFIED, //
        RtMidiPrefix, 1024) orelse return error.Fail;
    var in_name = try std.fmt.allocPrintZ(allocator, "{s}", .{"seamstress_in"});
    var dev = try allocator.create(Device);
    dev.* = Device{
        .Input = Device.input_dev{
            .id = id_counter,
            .quit = false,
            .ptr = midi_in,
            .name = in_name,
            // Device
        },
    };
    id_counter += 1;
    c.rtmidi_open_virtual_port(midi_in, "seamstress_in");
    dev.Input.thread = try std.Thread.spawn(.{}, Device.input_dev.loop, .{&dev.Input});
    try in_list.add(dev);

    midi_out = c.rtmidi_out_create( //
        c.RTMIDI_API_UNSPECIFIED, //
        RtMidiPrefix) orelse return error.Fail;
    var out_name = try std.fmt.allocPrintZ(allocator, "{s}", .{"seamstress_out"});
    dev = try allocator.create(Device);
    dev.* = Device{
        .Output = Device.output_dev{
            .id = id_counter,
            .ptr = midi_out,
            .name = out_name,
            // Device
        },
    };
    id_counter += 1;
    c.rtmidi_open_virtual_port(midi_out, "seamstress_out");
    try out_list.add(dev);

    thread = try std.Thread.spawn(.{}, main_loop, .{});
}

// NB: on Linux, RtMidi keeps on reanouncing registered devices w/ the added `RtMidiPrefix`
// this function allows retecting if a device name has this prefix (and thus is already registered)
fn is_device_name_rt_midi_prefixed(src: []const u8) bool {
    const prefix = RtMidiPrefix ++ ":";
    if (src.len > prefix.len and std.mem.eql(u8, prefix, src[0..prefix.len])) {
        return true;
    }
    return false;
}

fn main_loop() !void {
    while (!quit) {
        const in_count = c.rtmidi_get_port_count(midi_in);
        if (in_count > in_list.size) {
            var i: c_uint = 0;
            while (i < in_count) : (i += 1) {
                var len: c_int = 256;
                _ = c.rtmidi_get_port_name(midi_in, i, null, &len);
                var buf = try allocator.alloc(u8, @intCast(usize, len));
                defer allocator.free(buf);
                _ = c.rtmidi_get_port_name(midi_in, i, buf.ptr, &len);
                if (!is_device_name_rt_midi_prefixed(buf) and !in_list.find(buf)) {
                    std.debug.print("found new IN: {s} \n", .{buf});
                    var dev = try create(Dev_t.Input, i, buf);
                    try in_list.add(dev);
                    var name_copy = try allocator.allocSentinel(u8, dev.Input.name.len, 0);
                    std.mem.copyForwards(u8, name_copy, dev.Input.name);
                    const event = .{
                        .MIDI_Add = .{
                            // add event
                            .dev = dev,
                            .dev_type = .Input,
                            .id = dev.Input.id,
                            .name = name_copy,
                        },
                    };
                    events.post(event);
                }
            }
        }
        const out_count = c.rtmidi_get_port_count(midi_out);
        if (out_count > out_list.size) {
            var i: c_uint = 0;
            while (i < out_count) : (i += 1) {
                var len: c_int = 256;
                _ = c.rtmidi_get_port_name(midi_out, i, null, &len);
                var buf = try allocator.alloc(u8, @intCast(usize, len));
                defer allocator.free(buf);
                _ = c.rtmidi_get_port_name(midi_out, i, buf.ptr, &len);
                if (!is_device_name_rt_midi_prefixed(buf) and !out_list.find(buf)) {
                    std.debug.print("found new OUT: {s}\n", .{buf});
                    var dev = try create(Dev_t.Output, i, buf);
                    try out_list.add(dev);
                    var name_copy = try allocator.allocSentinel(u8, dev.Output.name.len, 0);
                    std.mem.copyForwards(u8, name_copy, dev.Output.name);
                    const event = .{
                        .MIDI_Add = .{
                            // add event
                            .dev = dev,
                            .dev_type = .Output,
                            .id = dev.Output.id,
                            .name = name_copy,
                        },
                    };
                    events.post(event);
                }
            }
        }
        std.time.sleep(std.time.ns_per_s);
    }
}

fn create(dev_type: Dev_t, port_number: c_uint, name: []const u8) !*Device {
    var ptr = switch (dev_type) {
        Dev_t.Input => c.rtmidi_in_create( //
            c.RTMIDI_API_UNSPECIFIED, //
            RtMidiPrefix, 1024) orelse return error.Fail,
        Dev_t.Output => c.rtmidi_out_create( //
            c.RTMIDI_API_UNSPECIFIED, RtMidiPrefix) orelse return error.Fail,
    };
    var c_name = try allocator.allocSentinel(u8, name.len, 0);
    std.mem.copyForwards(u8, c_name, name);
    c.rtmidi_open_port(ptr, port_number, c_name.ptr);
    var dev = try allocator.create(Device);
    switch (dev_type) {
        Dev_t.Input => {
            dev.* = Device{
                .Input = Device.input_dev{
                    .id = id_counter,
                    .quit = false,
                    .ptr = ptr,
                    .name = c_name,
                },
                // Device
            };
            id_counter += 1;
            dev.Input.thread = try std.Thread.spawn(.{}, Device.input_dev.loop, .{&dev.Input});
            return dev;
        },
        Dev_t.Output => {
            dev.* = Device{
                .Output = Device.output_dev{
                    .id = id_counter,
                    .name = c_name,
                    .ptr = ptr,
                },
                // Device
            };
            id_counter += 1;
            return dev;
        },
    }
}

pub fn deinit() void {
    quit = true;
    thread.join();
    var node = in_list.head;
    while (node) |n| {
        node = n.next;
        Device.deinit(Dev_t.Input, n.dev.Input.id);
    }
    node = out_list.head;
    while (node) |n| {
        node = n.next;
        Device.deinit(Dev_t.Output, n.dev.Output.id);
    }
}
