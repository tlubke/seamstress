const std = @import("std");
const events = @import("events.zig");
const monome = @import("monome.zig");

pub const Dev_t = enum { Monome };

pub const dev_base = struct {
    // base device
    id: usize = undefined,
    thread: std.Thread = undefined,
    lock: std.Thread.Mutex = undefined,
    quit: bool = undefined,
    path: [:0]const u8 = undefined,
    serial: []u8 = undefined,
    name: []u8 = undefined,
};

pub const Device = union(Dev_t) { Monome: monome.Device };

const Dev_Node = struct {
    next: ?*Dev_Node,
    prev: ?*Dev_Node,
    dev: *Device,
    path: []const u8,
    // device node
};

const Dev_List = struct {
    head: ?*Dev_Node,
    tail: ?*Dev_Node,
    size: usize,
    // device list
};

var list = Dev_List{ .head = null, .tail = null, .size = 0 };
var allocator: std.mem.Allocator = undefined;
pub var id: u32 = 0;

pub fn init(alloc_pointer: std.mem.Allocator) void {
    allocator = alloc_pointer;
    monome.init(alloc_pointer);
}

pub fn add(dev_type: Dev_t, path: []const u8) !void {
    var dev = try new(dev_type, path);
    var event = try add_to_list(dev_type, dev, path);
    if (event != null) try events.post(event.?);
}

fn search(path: []const u8) ?*Dev_Node {
    var node = list.head;
    while (node) |n| {
        if (std.mem.eql(u8, path, n.path)) {
            return n;
        }
        node = n.next;
    }
    return null;
}

fn add_to_list(dev_type: Dev_t, device: *Device, path: []const u8) !?*events.Data {
    if (search(path) != null) return null;
    var new_node = try allocator.create(Dev_Node);
    var path_copy = try allocator.alloc(u8, path.len);
    std.mem.copyForwards(u8, path_copy, path);
    new_node.* = Dev_Node{ .dev = device, .path = path_copy, .next = null, .prev = null };
    var node = list.head;
    while (node != null and node.?.next != null) {
        node = node.?.next;
    }
    if (node == null) {
        std.debug.assert(list.size == 0);
        list.head = new_node;
    } else {
        node.?.next = new_node;
        new_node.prev = node.?;
    }
    list.tail = new_node;
    list.size += 1;
    var event: *events.Data = undefined;
    switch (dev_type) {
        .Monome => {
            event = try events.new(events.Event.Monome_Add);
            event.Monome_Add.dev = &device.Monome;
        },
    }
    return event;
}

pub fn remove(dev_type: Dev_t, path: []const u8) !void {
    var node = search(path);
    if (node == null) return;
    var dev = node.?.dev;
    switch (dev_type) {
        .Monome => {
            var event = try events.new(events.Event.Monome_Remove);
            event.Monome_Remove.id = switch (dev.*) {
                .Monome => dev.Monome.base.id,
            };
            try events.post(event);
        },
    }
    if (list.head == node.?) {
        list.head = node.?.next;
    }
    if (list.tail == node.?) {
        list.tail = node.?.prev;
    }
    var prev = node.?.prev;
    var next = node.?.next;
    if (prev != null) prev.?.next = next;
    if (next != null) next.?.prev = prev;
    list.size -= 1;
    free(dev);
    allocator.free(node.?.path);
    allocator.destroy(node.?);
}

fn new(dev_type: Dev_t, path: []const u8) !*Device {
    var path_copy: [:0]u8 = try allocator.allocSentinel(u8, path.len, 0);
    std.mem.copyForwards(u8, path_copy, path);
    var device: *Device = undefined;
    switch (dev_type) {
        .Monome => {
            device = try allocator.create(Device);
            device.* = Device{ .Monome = monome.Device{} };
            var base = try allocator.create(dev_base);
            base.* = dev_base{};
            device.Monome.base = base;
            try device.Monome.init(path_copy);
        },
    }
    return device;
}

fn free(dev: *Device) void {
    switch (dev.*) {
        .Monome => {
            dev.Monome.base.lock.lock();
            dev.Monome.base.quit = true;
            dev.Monome.base.lock.unlock();
            dev.Monome.base.thread.join();
            allocator.free(dev.Monome.base.name);
            allocator.free(dev.Monome.base.serial);
            allocator.free(dev.Monome.base.path);
            allocator.destroy(dev.Monome.base);
            allocator.destroy(dev);
        },
    }
}
