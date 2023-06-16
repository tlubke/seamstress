const dev = @import("monome.zig");
const std = @import("std");
const c = @import("c_includes.zig").os_imported;

const notify = struct { notify_add: c.IONotificationPortRef, notify_destroy: c.IONotificationPortRef, iter_add: c.io_iterator_t, iter_destroy: c.io_iterator_t };

var state: *notify = undefined;
var thread: std.Thread = undefined;
var run_loop: ?*c.struct___CFRunLoop = null;
var allocator: std.mem.Allocator = undefined;

fn wait_on_parent_usbdevice(device: c.io_service_t) bool {
    var dev_copy = device;
    var parent: c.io_registry_entry_t = undefined;
    while (true) {
        if (c.IORegistryEntryGetParentEntry(dev_copy, c.kIOServicePlane, &parent) != 0) {
            return true;
        }
        dev_copy = parent;

        if (c.IOObjectConformsTo(dev_copy, c.kIOUSBDeviceClassName) != 0) {
            break;
        }
    }
    _ = c.IOServiceWaitQuiet(dev_copy, null);
    return false;
}

fn iterate_devices(context: ?*anyopaque, iter: c.io_iterator_t) callconv(.C) void {
    _ = context;
    try_add(iter);
}

fn deiterate_devices(context: ?*anyopaque, iter: c.io_iterator_t) callconv(.C) void {
    _ = context;
    var device = c.IOIteratorNext(iter);
    var device_node = allocator.alloc(u8, 256) catch unreachable;
    var len: u32 = 256;
    while (device != 0) : (device = c.IOIteratorNext(iter)) {
        _ = c.IORegistryEntryGetProperty(device, c.kIODialinDeviceKey, device_node.ptr, &len);
        dev.remove(device_node[0..len]) catch {
            std.debug.print("removing device failed at address {s}\n", .{device_node[0..len]});
        };
        _ = c.IOObjectRelease(device);
    }
    allocator.free(device_node);
}

inline fn try_add(iter: c.io_iterator_t) void {
    var device: c.io_service_t = c.IOIteratorNext(iter);
    var device_node = allocator.alloc(u8, 256) catch unreachable;
    var len: u32 = 256;
    while (device != 0) : (device = c.IOIteratorNext(iter)) {
        _ = c.IORegistryEntryGetProperty(device, c.kIODialinDeviceKey, device_node.ptr, &len);
        if (!wait_on_parent_usbdevice(device)) {
            dev.add(device_node[0..len]) catch {
                std.debug.print("adding device failed at address {s}\n", .{device_node[0..len]});
            };
        }
        _ = c.IOObjectRelease(device);
    }
    allocator.free(device_node);
}

pub fn init(alloc_pointer: std.mem.Allocator) !void {
    allocator = alloc_pointer;
    dev.init(alloc_pointer);
    state = try allocator.create(notify);
    thread = try std.Thread.spawn(.{}, loop, .{});
}

fn loop() !void {
    try setup_usb();
    c.CFRunLoopRun();
}

fn setup_usb() !void {
    var matching: c.CFMutableDictionaryRef = undefined;
    const kIOSerialBSDTypeKey = "IOSerialBSDClientType";
    const kIOSerialBSDAllTypes = "IOSerialStream";
    matching = c.IOServiceMatching(c.kIOSerialBSDServiceValue);
    c.CFDictionarySetValue(matching, //
        c.CFStringCreateWithCString(null, kIOSerialBSDTypeKey, 134217984), //
        c.CFStringCreateWithCString(null, kIOSerialBSDAllTypes, 134217984));
    var main_port: c.mach_port_t = undefined;
    _ = c.IOMainPort(c.MACH_PORT_NULL, &main_port);
    state.notify_add = c.IONotificationPortCreate(main_port);
    if (state.notify_add == null) {
        std.debug.print("dev_monitor_init(): couldn't allocate notification port!\n", .{});
        return error.Fail;
    }
    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), //
        c.IONotificationPortGetRunLoopSource(state.notify_add.?), //
        c.kCFRunLoopDefaultMode); //
    _ = c.CFRetain(matching);
    _ = c.IOServiceAddMatchingNotification(state.notify_add.?, //
        c.kIOMatchedNotification, //
        matching, //
        iterate_devices, //
        state, //
        &state.iter_add); //
    try_add(state.iter_add);
    state.notify_destroy = c.IONotificationPortCreate(c.kIOMainPortDefault);
    if (state.notify_destroy == null) {
        std.debug.print("dev_monitorr_init(): couldn't allocate notification port!\n", .{});
        return error.Fail;
    }
    c.CFRunLoopAddSource(c.CFRunLoopGetCurrent(), //
        c.IONotificationPortGetRunLoopSource(state.notify_destroy), //
        c.kCFRunLoopDefaultMode); //
    _ = c.IOServiceAddMatchingNotification(state.notify_destroy, //
        c.kIOTerminatedNotification, //
        matching, //
        deiterate_devices, //
        state, //
        &state.iter_destroy); //
    while (c.IOIteratorNext(state.iter_destroy) != 0) {}
    run_loop = c.CFRunLoopGetCurrent();
}

pub fn deinit() void {
    c.CFRunLoopStop(run_loop);
    thread.join();
    _ = c.IOObjectRelease(state.iter_add);
    _ = c.IOObjectRelease(state.iter_destroy);
    _ = c.IONotificationPortDestroy(state.notify_add);
    _ = c.IONotificationPortDestroy(state.notify_destroy);
    allocator.destroy(state);
    dev.deinit();
}
