const std = @import("std");
const device = @import("device.zig");
const events = @import("events.zig");
const c = @import("c_includes.zig").imported;

var allocator: std.mem.Allocator = undefined;

pub fn init(alloc_pointer: std.mem.Allocator) void {
    allocator = alloc_pointer;
}

const Monome_t = enum { Grid, Arc };

pub const Device = struct {
    base: *device.dev_base = undefined,
    dev_type: Monome_t = undefined,
    m_dev: *c.struct_monome = undefined,
    data: [4][64]u8 = undefined,
    dirty: [4]bool = undefined,
    cols: u8 = undefined,
    rows: u8 = undefined,
    quads: u8 = undefined,
    pub fn init(self: *Device, path: [:0]const u8) !void {
        self.base.path = path;
        var m = c.monome_open(path);
        if (m == null) {
            std.debug.print("error: couldn't open monome device at {s}\n", .{path});
            return error.Fail;
        }
        self.m_dev = m.?;
        self.base.id = device.id;
        device.id += 1;
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

        const c_name = std.mem.span(c.monome_get_friendly_name(m));
        self.base.name = try allocator.alloc(u8, c_name.len);
        std.mem.copyForwards(u8, self.base.name, c_name);

        const c_serial = std.mem.span(c.monome_get_serial(m));
        self.base.serial = try allocator.alloc(u8, c_serial.len);
        std.mem.copyForwards(u8, self.base.serial, c_serial);

        self.base.lock = .{};
        self.base.quit = false;
        self.base.thread = try std.Thread.spawn(.{}, loop, .{ self.base, self.m_dev });
    }
    pub fn deinit(self: *Device) void {
        c.monome_close(self.m_dev);
        allocator.free(self.base.name);
        allocator.free(self.base.path);
        allocator.free(self.base.serial);
        allocator.destroy(self.base);
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
    event.Grid_Key.id = self.base.id;
    event.Grid_Key.x = e.*.unnamed_0.grid.x;
    event.Grid_Key.y = e.*.unnamed_0.grid.y;
    event.Grid_Key.state = state;
    events.post(event) catch unreachable;
}

inline fn arc_key_event(e: [*c]const c.monome_event_t, ptr: ?*anyopaque, state: i2) void {
    const self = @ptrCast(*Device, @alignCast(8, ptr.?));
    var event = events.new(events.Event.Arc_Key) catch unreachable;
    event.Arc_Key.id = self.base.id;
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
    event.Grid_Tilt.id = self.base.id;
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
    event.Arc_Encoder.id = self.base.id;
    event.Arc_Encoder.ring = e.*.unnamed_0.encoder.number;
    event.Arc_Encoder.delta = e.*.unnamed_0.encoder.delta;
    events.post(event) catch unreachable;
}

fn loop(self: *device.dev_base, monome: *c.struct_monome) void {
    while (true) {
        self.lock.lock();
        if (self.quit) {
            self.lock.unlock();
            break;
        }
        self.lock.unlock();
        while (c.monome_event_handle_next(monome) != 0) {}
        std.os.nanosleep(0, 1000);
    }
}
