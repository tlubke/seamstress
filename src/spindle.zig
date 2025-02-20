/// zig->lua and lua->zig interface
// @author ryleelyman
// @module seamstress
const std = @import("std");
const args = @import("args.zig");
const osc = @import("serialosc.zig");
const events = @import("events.zig");
const monome = @import("monome.zig");
const midi = @import("midi.zig");
const clock = @import("clock.zig");
const screen = @import("screen.zig");
const metro = @import("metros.zig");
const ziglua = @import("ziglua");

const Lua = ziglua.Lua;
var lvm: Lua = undefined;
var config_file: []const u8 = undefined;
var script_file: [:0]const u8 = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn init(config: []const u8, alloc_pointer: std.mem.Allocator) !void {
    config_file = config;
    allocator = alloc_pointer;

    std.debug.print("starting lua vm\n", .{});
    lvm = try Lua.init(allocator);

    lvm.openLibs();

    lvm.newTable();

    register_seamstress("osc_send", ziglua.wrap(osc_send));

    register_seamstress("grid_set_led", ziglua.wrap(grid_set_led));
    register_seamstress("grid_all_led", ziglua.wrap(grid_all_led));
    register_seamstress("grid_rows", ziglua.wrap(grid_rows));
    register_seamstress("grid_cols", ziglua.wrap(grid_cols));
    register_seamstress("grid_set_rotation", ziglua.wrap(grid_set_rotation));
    register_seamstress("grid_tilt_enable", ziglua.wrap(grid_tilt_enable));
    register_seamstress("grid_tilt_disable", ziglua.wrap(grid_tilt_disable));

    register_seamstress("arc_set_led", ziglua.wrap(arc_set_led));
    register_seamstress("arc_all_led", ziglua.wrap(arc_all_led));

    register_seamstress("monome_refresh", ziglua.wrap(monome_refresh));
    register_seamstress("monome_intensity", ziglua.wrap(monome_intensity));

    register_seamstress("screen_refresh", ziglua.wrap(screen_refresh));
    register_seamstress("screen_pixel", ziglua.wrap(screen_pixel));
    register_seamstress("screen_line", ziglua.wrap(screen_line));
    register_seamstress("screen_rect", ziglua.wrap(screen_rect));
    register_seamstress("screen_rect_fill", ziglua.wrap(screen_rect_fill));
    register_seamstress("screen_text", ziglua.wrap(screen_text));
    register_seamstress("screen_color", ziglua.wrap(screen_color));
    register_seamstress("screen_clear", ziglua.wrap(screen_clear));
    register_seamstress("screen_set", ziglua.wrap(screen_set));
    register_seamstress("screen_show", ziglua.wrap(screen_show));
    register_seamstress("screen_get_size", ziglua.wrap(screen_get_size));
    register_seamstress("screen_get_text_size", ziglua.wrap(screen_get_text_size));

    register_seamstress("metro_start", ziglua.wrap(metro_start));
    register_seamstress("metro_stop", ziglua.wrap(metro_stop));
    register_seamstress("metro_set_time", ziglua.wrap(metro_set_time));

    register_seamstress("midi_write", ziglua.wrap(midi_write));

    register_seamstress("clock_resume", ziglua.wrap(clock_resume));
    register_seamstress("clock_get_tempo", ziglua.wrap(clock_get_tempo));
    register_seamstress("clock_get_beats", ziglua.wrap(clock_get_beats));
    register_seamstress("clock_cancel", ziglua.wrap(clock_cancel));

    register_seamstress("reset_lvm", ziglua.wrap(reset_lvm));
    register_seamstress("quit_lvm", ziglua.wrap(quit_lvm));

    _ = lvm.pushString(args.local_port);
    lvm.setField(-2, "local_port");
    _ = lvm.pushString(args.remote_port);
    lvm.setField(-2, "remote_port");

    lvm.setGlobal("_seamstress");

    const cmd = try std.fmt.allocPrint(allocator, "dofile({s})\n ", .{config});
    defer allocator.free(cmd);
    var realcmd = try allocator.allocSentinel(u8, cmd.len, 0);
    defer allocator.free(realcmd);
    std.mem.copyForwards(u8, realcmd, cmd);
    try run_code(realcmd[0..cmd.len :0]);
    try run_code("require('core/seamstress')");
}

fn register_seamstress(name: [:0]const u8, f: ziglua.CFn) void {
    lvm.pushFunction(f);
    lvm.setField(-2, name);
}

pub fn deinit() void {
    std.debug.print("\nshutting down lua vm\n", .{});
    lvm.deinit();
    if (save_buf) |s| allocator.free(s);
}

pub fn startup(script: [:0]const u8) !void {
    script_file = script;
    _ = lvm.pushString(script_file);
    _ = try lvm.getGlobal("_startup");
    lvm.insert(1);
    try docall(&lvm, 1, 0);
}

/// sends OSC to specified address.
// users should use `osc:send` instead.
// @param address a table of the form `{host, port}`, both strings
// @param path a string representing an OSC path `/like/this`
// @param args an array whose data will be passed to OSC as arguments
// @see osc.send
// @usage osc.send({"localhost", "7777"}, "/send/stuff", {"a", 0, 0.5, nil, true})
// @function osc_send
fn osc_send(l: *Lua) i32 {
    var host: ?[*:0]const u8 = null;
    var port: ?[*:0]const u8 = null;
    var path: ?[*:0]const u8 = null;
    const num_args = l.getTop();
    if (num_args < 2) return 0;
    l.checkType(1, ziglua.LuaType.table);
    if (l.rawLen(1) != 2) {
        l.argError(1, "address should be a table in the form {host, port}");
    }

    l.pushNumber(1);
    _ = l.getTable(1);
    if (l.isString(-1)) {
        host = l.toString(-1) catch unreachable;
    } else {
        l.argError(1, "address should be a table in the form {host, port}");
    }
    l.pop(1);

    l.pushNumber(2);
    _ = l.getTable(1);
    if (l.isString(-1)) {
        port = l.toString(-1) catch unreachable;
    } else {
        l.argError(1, "address should be a table in the form {host, port}");
    }
    l.pop(1);

    l.checkType(2, ziglua.LuaType.string);
    path = l.toString(2) catch unreachable;
    if (host == null or port == null or path == null) {
        return 1;
    }

    var msg: []osc.Lo_Arg = undefined;
    if (num_args == 2) {
        osc.send(host.?, port.?, path.?, msg);
        return 0;
    }
    l.checkType(3, ziglua.LuaType.table);
    const len = l.rawLen(3);
    msg = allocator.alloc(osc.Lo_Arg, len) catch |err| {
        if (err == error.OutOfMemory) std.debug.print("out of memory!\n", .{});
        return 0;
    };
    defer allocator.free(msg);
    var i: usize = 1;
    while (i <= len) : (i += 1) {
        l.pushInteger(@intCast(c_longlong, i));
        _ = l.getTable(3);
        msg[i - 1] = switch (l.typeOf(-1)) {
            .nil => osc.Lo_Arg{ .Lo_Nil = false },
            .boolean => blk: {
                if (l.toBoolean(-1)) {
                    break :blk osc.Lo_Arg{ .Lo_True = true };
                } else {
                    break :blk osc.Lo_Arg{ .Lo_False = false };
                }
            },
            .number => osc.Lo_Arg{ .Lo_Double = l.toNumber(-1) catch unreachable },
            .string => blk: {
                const str = std.mem.span(l.toString(-1) catch unreachable);
                break :blk osc.Lo_Arg{ .Lo_String = str };
            },
            else => blk: {
                const str = std.fmt.allocPrint(allocator, "invalid osc argument type {s}", .{l.typeName(l.typeOf(-1))}) catch unreachable;
                l.raiseErrorStr(str[0..str.len :0], .{});
                break :blk osc.Lo_Arg{ .Lo_Nil = false };
            },
        };
        l.pop(1);
    }
    osc.send(host.?, port.?, path.?, msg);
    l.setTop(0);
    return 0;
}

/// sets grid led.
// users should use `grid:led` instead.
// @param md opaque pointer to monome device
// @param x x-coordinate for led (1-indexed)
// @param y y-coordinate for led (1-indexed)
// @param val brightness for led (0-15)
// @see grid:led
// @function grid_set_led
fn grid_set_led(l: *Lua) i32 {
    check_num_args(l, 4);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const x = @intCast(u8, l.checkInteger(2) - 1);
    const y = @intCast(u8, l.checkInteger(3) - 1);
    const val = @intCast(u8, l.checkInteger(4));
    md.grid_set_led(x, y, val);
    l.setTop(0);
    return 0;
}

/// sets all grid leds.
// users should use `grid:all` instead.
// @param md opaque pointer to monome device
// @param val brightness for led (0-15)
// @see grid:all
// @function grid_all_led
fn grid_all_led(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const val = @intCast(u8, l.checkInteger(2));
    md.grid_all_led(val);
    l.setTop(0);
    return 0;
}

/// reports number of rows of grid device.
// @param md opaque pointer to monome device
// @return number of rows
// @function grid_rows
fn grid_rows(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    l.setTop(0);
    l.pushInteger(md.rows);
    return 1;
}

/// reports number of columns of grid device.
// @param md opaque pointer to monome device
// @return number of columns
// @function grid_cols
fn grid_cols(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    l.setTop(0);
    l.pushInteger(md.cols);
    return 1;
}

/// sets grid rotation.
// users should use `grid:rotation` instead
// @param md opaque pointer to monome device
// @param rotation value to rotate
// @see grid:rotation
// @function grid_set_rotation
fn grid_set_rotation(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const rotation = @intCast(u16, l.checkInteger(2));
    md.set_rotation(rotation);
    l.setTop(0);
    return 0;
}

/// enable tilt data.
// users should use `grid:tilt` instead
// @param md opaque pointer to monome device
// @param sensor tilt sensor to enable
// @see grid:tilt
// @function grid_tilt_enable
fn grid_tilt_enable(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const sensor = @intCast(u8, l.checkInteger(2) - 1);
    md.tilt_set(sensor, 1);
    return 0;
}

/// disable tilt data.
// users should use `grid:tilt` instead
// @param md opaque pointer to monome device
// @param sensor tilt sensor to disable
// @see grid:tilt
// @function grid_tilt_disable
fn grid_tilt_disable(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const sensor = @intCast(u8, l.checkInteger(2) - 1);
    md.tilt_set(sensor, 0);
    return 0;
}

/// sets arc led.
// users should use `arc:led` instead
// @param md opaque pointer to monome device
// @param ring arc ring (1-based)
// @param led arc led (1-based)
// @param val led brightness (0-15)
// @see arc:led
// @function arc_set_led
fn arc_set_led(l: *Lua) i32 {
    check_num_args(l, 4);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const ring = @intCast(u8, l.checkInteger(2) - 1);
    const led = @intCast(u8, l.checkInteger(3) - 1);
    const val = @intCast(u8, l.checkInteger(4));
    md.arc_set_led(ring, led, val);
    l.setTop(0);
    return 0;
}

/// sets all arc leds.
// users should use `arc:all` instead
// @param md opaque pointser to monome device
// @param val led brightness (0-15)
// @see arc:all
// @function arc_all_led
fn arc_all_led(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const val = @intCast(u8, l.checkInteger(2));
    md.grid_all_led(val);
    l.setTop(0);
    return 0;
}

/// send dirty quads to monome device.
// users should use `grid:refresh` or `arc:refresh` instead
// @param md opaque pointer to monome device
// @see arc:refresh
// @see grid:refresh
// @function monome_refresh
fn monome_refresh(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    md.refresh();
    l.setTop(0);
    return 0;
}

/// sets maximum led brightness.
// users should use `grid:intensity` or `arc:intensity` instead
// @param md opaque pointer to monome device
// @param level maximum brightness level
// @see arc:intensity
// @see grid:intensity
// @function monome_intensity
fn monome_intensity(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Monome, 1) catch unreachable;
    const level = @intCast(u8, l.checkInteger(2));
    md.intensity(level);
    l.setTop(0);
    return 0;
}

/// refreshes the screen.
// users should use `screen.redraw` instead
// @see screen.refresh
// @function screen_refresh
fn screen_refresh(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.refresh();
    return 0;
}

/// draws a single pixel.
// users should use `screen.pixel` instead
// @param x x-coordinate (1-based)
// @param y y-coordinate (1-based)
// @see screen:pixel
// @function screen_pixel
fn screen_pixel(l: *Lua) i32 {
    check_num_args(l, 2);
    const x = @intCast(i32, l.checkInteger(1)) - 1;
    const y = @intCast(i32, l.checkInteger(2)) - 1;
    screen.pixel(x, y);
    l.setTop(0);
    return 0;
}

/// draws a line.
// users should use `screen.line` instead
// @param ax initial x-coordinate (1-based)
// @param ay initial y-coordinate (1-based)
// @param bx terminal x-coordinate (1-based)
// @param by terminal y-coordinate (1-based)
// @see screen:line
// @function screen_line
fn screen_line(l: *Lua) i32 {
    check_num_args(l, 4);
    const ax = @intCast(i32, l.checkInteger(1)) - 1;
    const ay = @intCast(i32, l.checkInteger(2)) - 1;
    const bx = @intCast(i32, l.checkInteger(3)) - 1;
    const by = @intCast(i32, l.checkInteger(4)) - 1;
    screen.line(ax, ay, bx, by);
    l.setTop(0);
    return 0;
}

/// draws a rectangle.
// users should use `screen.rect` instead
// @param x upper-left x-coordinate (1-based)
// @param y upper-left x-coordinate (1-based)
// @param w width in pixels
// @param h height in pixels
// @see screen:rect
// @function screen_rect
fn screen_rect(l: *Lua) i32 {
    check_num_args(l, 4);
    const x = @intCast(i32, l.checkInteger(1)) - 1;
    const y = @intCast(i32, l.checkInteger(2)) - 1;
    const w = @intCast(i32, l.checkInteger(3));
    const h = @intCast(i32, l.checkInteger(4));
    screen.rect(x, y, w, h);
    l.setTop(0);
    return 0;
}

/// draws a filled rectangle.
// users should use `screen.rect` instead
// @param x upper-left x-coordinate (1-based)
// @param y upper-left x-coordinate (1-based)
// @param w width in pixels
// @param h height in pixels
// @see screen:rect
// @function screen_rect_fill
fn screen_rect_fill(l: *Lua) i32 {
    check_num_args(l, 4);
    const x = @intCast(i32, l.checkInteger(1)) - 1;
    const y = @intCast(i32, l.checkInteger(2)) - 1;
    const w = @intCast(i32, l.checkInteger(3));
    const h = @intCast(i32, l.checkInteger(4));
    screen.rect_fill(x, y, w, h);
    l.setTop(0);
    return 0;
}

/// draws text to the screen.
// users should use `screen.text` instead
// @param x upper-left x-coordinate (1-based)
// @param y upper-left y-coordinate (1-based)
// @param words text to draw to the screen
// @see screen:text
// @function screen_text
fn screen_text(l: *Lua) i32 {
    check_num_args(l, 3);
    const x = @intCast(i32, l.checkInteger(1)) - 1;
    const y = @intCast(i32, l.checkInteger(2)) - 1;
    const words = l.checkString(3);
    screen.text(x, y, std.mem.span(words));
    l.setTop(0);
    return 0;
}

/// sets screen color.
// users should use `screen.color` instead
// @param r red value (0-255)
// @param g green value (0-255)
// @param b blue value (0-255)
// @param a alpha value (0-255), defaults to 255
// @see screen:color
// @function screen_color
fn screen_color(l: *Lua) i32 {
    check_num_args(l, 4);
    const r = @intCast(u8, l.checkInteger(1));
    const g = @intCast(u8, l.checkInteger(2));
    const b = @intCast(u8, l.checkInteger(3));
    const a = @intCast(u8, l.checkInteger(4));
    screen.color(r, g, b, a);
    l.setTop(0);
    return 0;
}

/// clears the screen.
// users should use `screen.clear` instead
// @see screen.clear
// @function screen_clear
fn screen_clear(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.clear();
    return 0;
}

/// sets which screen to draw to.
// users should use `screen.set` instead
// @see screen.set
// @function screen_set
fn screen_set(l: *Lua) i32 {
    check_num_args(l, 1);
    const value = @intCast(usize, l.checkInteger(1)) - 1;
    if (value > 1 or value < 0) return 0;
    screen.set(value);
    return 0;
}

/// unhides the params window
// @function screen_show
fn screen_show(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.show(1);
    return 0;
}

/// returns the size of the current window
// @function screen_get_size
fn screen_get_size(l: *Lua) i32 {
    check_num_args(l, 0);
    const ret = screen.get_size();
    l.pushInteger(ret.w);
    l.pushInteger(ret.h);
    return 2;
}

/// returns the size in pixels of the given text.
// users should use `screen.get_text_size` instead
// @see screen.get_text_size
// @function screen_get_text_size
fn screen_get_text_size(l: *Lua) i32 {
    check_num_args(l, 1);
    const str = l.checkString(1);
    const ret = screen.get_text_size(str);
    l.pushInteger(ret.w);
    l.pushInteger(ret.h);
    return 2;
}

/// starts a new metro.
// users should use `metro:start` instead
// @param idx metro id (1-36)
// @param seconds float time at which to repeat
// @param count stage at which to stop
// @param stage stage at which to start
// @see metro:start
// @function metro_start
fn metro_start(l: *Lua) i32 {
    check_num_args(l, 4);
    const idx = @intCast(u8, l.checkInteger(1) - 1);
    const seconds = l.checkNumber(2);
    const count = l.checkInteger(3);
    const stage = l.checkInteger(4);
    metro.start(idx, seconds, count, stage) catch unreachable;
    l.setTop(0);
    return 0;
}

/// stops a metro.
// users should use `metro:stop` instead
// @param idx metro id (1-36)
// @see metro:stop
// @function metro_stop
fn metro_stop(l: *Lua) i32 {
    check_num_args(l, 1);
    const idx = @intCast(u8, l.checkInteger(1) - 1);
    metro.stop(idx) catch unreachable;
    l.setTop(0);
    return 0;
}

/// set repetition time for a metro.
// users can use the `time` field on a metro instead.
// @param idx metro id (1-36)
// @param seconds new period (float)
// @function metro_set_time
fn metro_set_time(l: *Lua) i32 {
    check_num_args(l, 2);
    const idx = @intCast(u8, l.checkInteger(1) - 1);
    const seconds = l.checkNumber(2);
    metro.set_period(idx, seconds) catch unreachable;
    l.setTop(0);
    return 0;
}

/// outputs midi data to device.
// users should use `midi:send` instead
// @param dev opaque pointer to midi device
// @param bytes table of small integers to write
// @see midi:send
// @function midi_write
fn midi_write(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const dev = l.toUserdata(midi.Device, 1) catch unreachable;
    l.checkType(2, ziglua.LuaType.table);
    const len = l.rawLen(2);
    var i: c_longlong = 1;
    var msg = allocator.allocSentinel(u8, @intCast(usize, len), 0) catch |err| {
        if (err == error.OutOfMemory) std.debug.print("out of memory!\n", .{});
        return 0;
    };
    while (i <= len) : (i += 1) {
        l.pushInteger(i);
        _ = l.getTable(2);
        msg[@intCast(usize, i - 1)] = @intCast(u8, l.toInteger(-1) catch unreachable);
    }
    midi.Device.Guts.output.write(dev, msg);
    allocator.free(msg);
    l.setTop(0);
    return 0;
}

/// returns current tempo.
// users should use `clock.get_tempo` instead
// @return bpm
// @see clock.get_tempo
// @function clock_get_tempo
fn clock_get_tempo(l: *Lua) i32 {
    check_num_args(l, 0);
    const bpm = clock.get_tempo();
    l.pushNumber(bpm);
    return 1;
}

/// returns current beat since the clock was last reset.
// users should use `clock.get_beats` instead
// @return beats
// @see clock.get_beats
// @function clock_get_beats
fn clock_get_beats(l: *Lua) i32 {
    const beats = clock.get_beats();
    l.pushNumber(beats);
    return 1;
}

/// cancels coroutine.
// users should use `clock.cancel` instead
// @param idx id of coroutine to cancel
// @see clock.cancel
// @function clock_cancel
fn clock_cancel(l: *Lua) i32 {
    check_num_args(l, 1);
    const idx = l.checkInteger(1);
    l.setTop(0);
    if (idx < 0 or idx > 100) return 0;
    clock.cancel(@intCast(u8, idx));
    return 0;
}

/// resumes coroutine.
// @param id coroutine id (1-100);
// @param co coroutine corresponding to id
// @param ... args passed to `coroutine.resume`.
// @see clock.run
// @function clock_run
fn clock_resume(l: *Lua) i32 {
    const num_args = l.getTop();
    if (num_args < 2) return 0;
    const idx = l.checkInteger(1);
    var co = l.toThread(2) catch unreachable;
    l.pop(2);
    return do_resume(&co, idx);
}

/// resets lua VM.
// @function reset_lvm
fn reset_lvm(l: *Lua) i32 {
    check_num_args(l, 0);
    events.post(.{
        .Reset_LVM = {},
    });
    l.setTop(0);
    return 0;
}

/// quits seamstress
// @function quit_lvm
fn quit_lvm(l: *Lua) i32 {
    check_num_args(l, 0);
    events.post(.{
        .Quit = {},
    });
    l.setTop(0);
    return 0;
}

fn check_num_args(l: *Lua, n: i8) void {
    if (l.getTop() != n) {
        l.raiseErrorStr("error: requires {d} arguments", .{n});
    }
}

inline fn push_lua_func(field: [:0]const u8, func: [:0]const u8) !void {
    _ = try lvm.getGlobal("_seamstress");
    _ = lvm.getField(-1, field);
    lvm.remove(-2);
    _ = lvm.getField(-1, func);
    lvm.remove(-2);
}

pub fn exec_code_line(line: [:0]const u8) !void {
    try handle_line(&lvm, line);
}

pub fn osc_event(
    from_host: []const u8,
    from_port: []const u8,
    path: []const u8,
    msg: []osc.Lo_Arg,
) !void {
    try push_lua_func("osc", "event");
    var path_copy = try allocator.allocSentinel(u8, path.len, 0);
    std.mem.copyForwards(u8, path_copy, path);
    _ = lvm.pushString(path_copy);
    lvm.createTable(@intCast(i32, msg.len), 0);
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        switch (msg[i]) {
            .Lo_Int32 => |a| lvm.pushInteger(a),
            .Lo_Float => |a| lvm.pushNumber(a),
            .Lo_String => |a| {
                _ = lvm.pushString(a);
            },
            .Lo_Blob => |a| {
                var ptr = @ptrCast([*]u8, a.dataptr.?);
                var len: usize = 0;
                _ = lvm.pushBytes(ptr[0..len]);
            },
            .Lo_Int64 => |a| lvm.pushInteger(a),
            .Lo_Double => |a| lvm.pushNumber(a),
            .Lo_Symbol => |a| _ = lvm.pushString(a),
            .Lo_Midi => |a| _ = lvm.pushBytes(&a),
            .Lo_True => |a| {
                _ = a;
                lvm.pushBoolean(true);
            },
            .Lo_False => |a| {
                _ = a;
                lvm.pushBoolean(false);
            },
            .Lo_Nil => |a| {
                _ = a;
                lvm.pushNil();
            },
            .Lo_Infinitum => |a| {
                _ = a;
                lvm.pushNumber(std.math.inf(f64));
            },
        }
        lvm.rawSetIndex(-2, @intCast(c_longlong, i + 1));
    }

    lvm.createTable(2, 0);
    var host_copy = try allocator.allocSentinel(u8, from_host.len, 0);
    std.mem.copyForwards(u8, host_copy, from_host);
    _ = lvm.pushString(host_copy);
    lvm.rawSetIndex(-2, 1);
    var port_copy = try allocator.allocSentinel(u8, from_port.len, 0);
    std.mem.copyForwards(u8, port_copy, from_port);
    _ = lvm.pushString(port_copy);
    lvm.rawSetIndex(-2, 2);

    // report(lvm, docall(lvm, 3, 0));
}

pub fn reset_lua() !void {
    deinit();
    try init(config_file, allocator);
    try startup(script_file);
}

pub fn monome_add(dev: *monome.Monome) !void {
    const id = dev.id;
    const port = dev.name orelse return error.Fail;
    const name = switch (dev.m_type) {
        .Grid => "monome grid",
        .Arc => "monome arc",
    };
    try push_lua_func("monome", "add");
    lvm.pushInteger(@intCast(i64, id + 1));
    var port_copy = try allocator.allocSentinel(u8, port.len, 0);
    defer allocator.free(port_copy);
    std.mem.copyForwards(u8, port_copy, port);
    _ = lvm.pushString(port_copy);
    _ = lvm.pushString(name);
    lvm.pushLightUserdata(dev);
    try docall(&lvm, 4, 0);
}

pub fn monome_remove(id: usize) !void {
    try push_lua_func("monome", "remove");
    lvm.pushInteger(@intCast(i64, id + 1));
    try docall(&lvm, 1, 0);
}

pub fn grid_key(id: usize, x: i32, y: i32, state: i32) !void {
    try push_lua_func("grid", "key");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(x + 1);
    lvm.pushInteger(y + 1);
    lvm.pushInteger(state);
    try docall(&lvm, 4, 0);
}

pub fn grid_tilt(id: usize, sensor: i32, x: i32, y: i32, z: i32) !void {
    try push_lua_func("grid", "tilt");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(sensor + 1);
    lvm.pushInteger(x + 1);
    lvm.pushInteger(y + 1);
    lvm.pushInteger(z + 1);
    try docall(&lvm, 5, 0);
}

pub fn arc_delta(id: usize, ring: i32, delta: i32) !void {
    try push_lua_func("arc", "delta");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(ring + 1);
    lvm.pushInteger(delta);
    try docall(&lvm, 3, 0);
}

pub fn arc_key(id: usize, ring: i32, state: i32) !void {
    try push_lua_func("arc", "delta");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(ring + 1);
    lvm.pushInteger(state);
    try docall(&lvm, 3, 0);
}

pub fn screen_key(sym: i32, mod: u16, repeat: bool, state: bool, window: usize) !void {
    try push_lua_func("screen", "key");
    lvm.pushInteger(sym);
    lvm.pushInteger(mod);
    lvm.pushBoolean(repeat);
    lvm.pushInteger(if (state) 1 else 0);
    lvm.pushInteger(@intCast(c_longlong, window));
    try docall(&lvm, 5, 0);
}

pub fn screen_mouse(x: f64, y: f64, window: usize) !void {
    try push_lua_func("screen", "mouse");
    lvm.pushNumber(x + 1);
    lvm.pushNumber(y + 1);
    lvm.pushInteger(@intCast(c_longlong, window));
    try docall(&lvm, 3, 0);
}

pub fn screen_click(x: f64, y: f64, state: bool, button: u8, window: usize) !void {
    try push_lua_func("screen", "click");
    lvm.pushNumber(x + 1);
    lvm.pushNumber(y + 1);
    lvm.pushInteger(if (state) 1 else 0);
    lvm.pushInteger(button);
    lvm.pushInteger(@intCast(c_longlong, window));
    try docall(&lvm, 5, 0);
}

pub fn screen_resized(w: i32, h: i32, window: usize) !void {
    try push_lua_func("screen", "resized");
    lvm.pushInteger(w);
    lvm.pushInteger(h);
    lvm.pushInteger(@intCast(c_longlong, window));
    try docall(&lvm, 3, 0);
}

pub fn metro_event(id: u8, stage: i64) !void {
    try push_lua_func("metro", "event");
    lvm.pushInteger(id + 1);
    lvm.pushInteger(stage);
    try docall(&lvm, 2, 0);
}

pub fn midi_add(dev: *midi.Device) !void {
    try push_lua_func("midi", "add");
    _ = lvm.pushString(dev.name.?);
    switch (dev.guts) {
        midi.Dev_t.Input => lvm.pushBoolean(true),
        midi.Dev_t.Output => lvm.pushBoolean(false),
    }
    lvm.pushInteger(dev.id + 1);
    lvm.pushLightUserdata(dev);
    try docall(&lvm, 4, 0);
}

pub fn midi_remove(dev_type: midi.Dev_t, id: u32) !void {
    try push_lua_func("midi", "remove");
    switch (dev_type) {
        midi.Dev_t.Input => lvm.pushBoolean(true),
        midi.Dev_t.Output => lvm.pushBoolean(false),
    }
    lvm.pushInteger(id + 1);
    try docall(&lvm, 2, 0);
}

pub fn midi_event(id: u32, timestamp: f64, bytes: []const u8) !void {
    try push_lua_func("midi", "event");
    lvm.pushInteger(id + 1);
    lvm.pushNumber(timestamp);
    lvm.createTable(@intCast(i32, bytes.len), 0);
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        lvm.pushInteger(bytes[i]);
        lvm.rawSetIndex(-2, @intCast(c_longlong, i + 1));
    }
    try docall(&lvm, 3, 0);
}

// outward-facing clock resume
pub fn resume_clock(idx: u8) !void {
    const i = idx + 1;
    _ = try lvm.getGlobal("_seamstress");
    _ = lvm.getField(-1, "clock");
    _ = lvm.getField(-1, "threads");
    _ = lvm.getIndex(-1, i);
    var thread = try lvm.toThread(-1);
    lvm.pop(4);
    _ = do_resume(&thread, i);
}

fn do_resume(l: *Lua, idx: c_longlong) i32 {
    var top: i32 = 0;
    const status = l.resumeThread(null, l.getTop() - 1, &top) catch {
        _ = message_handler(l);
        lua_print(l) catch {
            std.debug.print("couldn't print error!\n", .{});
        };
        l.setTop(0);
        return 0;
    };
    switch (status) {
        ziglua.ResumeStatus.ok => {
            clock.cancel(@intCast(u8, idx));
            return top;
        },
        ziglua.ResumeStatus.yield => {
            if (top < 2) l.raiseErrorStr("error: clock.sleep/sync requires at least 1 argument", .{});
            const sleep_type = l.checkInteger(1);
            l.pop(1);
            switch (sleep_type) {
                0 => {
                    const seconds = l.checkNumber(1);
                    l.pop(1);
                    clock.schedule_sleep(@intCast(u8, idx - 1), seconds);
                },
                1 => {
                    const beats = l.checkNumber(1);
                    l.pop(1);
                    const offset = if (top >= 3) blk: {
                        const val = l.checkNumber(1);
                        l.pop(1);
                        break :blk val;
                    } else 0;
                    clock.schedule_sync(@intCast(u8, idx - 1), beats, offset);
                },
                else => {
                    l.raiseErrorStr("expected CLOCK_SCHEDULE_SLEEP or CLOCK_SCHEDULE_SYNC, got {d}", .{sleep_type});
                    return 1;
                },
            }
        },
    }
    return 0;
}

pub fn clock_transport(ev_type: clock.Transport) !void {
    switch (ev_type) {
        clock.Transport.Start => try push_lua_func("transport", "start"),
        clock.Transport.Stop => try push_lua_func("transport", "stop"),
        clock.Transport.Reset => try push_lua_func("transport", "reset"),
    }
    try docall(&lvm, 0, 0);
}

// -------------------------------------------------------
// lua interpreter

fn lua_print(l: *Lua) !void {
    const n = l.getTop();
    l.checkStackErr(1, "too many results to print");
    _ = try l.getGlobal("print");
    l.insert(1);
    l.call(n, 0);
}

fn run_code(code: [:0]const u8) !void {
    try dostring(&lvm, code, "s_run_code");
}

fn dostring(l: *Lua, str: [:0]const u8, name: [:0]const u8) !void {
    try l.loadBuffer(str, name, ziglua.Mode.text);
    try docall(l, 0, 0);
}

var save_buf: ?[]u8 = null;

fn save_statement_buffer(buf: []u8) !void {
    if (save_buf != null) {
        allocator.free(save_buf.?);
    }
    save_buf = try allocator.alloc(u8, buf.len);
    std.mem.copyForwards(u8, save_buf.?, buf);
}

fn clear_statement_buffer() void {
    if (save_buf == null) {
        return;
    }
    allocator.free(save_buf.?);
    save_buf = null;
}

fn message_handler(l: *Lua) i32 {
    if (l.typeOf(1) == ziglua.LuaType.string) {
        const msg = l.toString(1) catch unreachable;
        l.traceback(l, std.mem.span(msg), 1);
        return 1;
    } else {
        l.callMeta(1, "__tostring") catch {
            const msg = std.fmt.allocPrint(allocator, "(error object is a {s} value)", .{l.typeName(l.typeOf(1))}) catch {
                _ = l.pushString("(error object is not a string!)");
                return 1;
            };
            defer allocator.free(msg);
            var realmsg = allocator.allocSentinel(u8, msg.len, 0) catch {
                _ = l.pushString("(error object is not a string!)");
                return 1;
            };
            defer allocator.free(realmsg);
            std.mem.copyForwards(u8, realmsg, msg);
            _ = l.pushString(realmsg[0..msg.len :0]);
        };
        return 1;
    }
}

fn docall(l: *Lua, nargs: i32, nres: i32) !void {
    const base = l.getTop() - nargs;
    l.pushFunction(ziglua.wrap(message_handler));
    l.insert(base);
    l.protectedCall(nargs, nres, base) catch {
        const msg = try l.toString(-1);
        std.debug.print("{s}\n", .{msg});
        l.pop(1);
    };
    l.remove(base);
}

fn handle_line(l: *Lua, line: [:0]const u8) !void {
    l.setTop(0);
    _ = l.pushString(line);
    if (save_buf != null) {
        statement(l) catch |err| {
            if (err != error.Syntax) return err;
            l.setTop(0);
            std.debug.print(">... ", .{});
            return;
        };
    } else {
        add_return(l) catch |err| {
            if (err != error.Syntax) return err;
            statement(l) catch |err2| {
                if (err2 != error.Syntax) return err2;
                l.setTop(0);
                std.debug.print(">... ", .{});
                return;
            };
        };
    }
    try docall(l, 0, ziglua.mult_return);
    if (l.getTop() == 0) {
        std.debug.print("> ", .{});
    } else {
        try lua_print(l);
        std.debug.print("> ", .{});
    }
    l.setTop(0);
}

fn statement(l: *Lua) !void {
    const line = try l.toString(1);
    var buf: []u8 = undefined;
    if (save_buf == null) {
        buf = try std.fmt.allocPrint(allocator, "{s}", .{line});
    } else {
        buf = try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ save_buf.?, line });
    }
    defer allocator.free(buf);
    l.loadBuffer(buf, "=stdin", ziglua.Mode.text) catch |err| {
        if (err != error.Syntax) return err;
        const msg = std.mem.span(try l.toString(-1));
        const eofmark = "<eof>";
        if ((msg.len >= eofmark.len) and std.mem.eql(u8, eofmark, msg[(msg.len - eofmark.len)..msg.len])) {
            l.pop(1);
            try save_statement_buffer(buf);
        } else {
            clear_statement_buffer();
            l.remove(-2);
        }
        return err;
    };
    clear_statement_buffer();
    l.remove(1);
}

fn add_return(l: *Lua) !void {
    const line = try l.toString(-1);
    const retline = try std.fmt.allocPrint(allocator, "return {s}", .{line});
    defer allocator.free(retline);
    l.loadBuffer(retline, "=stdin", ziglua.Mode.text) catch |err| {
        l.pop(1);
        return err;
    };
    l.remove(-2);
}
