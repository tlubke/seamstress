const std = @import("std");
const args = @import("args.zig");
const osc = @import("osc.zig");
const monome = @import("monome.zig");
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

    register_seamstress("screen_redraw", ziglua.wrap(screen_redraw));
    register_seamstress("screen_pixel", ziglua.wrap(screen_pixel));
    register_seamstress("screen_line", ziglua.wrap(screen_line));
    register_seamstress("screen_rect", ziglua.wrap(screen_rect));
    register_seamstress("screen_rect_fill", ziglua.wrap(screen_rect_fill));
    register_seamstress("screen_text", ziglua.wrap(screen_text));
    register_seamstress("screen_color", ziglua.wrap(screen_color));
    register_seamstress("screen_clear", ziglua.wrap(screen_clear));

    register_seamstress("metro_start", ziglua.wrap(metro_start));
    register_seamstress("metro_stop", ziglua.wrap(metro_stop));
    register_seamstress("metro_set_time", ziglua.wrap(metro_set_time));

    register_seamstress("reset_lvm", ziglua.wrap(reset_lvm));

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
    std.debug.print("shutting down lua vm\n", .{});
    lvm.deinit();
}

pub fn startup(script: [:0]const u8) !void {
    script_file = script;
    _ = lvm.pushString(script_file);
    _ = try lvm.getGlobal("_startup");
    lvm.insert(1);
    try docall(&lvm, 1, 0);
}

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
        l.pushNumber(@intToFloat(f64, i));
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

fn grid_set_led(l: *Lua) i32 {
    check_num_args(l, 4);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md: *monome.Device = l.toUserdata(monome.Device, 1) catch unreachable;
    const x = @intCast(u8, l.checkInteger(2) - 1);
    const y = @intCast(u8, l.checkInteger(3) - 1);
    const val = @intCast(u8, l.checkInteger(4));
    md.grid_set_led(x, y, val);
    l.setTop(0);
    return 0;
}

fn grid_all_led(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const val = @intCast(u8, l.checkInteger(2));
    md.grid_all_led(val);
    l.setTop(0);
    return 0;
}

fn grid_rows(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    l.setTop(0);
    l.pushInteger(md.rows);
    return 1;
}

fn grid_cols(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    l.setTop(0);
    l.pushInteger(md.cols);
    return 1;
}

fn grid_set_rotation(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const rotation = @intCast(u8, l.checkInteger(2));
    md.set_rotation(rotation);
    l.setTop(0);
    return 0;
}

fn grid_tilt_enable(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const sensor = @intCast(u8, l.checkInteger(2) - 1);
    md.tilt_enable(sensor);
    return 0;
}

fn grid_tilt_disable(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const sensor = @intCast(u8, l.checkInteger(2) - 1);
    md.tilt_disable(sensor);
    return 0;
}

fn arc_set_led(l: *Lua) i32 {
    check_num_args(l, 4);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const ring = @intCast(u8, l.checkInteger(2) - 1);
    const led = @intCast(u8, l.checkInteger(3) - 1);
    const val = @intCast(u8, l.checkInteger(4));
    md.arc_set_led(ring, led, val);
    l.setTop(0);
    return 0;
}

fn arc_all_led(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const val = @intCast(u8, l.checkInteger(2));
    md.grid_all_led(val);
    l.setTop(0);
    return 0;
}

fn monome_refresh(l: *Lua) i32 {
    check_num_args(l, 1);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    md.refresh();
    l.setTop(0);
    return 0;
}

fn monome_intensity(l: *Lua) i32 {
    check_num_args(l, 2);
    l.checkType(1, ziglua.LuaType.light_userdata);
    const md = l.toUserdata(monome.Device, 1) catch unreachable;
    const level = @intCast(u8, l.checkInteger(2));
    md.intensity(level);
    l.setTop(0);
    return 0;
}

fn screen_redraw(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.redraw();
    return 0;
}

fn screen_pixel(l: *Lua) i32 {
    check_num_args(l, 2);
    const x = @intCast(i32, l.checkInteger(1));
    const y = @intCast(i32, l.checkInteger(2));
    screen.pixel(x, y);
    l.setTop(0);
    return 0;
}

fn screen_line(l: *Lua) i32 {
    check_num_args(l, 4);
    const ax = @intCast(i32, l.checkInteger(1));
    const ay = @intCast(i32, l.checkInteger(2));
    const bx = @intCast(i32, l.checkInteger(3));
    const by = @intCast(i32, l.checkInteger(4));
    screen.line(ax, ay, bx, by);
    l.setTop(0);
    return 0;
}

fn screen_rect(l: *Lua) i32 {
    check_num_args(l, 4);
    const x = @intCast(i32, l.checkInteger(1));
    const y = @intCast(i32, l.checkInteger(2));
    const w = @intCast(i32, l.checkInteger(3));
    const h = @intCast(i32, l.checkInteger(4));
    screen.rect(x, y, w, h);
    l.setTop(0);
    return 0;
}

fn screen_rect_fill(l: *Lua) i32 {
    check_num_args(l, 4);
    const x = @intCast(i32, l.checkInteger(1));
    const y = @intCast(i32, l.checkInteger(2));
    const w = @intCast(i32, l.checkInteger(3));
    const h = @intCast(i32, l.checkInteger(4));
    screen.rect_fill(x, y, w, h);
    l.setTop(0);
    return 0;
}

fn screen_text(l: *Lua) i32 {
    check_num_args(l, 3);
    const x = @intCast(i32, l.checkInteger(1));
    const y = @intCast(i32, l.checkInteger(2));
    const words = l.checkString(3);
    screen.text(x, y, std.mem.span(words));
    l.setTop(0);
    return 0;
}

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

fn screen_clear(l: *Lua) i32 {
    check_num_args(l, 0);
    screen.clear();
    return 0;
}

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

fn metro_stop(l: *Lua) i32 {
    check_num_args(l, 1);
    const idx = @intCast(u8, l.checkInteger(1) - 1);
    metro.stop(idx) catch unreachable;
    l.setTop(0);
    return 0;
}

fn metro_set_time(l: *Lua) i32 {
    check_num_args(l, 2);
    const idx = @intCast(u8, l.checkInteger(1) - 1);
    const seconds = l.checkNumber(2);
    metro.set_period(idx, seconds) catch unreachable;
    l.setTop(0);
    return 0;
}

fn reset_lvm(l: *Lua) i32 {
    check_num_args(l, 0);
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

pub fn osc_event(from_host: [:0]const u8, from_port: [:0]const u8, path: [:0]const u8, msg: []osc.Lo_Arg) !void {
    try push_lua_func("osc", "event");
    _ = lvm.pushString(path);
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
                _ = a;
                lvm.pushNil();
                // var slice = std.mem.span(@ptrCast(*u8, a.dataptr.?));
                // lvm.pushBytes(slice);
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
    _ = lvm.pushString(from_host);
    lvm.rawSetIndex(-2, 1);
    _ = lvm.pushString(from_port);
    lvm.rawSetIndex(-2, 2);

    // report(lvm, docall(lvm, 3, 0));
}

pub fn reset_lua() !void {
    deinit();
    try init(config_file, allocator);
    try startup(script_file);
}

pub fn monome_add(dev: *monome.Device) !void {
    const id = dev.id;
    const serial = dev.serial;
    const name = dev.name;
    try push_lua_func("monome", "add");
    lvm.pushInteger(@intCast(i64, id + 1));
    var serial_copy = try allocator.allocSentinel(u8, serial.len, 0);
    defer allocator.free(serial_copy);
    std.mem.copyForwards(u8, serial_copy, serial);
    _ = lvm.pushString(serial_copy);
    var name_copy = try allocator.allocSentinel(u8, name.len, 0);
    defer allocator.free(name_copy);
    std.mem.copyForwards(u8, name_copy, name);
    _ = lvm.pushString(name_copy);
    lvm.pushLightUserdata(dev);
    try docall(&lvm, 4, 0);
}

pub fn monome_remove(id: usize) !void {
    try push_lua_func("monome", "remove");
    lvm.pushInteger(@intCast(i64, id + 1));
    try docall(&lvm, 1, 0);
}

pub fn grid_key(id: usize, x: u32, y: u32, state: i2) !void {
    try push_lua_func("grid", "key");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(x + 1);
    lvm.pushInteger(y + 1);
    lvm.pushInteger(state);
    try docall(&lvm, 4, 0);
}

pub fn grid_tilt(id: usize, sensor: u32, x: i32, y: i32, z: i32) !void {
    try push_lua_func("grid", "tilt");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(sensor + 1);
    lvm.pushInteger(x + 1);
    lvm.pushInteger(y + 1);
    lvm.pushInteger(z + 1);
    try docall(&lvm, 5, 0);
}

pub fn arc_delta(id: usize, ring: u32, delta: i32) !void {
    try push_lua_func("arc", "delta");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(ring + 1);
    lvm.pushInteger(delta);
    try docall(&lvm, 3, 0);
}

pub fn arc_key(id: usize, ring: u32, state: i2) !void {
    try push_lua_func("arc", "delta");
    lvm.pushInteger(@intCast(i64, id + 1));
    lvm.pushInteger(ring + 1);
    lvm.pushInteger(state);
    try docall(&lvm, 3, 0);
}

pub fn screen_key(scancode: i32) !void {
    try push_lua_func("screen", "key");
    lvm.pushInteger(scancode);
    try docall(&lvm, 1, 0);
}

pub fn metro_event(id: u8, stage: i64) !void {
    try push_lua_func("metro", "event");
    lvm.pushInteger(id + 1);
    lvm.pushInteger(stage);
    try docall(&lvm, 2, 0);
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
    allocator.free(buf);
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
    add_return(l) catch |err| {
        if (err != error.Syntax) return err;
        statement(l) catch |err2| {
            if (err2 != error.Syntax) return err2;
            l.setTop(0);
            return;
        };
    };
    try docall(l, 0, ziglua.mult_return);
    if (l.getTop() == 0) {
        std.debug.print("<ok>\n", .{});
    } else {
        try lua_print(l);
        std.debug.print("\n", .{});
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
