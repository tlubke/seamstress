const std = @import("std");
const events = @import("events.zig");
const c = @import("c_includes.zig").imported;

var WIDTH: u16 = 256;
var HEIGHT: u16 = 128;
var ZOOM: u16 = 4;

var window: *c.SDL_Window = undefined;
var render: *c.SDL_Renderer = undefined;
var font: *c.TTF_Font = undefined;
var thread: std.Thread = undefined;
var quit = false;

pub fn redraw() void {
    c.SDL_RenderPresent(render);
}

pub fn clear() void {
    sdl_call(c.SDL_SetRenderDrawColor(render, 0, 0, 0, 255), "screen.clear()");
    sdl_call(c.SDL_RenderClear(render), "screen.clear()");
}

pub fn color(r: u8, g: u8, b: u8, a: u8) void {
    sdl_call(c.SDL_SetRenderDrawColor(render, r, g, b, a), "screen.color()");
}

pub fn pixel(x: i32, y: i32) void {
    sdl_call(c.SDL_RenderDrawPoint(render, x, y), "screen.pixel()");
}

pub fn line(ax: i32, ay: i32, bx: i32, by: i32) void {
    sdl_call(c.SDL_RenderDrawLine(render, ax, ay, bx, by), "screen.line()");
}

pub fn rect(x: i32, y: i32, w: i32, h: i32) void {
    var r = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
    sdl_call(c.SDL_RenderDrawRect(render, &r), "screen.rect()");
}

pub fn rect_fill(x: i32, y: i32, w: i32, h: i32) void {
    var r = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
    sdl_call(c.SDL_RenderFillRect(render, &r), "screen.rect_fill()");
}

pub fn text(x: i32, y: i32, words: [:0]const u8) void {
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    _ = c.SDL_GetRenderDrawColor(render, &r, &g, &b, &a);
    var col = c.SDL_Color{ .r = r, .g = g, .b = b, .a = a };
    var text_surf = c.TTF_RenderText_Solid(font, words, col);
    var texture = c.SDL_CreateTextureFromSurface(render, text_surf);
    const rectangle = c.SDL_Rect{ .x = x, .y = y, .w = text_surf.*.w, .h = text_surf.*.h };
    sdl_call(c.SDL_RenderCopy(render, texture, null, &rectangle), "screen.text()");
    c.SDL_DestroyTexture(texture);
    c.SDL_FreeSurface(text_surf);
}

pub fn init(width: u16, height: u16) !void {
    HEIGHT = height;
    WIDTH = width;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("screen.init(): {s}\n", .{c.SDL_GetError()});
        return;
    }

    if (c.TTF_Init() < 0) {
        std.debug.print("screen.init(): {s}\n", .{c.TTF_GetError()});
        return;
    }

    var f = c.TTF_OpenFont("/usr/local/share/seamstress/resources/04b03.ttf", 8);
    font = f orelse {
        std.debug.print("screen.init(): {s}\n", .{c.TTF_GetError()});
        return;
    };

    var w = c.SDL_CreateWindow("seamstress", //
        c.SDL_WINDOWPOS_UNDEFINED, //
        c.SDL_WINDOWPOS_UNDEFINED, //
        WIDTH * ZOOM, //
        HEIGHT * ZOOM, //
        c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE);
    window = w orelse {
        std.debug.print("screen.init(): {s}\n", .{c.SDL_GetError()});
        return;
    };

    var r = c.SDL_CreateRenderer(window, 0, 0);
    render = r orelse {
        std.debug.print("screen.init(): {s}\n", .{c.SDL_GetError()});
        return;
    };

    c.SDL_SetWindowMinimumSize(window, WIDTH, HEIGHT);
    window_rect();
    clear();
    thread = try std.Thread.spawn(.{}, loop, .{});
}

fn window_rect() void {
    var xsize: i32 = undefined;
    var ysize: i32 = undefined;
    var xzoom: u16 = 1;
    var yzoom: u16 = 1;
    c.SDL_GetWindowSize(window, &xsize, &ysize);
    while ((1 + xzoom) * WIDTH <= xsize) : (xzoom += 1) {}
    while ((1 + yzoom) * HEIGHT <= ysize) : (yzoom += 1) {}
    ZOOM = if (xzoom < yzoom) xzoom else yzoom;
    sdl_call(c.SDL_RenderSetScale(render, @intToFloat(f32, ZOOM), @intToFloat(f32, ZOOM)), "window_rect()");
}

pub fn check() !void {
    var event: *events.Data = undefined;
    var ev: c.SDL_Event = undefined;
    while (c.SDL_PollEvent(&ev) != 0) {
        switch (ev.type) {
            c.SDL_KEYDOWN => {
                event = try events.new(events.Event.Screen_Key);
                event.Screen_Key.scancode = ev.key.keysym.sym;
                try events.post(event);
            },
            c.SDL_QUIT => {
                event = try events.new(events.Event.Quit);
                try events.post(event);
                quit = true;
            },
            c.SDL_WINDOWEVENT => {
                switch (ev.window.event) {
                    c.SDL_WINDOWEVENT_EXPOSED => redraw(),
                    c.SDL_WINDOWEVENT_RESIZED => {
                        window_rect();
                        redraw();
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
}

pub fn deinit() void {
    quit = true;
    thread.join();
    c.TTF_CloseFont(font);
    c.SDL_DestroyRenderer(render);
    c.SDL_DestroyWindow(window);
    c.TTF_Quit();
    c.SDL_Quit();
}

fn loop() !void {
    while (!quit) {
        var event = try events.new(events.Event.Screen_Check);
        try events.post(event);
        std.time.sleep(20000000);
    }
}

fn sdl_call(err: c_int, name: []const u8) void {
    if (err < -1) {
        std.debug.print("{s}: error: {s}", .{ name, c.SDL_GetError() });
    }
}
