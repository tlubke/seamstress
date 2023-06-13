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

pub const Device = union(Dev_t) {
    const input_dev = struct {
        id: u32,
        quit: bool,
        ptr: *c.RtMidiWrapper,
        thread: std.Thread = undefined,
        buf: [1024]u8 = undefined,
        name: []const u8,
        fn read(self: *input_dev) !bool {
            var len: usize = 1024;
            const timestamp = c.rtmidi_in_get_message(self.ptr, &self.buf, &len);
            if (self.ptr.*.ok != true) {
                const err = std.mem.span(self.ptr.*.msg);
                std.debug.print("error in device {s}: {s}\n", .{ self.name, err });
                self.quit = true;
                return false;
            }
            if (len == 0) return false;
            var line = try allocator.alloc(u8, len);
            std.mem.copyForwards(u8, line, self.buf[0..len]);
            var event = try events.new(events.Event.MIDI);
            event.MIDI.message = line;
            event.MIDI.timestamp = timestamp;
            event.MIDI.id = self.id;
            try events.post(event);
            return true;
        }
        fn loop(self: *input_dev) !void {
            while (!self.quit) {
                const did_read = try self.read();
                if (!did_read) std.time.sleep(std.time.ns_per_us * 300);
            }
            try Device.deinit(Dev_t.Input, self.id);
        }
    };
    const output_dev = struct {
        id: u32,
        ptr: *c.RtMidiWrapper,
        name: []const u8,
        pub fn write(self: *output_dev, message: []const u8) void {
            _ = c.rtmidi_out_send_message(self.ptr, message.ptr, @intCast(c_int, message.len));
            if (self.ptr.*.ok != true) {
                const err = std.mem.span(self.ptr.*.msg);
                std.debug.print("error in device {s}: {s}\n", .{ self.name, err });
                Device.deinit(Dev_t.Output, self.id) catch unreachable;
            }
        }
    };
    Input: input_dev,
    Output: output_dev,
    fn deinit(dev_type: Dev_t, id: u32) !void {
        switch (dev_type) {
            .Input => {
                const dev = in_list.remove(id);
                if (dev) |d| {
                    d.Input.quit = true;
                    d.Input.thread.join();
                    var event = try events.new(events.Event.MIDI_Remove);
                    event.MIDI_Remove.id = d.Input.id;
                    event.MIDI_Remove.dev_type = Dev_t.Input;
                    try events.post(event);
                    allocator.free(d.Input.name);
                    c.rtmidi_close_port(d.Input.ptr);
                    c.rtmidi_in_free(d.Input.ptr);
                    allocator.destroy(d);
                }
            },
            .Output => {
                const dev = out_list.remove(id);
                if (dev) |d| {
                    var event = try events.new(events.Event.MIDI_Remove);
                    event.MIDI_Remove.id = d.Output.id;
                    event.MIDI_Remove.dev_type = Dev_t.Output;
                    try events.post(event);
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
        var node = self.head;
        while (node != null and node.?.next != null) {
            node = node.?.next;
        }
        if (node == null) {
            std.debug.assert(self.size == 0);
            self.head = new_node;
        } else {
            node.?.next = new_node;
            new_node.prev = node.?;
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
        "seamstress", 1024) orelse return error.Fail;
    var name = try std.fmt.allocPrint(allocator, "{s}", .{"seamstress_in"});
    var dev = try allocator.create(Device);
    dev.* = Device{
        .Input = Device.input_dev{
            .id = id_counter,
            .quit = false,
            .ptr = midi_in,
            .name = name,
            // Device
        },
    };
    id_counter += 1;
    c.rtmidi_open_virtual_port(midi_in, "seamstress_in");
    dev.Input.thread = try std.Thread.spawn(.{}, Device.input_dev.loop, .{&dev.Input});
    try in_list.add(dev);

    midi_out = c.rtmidi_out_create( //
        c.RTMIDI_API_UNSPECIFIED, //
        "seamstress") orelse return error.Fail;
    name = try std.fmt.allocPrint(allocator, "{s}", .{"seamstress_in"});
    dev = try allocator.create(Device);
    dev.* = Device{
        .Output = Device.output_dev{
            .id = id_counter,
            .ptr = midi_out,
            .name = name,
            // Device
        },
    };
    id_counter += 1;
    c.rtmidi_open_virtual_port(midi_out, "seamstress_out");
    try out_list.add(dev);

    thread = try std.Thread.spawn(.{}, main_loop, .{});
}

fn main_loop() !void {
    while (!quit) {
        const in_count = c.rtmidi_get_port_count(midi_in);
        if (in_count > in_list.size) {
            var i: c_uint = 0;
            while (i < in_count) : (i += 1) {
                var len: c_int = 256;
                var buf = try allocator.alloc(u8, 256);
                _ = c.rtmidi_get_port_name(midi_in, i, buf.ptr, &len);
                if (!in_list.find(buf)) {
                    var dev = try create(Dev_t.Input, i, buf);
                    try in_list.add(dev);
                }
            }
        }
        const out_count = c.rtmidi_get_port_count(midi_out);
        if (out_count > out_list.size) {
            var i: c_uint = 0;
            while (i < out_count) : (i += 1) {
                var len: c_int = 256;
                var buf = try allocator.alloc(u8, 256);
                _ = c.rtmidi_get_port_name(midi_out, i, buf.ptr, &len);
                if (!out_list.find(buf)) {
                    var dev = try create(Dev_t.Output, i, buf);
                    try out_list.add(dev);
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
            "seamstress", 1024) orelse return error.Fail,
        Dev_t.Output => c.rtmidi_out_create( //
            c.RTMIDI_API_UNSPECIFIED, "seamstress") orelse return error.Fail,
    };
    var c_name = try allocator.allocSentinel(u8, name.len, 0);
    std.mem.copyForwards(u8, c_name, name);
    c.rtmidi_open_port(ptr, port_number, c_name.ptr);
    allocator.free(c_name);
    var dev = try allocator.create(Device);
    switch (dev_type) {
        Dev_t.Input => {
            dev.* = Device{
                .Input = Device.input_dev{
                    .id = id_counter,
                    .quit = false,
                    .ptr = ptr,
                    .name = name,
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
                    .name = name,
                    .ptr = ptr,
                },
                // Device
            };
            id_counter += 1;
            return dev;
        },
    }
}

pub fn deinit() !void {
    quit = true;
    thread.join();
    var node = in_list.head;
    while (node) |n| {
        node = n.next;
        try Device.deinit(Dev_t.Input, n.dev.Input.id);
    }
    node = out_list.head;
    while (node) |n| {
        node = n.next;
        try Device.deinit(Dev_t.Output, n.dev.Output.id);
    }
}
