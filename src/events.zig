const std = @import("std");
const spindle = @import("spindle.zig");
const osc = @import("osc.zig");
const monome = @import("monome.zig");
const screen = @import("screen.zig");
const midi = @import("midi.zig");
const c = std.c;

pub const Event = enum(u4) {
    // list of event types
    Quit,
    Exec_Code_Line,
    OSC,
    Reset_LVM,
    Monome_Add,
    Monome_Remove,
    Grid_Key,
    Grid_Tilt,
    Arc_Encoder,
    Arc_Key,
    Screen_Key,
    Screen_Check,
    Metro,
    MIDI_Add,
    MIDI_Remove,
    MIDI,
};

pub const Data = union(Event) {
    Quit: void,
    Exec_Code_Line: event_exec_code_line,
    OSC: event_osc,
    Reset_LVM: void,
    Monome_Add: event_monome_add,
    Monome_Remove: event_monome_remove,
    Grid_Key: event_grid_key,
    Grid_Tilt: event_grid_tilt,
    Arc_Encoder: event_arc_delta,
    Arc_Key: event_arc_key,
    Screen_Key: event_screen_key,
    Screen_Check: void,
    Metro: event_metro,
    MIDI_Add: event_midi_add,
    MIDI_Remove: event_midi_remove,
    MIDI: event_midi,
    // event data struct
};

const event_exec_code_line = struct {
    line: [:0]const u8 = undefined,
    // exec_code
};

const event_osc = struct {
    from_host: [:0]const u8 = undefined,
    from_port: [:0]const u8 = undefined,
    path: [:0]const u8 = undefined,
    msg: []osc.Lo_Arg = undefined,
    // osc
};

const event_monome_add = struct {
    dev: *monome.Device = undefined,
    // device
};

const event_monome_remove = struct {
    id: usize = undefined,
    // monome_remove
};

const event_grid_key = struct {
    id: usize = undefined,
    x: u32 = undefined,
    y: u32 = undefined,
    state: i2 = undefined,
    // grid_key
};

const event_grid_tilt = struct {
    id: usize = undefined,
    sensor: u32 = undefined,
    x: i32 = undefined,
    y: i32 = undefined,
    z: i32 = undefined,
    // grid_tilt
};

const event_arc_delta = struct {
    id: usize = undefined,
    ring: u32 = undefined,
    delta: i32 = undefined,
    // arc_delta
};

const event_arc_key = struct {
    id: usize = undefined,
    ring: u32 = undefined,
    state: i2 = undefined,
    // arc_key
};

const event_screen_key = struct {
    scancode: i32 = undefined,
    // screen_key
};

const event_screen_check = struct {};

const event_metro = struct {
    id: u8 = undefined,
    stage: i64 = undefined,
    // metro
};

const event_midi_add = struct {
    dev: *midi.Device = undefined,
    dev_type: midi.Dev_t = undefined,
    id: u32 = undefined,
    name: [:0]const u8 = undefined,
    // midi_add
};

const event_midi_remove = struct {
    id: u32 = undefined,
    dev_type: midi.Dev_t = undefined,
    // midi_remove
};

const event_midi = struct {
    id: u32 = undefined,
    timestamp: f64 = undefined,
    message: []const u8 = undefined,
    // midi
};

var allocator: std.mem.Allocator = undefined;

const Queue = struct {
    const Node = struct {
        // node
        next: ?*Node,
        prev: ?*Node,
        ev: *Data,
    };
    head: ?*Node,
    tail: ?*Node,
    size: usize,
    lock: std.Thread.Mutex,
    cond: std.Thread.Condition,
    fn push(self: *Queue, data: *Data) !void {
        var new_node = try allocator.create(Node);
        new_node.* = Node{ .next = null, .prev = null, .ev = data };
        if (self.tail) |n| {
            self.tail = new_node;
            n.next = new_node;
            new_node.prev = n;
        } else {
            std.debug.assert(self.size == 0);
            self.tail = new_node;
            self.head = new_node;
        }
        self.size += 1;
    }
    fn pop(self: *Queue) ?*Data {
        if (self.head) |n| {
            const ev = n.ev;
            self.head = n.next;
            allocator.destroy(n);
            if (self.size == 1) self.tail = null;
            self.size -= 1;
            return ev;
        } else {
            std.debug.assert(self.size == 0);
            return null;
        }
    }
};

var queue: Queue = undefined;

var quit: bool = false;

pub fn init(alloc_ptr: std.mem.Allocator) !void {
    allocator = alloc_ptr;
    queue = Queue{ .head = null, .tail = null, .cond = .{}, .lock = .{}, .size = 0 };
}

test "init" {
    try init(std.testing.allocator);
}

pub fn loop() !void {
    std.debug.print("> ", .{});
    while (!quit) {
        queue.lock.lock();
        while (queue.size == 0) {
            if (quit) break;
            queue.cond.wait(&queue.lock);
            continue;
        }
        const ev = queue.pop();
        queue.lock.unlock();
        if (ev != null) try handle(ev.?);
    }
}

pub fn new(event_type: Event) !*Data {
    // TODO: surely there's a metaprogramming solution to this nonsense
    var event = try allocator.create(Data);
    event.* = switch (event_type) {
        Event.Quit => Data{ .Quit = {} },
        Event.Exec_Code_Line => Data{ .Exec_Code_Line = event_exec_code_line{} },
        Event.Reset_LVM => Data{ .Reset_LVM = {} },
        Event.OSC => Data{ .OSC = event_osc{} },
        Event.Monome_Add => Data{ .Monome_Add = event_monome_add{} },
        Event.Monome_Remove => Data{ .Monome_Remove = event_monome_remove{} },
        Event.Grid_Key => Data{ .Grid_Key = event_grid_key{} },
        Event.Grid_Tilt => Data{ .Grid_Tilt = event_grid_tilt{} },
        Event.Arc_Encoder => Data{ .Arc_Encoder = event_arc_delta{} },
        Event.Arc_Key => Data{ .Arc_Key = event_arc_key{} },
        Event.Screen_Key => Data{ .Screen_Key = event_screen_key{} },
        Event.Screen_Check => Data{ .Screen_Check = {} },
        Event.Metro => Data{ .Metro = event_metro{} },
        Event.MIDI_Add => Data{ .MIDI_Add = event_midi_add{} },
        Event.MIDI_Remove => Data{ .MIDI_Remove = event_midi_remove{} },
        Event.MIDI => Data{ .MIDI = event_midi{} },
    };
    return event;
}

pub fn free(event: *Data) void {
    switch (event.*) {
        Event.OSC => |e| {
            allocator.free(e.path);
            allocator.free(e.from_host);
            allocator.free(e.from_port);
            allocator.free(e.msg);
        },
        Event.Exec_Code_Line => |e| {
            allocator.free(e.line);
        },
        Event.MIDI_Add => |e| {
            allocator.free(e.name);
        },
        Event.MIDI => |e| {
            allocator.free(e.message);
        },
        else => {},
    }
    allocator.destroy(event);
}

pub fn post(event: *Data) !void {
    queue.lock.lock();
    try queue.push(event);
    queue.cond.signal();
    queue.lock.unlock();
}

pub fn handle_pending() !void {
    var event: ?*Data = null;
    var done = false;
    while (!done) {
        queue.lock.lock();
        if (queue.size > 0) {
            event = queue.pop();
        } else {
            done = true;
        }
        queue.lock.unlock();
        if (event != null) try handle(event.?);
        event = null;
    }
}

pub fn free_pending() void {
    var event: ?*Data = null;
    var done = false;
    while (!done) {
        if (queue.size > 0) {
            event = queue.pop();
        } else {
            done = true;
        }
        if (event) |ev| free(ev);
        event = null;
    }
}

fn handle(event: *Data) !void {
    switch (event.*) {
        Event.Quit => {
            quit = true;
        },
        Event.Exec_Code_Line => {
            try spindle.exec_code_line(event.Exec_Code_Line.line);
        },
        Event.OSC => {
            try spindle.osc_event(event.OSC.from_host, event.OSC.from_port, event.OSC.path, event.OSC.msg);
        },
        Event.Reset_LVM => {
            try spindle.reset_lua();
        },
        Event.Monome_Add => {
            try spindle.monome_add(event.Monome_Add.dev);
        },
        Event.Monome_Remove => {
            try spindle.monome_remove(event.Monome_Remove.id);
        },
        Event.Grid_Key => {
            try spindle.grid_key(event.Grid_Key.id, event.Grid_Key.x, event.Grid_Key.y, event.Grid_Key.state);
        },
        Event.Grid_Tilt => {
            try spindle.grid_tilt(event.Grid_Tilt.id, event.Grid_Tilt.sensor, event.Grid_Tilt.x, event.Grid_Tilt.y, event.Grid_Tilt.z);
        },
        Event.Arc_Encoder => {
            try spindle.arc_delta(event.Arc_Encoder.id, event.Arc_Encoder.ring, event.Arc_Encoder.delta);
        },
        Event.Arc_Key => {
            try spindle.arc_key(event.Arc_Key.id, event.Arc_Key.ring, event.Arc_Key.state);
        },
        Event.Screen_Key => {
            try spindle.screen_key(event.Screen_Key.scancode);
        },
        Event.Screen_Check => {
            try screen.check();
        },
        Event.Metro => {
            try spindle.metro_event(event.Metro.id, event.Metro.stage);
        },
        Event.MIDI_Add => {
            try spindle.midi_add(event.MIDI_Add.dev, event.MIDI_Add.dev_type, event.MIDI_Add.id, event.MIDI_Add.name);
        },
        Event.MIDI_Remove => {
            try spindle.midi_remove(event.MIDI_Remove.dev_type, event.MIDI_Remove.id);
        },
        Event.MIDI => {
            try spindle.midi_event(event.MIDI.id, event.MIDI.timestamp, event.MIDI.message);
        },
    }
    free(event);
}
