const std = @import("std");
const events = @import("events.zig");
const c = @import("c_includes.zig").imported;

var allocator: std.mem.Allocator = undefined;
var id: usize = 0;
var list = Monome_List{ .head = null, .tail = null, .size = 0 };

pub fn init(alloc_pointer: std.mem.Allocator) void {
    allocator = alloc_pointer;
}

pub fn deinit() void {
    while (list.pop_and_deinit()) {}
}

const Monome_List = struct {
    const Node = struct {
        next: ?*Node,
        prev: ?*Node,
        dev: *Device,
        path: []const u8,
    };
    head: ?*Node,
    tail: ?*Node,
    size: usize,
    fn pop_and_deinit(self: *Monome_List) bool {
        if (self.head) |n| {
            self.head = n.next;
            const dev = n.dev;
            dev.deinit();
            allocator.destroy(n);
            self.size -= 1;
            return true;
        } else {
            std.debug.assert(self.size == 0);
            return false;
        }
    }
    fn search(self: *Monome_List, path: []const u8) ?*Node {
        var node = self.head;
        while (node) |n| {
            if (std.mem.eql(u8, path, n.path)) {
                return n;
            }
            node = n.next;
        }
        return null;
    }
    fn add(self: *Monome_List, dev: *Device, path: []const u8) !*events.Data {
        var new_node = try allocator.create(Node);
        new_node.* = Node{ .dev = dev, .path = path, .next = null, .prev = null };
        if (self.tail) |n| {
            n.next = new_node;
            new_node.prev = n;
        } else {
            std.debug.assert(self.size == 0);
            self.head = new_node;
        }
        self.tail = new_node;
        self.size += 1;
        var event = try events.new(events.Event.Monome_Add);
        event.Monome_Add.dev = dev;
        return event;
    }
    fn remove(self: *Monome_List, path: []const u8) !void {
        var node = self.search(path);
        if (node == null) return;
        var dev = node.?.dev;
        var event = try events.new(events.Event.Monome_Remove);
        event.Monome_Remove.id = dev.id;
        try events.post(event);
        if (self.head == node.?) self.head = node.?.next;
        if (self.tail == node.?) self.tail = node.?.prev;
        var prev = node.?.prev;
        var next = node.?.next;
        if (prev) |p| p.next = next;
        if (next) |n| n.prev = prev;
        self.size -= 1;
        dev.deinit();
        allocator.free(node.?.path);
        allocator.destroy(node.?);
    }
};

pub fn remove(path: []const u8) !void {
    try list.remove(path);
}

pub fn add(path: []const u8) !void {
    if (list.search(path) != null) return;
    const dev = try new(path);
    var event = try list.add(dev, path);
    try events.post(event);
}

fn new(path: []const u8) !*Device {
    var path_copy: [:0]u8 = try allocator.allocSentinel(u8, path.len, 0);
    std.mem.copyForwards(u8, path_copy, path);
    var device = try allocator.create(Device);
    device.* = Device{};
    try device.init(path_copy);
    return device;
}

const Monome_t = enum { Grid, Arc };

pub const Device = struct {
    id: usize = undefined,
    thread: std.Thread = undefined,
    lock: std.Thread.Mutex = undefined,
    quit: bool = undefined,
    path: [:0]const u8 = undefined,
    serial: []const u8 = undefined,
    name: []const u8 = undefined,
    dev_type: Monome_t = undefined,
    m_dev: *c.struct_monome = undefined,
    data: [4][64]u8 = undefined,
    dirty: [4]bool = undefined,
    cols: u8 = undefined,
    rows: u8 = undefined,
    quads: u8 = undefined,
    pub fn init(self: *Device, path: [:0]const u8) !void {
        self.path = path;
        var m = c.monome_open(path);
        if (m == null) {
            std.debug.print("error: couldn't open monome device at {s}\n", .{path});
            return error.Fail;
        }
        self.m_dev = m.?;
        self.id = id;
        id += 1;
        var i: u8 = 0;
        while (i < 4) : (i += 1) {
            self.dirty[i] = false;
            var j: u8 = 0;
            while (j < 64) : (j += 1) {
                self.data[i][j] = 0;
            }
        }
        self.rows = @intCast(u8, c.monome_get_rows(m));
        self.cols = @intCast(u8, c.monome_get_cols(m));

        if (self.rows == 0 and self.cols == 0) {
            std.debug.print("monome device reports zero rows/cols; assuming arc\n", .{});
            self.dev_type = .Arc;
            self.quads = 4;
        } else {
            self.dev_type = .Grid;
            self.quads = (self.rows * self.cols) / 64;
            std.debug.print("monome device appears to be a grid; rows={d}, cols={d}; quads={d}\n", .{ self.rows, self.cols, self.quads });
        }

        _ = c.monome_register_handler(m, c.MONOME_BUTTON_DOWN, handle_press, self);
        _ = c.monome_register_handler(m, c.MONOME_BUTTON_UP, handle_lift, self);
        _ = c.monome_register_handler(m, c.MONOME_ENCODER_DELTA, handle_delta, self);
        _ = c.monome_register_handler(m, c.MONOME_ENCODER_KEY_DOWN, handle_encoder_press, self);
        _ = c.monome_register_handler(m, c.MONOME_ENCODER_KEY_UP, handle_encoder_lift, self);
        _ = c.monome_register_handler(m, c.MONOME_TILT, handle_tilt, self);

        self.name = std.mem.span(c.monome_get_friendly_name(m));
        self.serial = std.mem.span(c.monome_get_serial(m));

        self.lock = .{};
        self.quit = false;
        self.thread = try std.Thread.spawn(.{}, loop, .{ self, self.m_dev });
    }
    pub fn deinit(self: *Device) void {
        self.lock.lock();
        self.quit = true;
        self.lock.unlock();
        self.thread.join();
        c.monome_close(self.m_dev);
        allocator.free(self.path);
        allocator.destroy(self);
    }
    pub fn set_rotation(self: *Device, rotation: u8) void {
        c.monome_set_rotation(self.m_dev, rotation);
    }
    pub fn tilt_enable(self: *Device, sensor: u8) void {
        _ = c.monome_tilt_enable(self.m_dev, sensor);
    }
    pub fn tilt_disable(self: *Device, sensor: u8) void {
        _ = c.monome_tilt_disable(self.m_dev, sensor);
    }
    pub fn grid_set_led(self: *Device, x: u8, y: u8, val: u8) void {
        const q = quad_index(x, y);
        self.data[q][quad_offset(x, y)] = val;
        self.dirty[q] = true;
    }
    pub fn grid_all_led(self: *Device, val: u8) void {
        var q: u8 = 0;
        while (q < self.quads) : (q += 1) {
            var i: u8 = 0;
            while (i < 64) : (i += 1) {
                self.data[q][i] = val;
            }
            self.dirty[q] = true;
        }
    }
    pub fn arc_set_led(self: *Device, ring: u8, led: u8, val: u8) void {
        self.data[ring][led] = val;
        self.dirty[ring] = true;
    }
    pub fn refresh(self: *Device) void {
        const quad_xoff = [_]u8{ 0, 8, 0, 8 };
        const quad_yoff = [_]u8{ 0, 0, 8, 8 };
        var quad: u8 = 0;
        while (quad < self.quads) : (quad += 1) {
            if (self.dirty[quad]) {
                switch (self.dev_type) {
                    .Arc => _ = c.monome_led_ring_map(self.m_dev, quad, &self.data[quad]),
                    .Grid => _ = c.monome_led_level_map(self.m_dev, quad_xoff[quad], quad_yoff[quad], &self.data[quad]),
                }
            }
            self.dirty[quad] = false;
        }
    }
    pub fn intensity(self: *Device, level: u8) void {
        if (level > 15) {
            _ = c.monome_led_intensity(self.m_dev, 15);
        } else {
            _ = c.monome_led_intensity(self.m_dev, level);
        }
    }
};

inline fn quad_index(x: u8, y: u8) u8 {
    switch (y) {
        0...7 => {
            switch (x) {
                0...7 => return 0,
                else => return 1,
            }
        },
        else => {
            switch (x) {
                0...7 => return 2,
                else => return 3,
            }
        },
    }
}

inline fn quad_offset(x: u8, y: u8) u8 {
    return ((y & 7) * 8) + (x & 7);
}

inline fn grid_key_event(e: [*c]const c.monome_event_t, ptr: ?*anyopaque, state: i2) void {
    const self = @ptrCast(*Device, @alignCast(8, ptr.?));
    var event = events.new(events.Event.Grid_Key) catch unreachable;
    event.Grid_Key.id = self.id;
    event.Grid_Key.x = e.*.unnamed_0.grid.x;
    event.Grid_Key.y = e.*.unnamed_0.grid.y;
    event.Grid_Key.state = state;
    events.post(event) catch unreachable;
}

inline fn arc_key_event(e: [*c]const c.monome_event_t, ptr: ?*anyopaque, state: i2) void {
    const self = @ptrCast(*Device, @alignCast(8, ptr.?));
    var event = events.new(events.Event.Arc_Key) catch unreachable;
    event.Arc_Key.id = self.id;
    event.Arc_Key.ring = e.*.unnamed_0.encoder.number;
    event.Arc_Key.state = state;
    events.post(event) catch unreachable;
}

fn handle_press(e: [*c]const c.monome_event_t, ptr: ?*anyopaque) callconv(.C) void {
    grid_key_event(e, ptr, 1);
}

fn handle_lift(e: [*c]const c.monome_event_t, ptr: ?*anyopaque) callconv(.C) void {
    grid_key_event(e, ptr, 0);
}

fn handle_tilt(e: [*c]const c.monome_event_t, ptr: ?*anyopaque) callconv(.C) void {
    const self = @ptrCast(*Device, @alignCast(8, ptr.?));
    var event = events.new(events.Event.Grid_Tilt) catch unreachable;
    event.Grid_Tilt.id = self.id;
    event.Grid_Tilt.sensor = e.*.unnamed_0.tilt.sensor;
    event.Grid_Tilt.x = e.*.unnamed_0.tilt.x;
    event.Grid_Tilt.y = e.*.unnamed_0.tilt.y;
    event.Grid_Tilt.z = e.*.unnamed_0.tilt.z;
    events.post(event) catch unreachable;
}

fn handle_encoder_press(e: [*c]const c.monome_event_t, ptr: ?*anyopaque) callconv(.C) void {
    arc_key_event(e, ptr, 1);
}

fn handle_encoder_lift(e: [*c]const c.monome_event_t, ptr: ?*anyopaque) callconv(.C) void {
    arc_key_event(e, ptr, 0);
}

fn handle_delta(e: [*c]const c.monome_event_t, ptr: ?*anyopaque) callconv(.C) void {
    const self = @ptrCast(*Device, @alignCast(8, ptr.?));
    var event = events.new(events.Event.Arc_Encoder) catch unreachable;
    event.Arc_Encoder.id = self.id;
    event.Arc_Encoder.ring = e.*.unnamed_0.encoder.number;
    event.Arc_Encoder.delta = e.*.unnamed_0.encoder.delta;
    events.post(event) catch unreachable;
}

fn loop(self: *Device, monome: *c.struct_monome) void {
    while (!self.quit) {
        switch (c.monome_event_handle_next(monome)) {
            1 => continue,
            0 => std.time.sleep(1000),
            else => self.quit = true,
        }
    }
}
