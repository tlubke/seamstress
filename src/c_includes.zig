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
});
