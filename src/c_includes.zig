const builtin = @import("builtin");
pub const imported = @cImport({
    @cInclude("monome.h");
    @cInclude("lo/lo.h");
    @cInclude("dns_sd.h");
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
    @cInclude("SDL2/SDL_error.h");
    @cInclude("SDL2/SDL_render.h");
    @cInclude("SDL2/SDL_surface.h");
    @cInclude("SDL2/SDL_video.h");
    @cInclude("portmidi.h");
});

pub const os_imported = switch (builtin.target.os.tag) {
    .linux => @cImport({}),
    else => @cImport({
        @cInclude("CoreFoundation/CoreFoundation.h");
        @cInclude("IOKit/IOKitKeys.h");
        @cInclude("IOKit/IOKitLib.h");
        @cInclude("IOKit/IOTypes.h");
        @cInclude("IOKit/usb/IOUSBLib.h");
        @cInclude("IOKit/serial/IOSerialKeys.h");
    }),
};
