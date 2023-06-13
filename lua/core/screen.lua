--- screen
-- @module screen
local Screen = {}
Screen.__index = Screen

--- clears the screen.
-- @function screen.clear
function Screen.clear()
	_seamstress.screen_clear()
end

--- redraws the screen; reveals changes.
-- @function screen.redraw
function Screen.redraw()
	_seamstress.screen_redraw()
end

--- sets screen color.
-- @tparam integer r red value (0-255)
-- @tparam integer g green value (0-255)
-- @tparam integer b blue value (0-255)
-- @tparam integer a alpha value (0-255) (default 255)
-- @function screen.color
function Screen.color(r, g, b, a)
	_seamstress.screen_color(r, g, b, a or 255)
end

--- draws a single pixel.
-- @tparam integer x x-coordinate (1-based)
-- @tparam integer y y-coordinate (1-based)
-- @function screen.pixel
function Screen.pixel(x, y)
	_seamstress.screen_pixel(x, y)
end

--- draws a line.
-- @tparam integer ax source x-coordinate (1-based)
-- @tparam integer ay source y-coordinate (1-based)
-- @tparam integer bx target x-coordinate (1-based)
-- @tparam integer by target y-coordinate (1-based)
-- @function screen.line
function Screen.line(ax, ay, bx, by)
	_seamstress.screen_line(ax, ay, bx, by)
end

--- draws a rectangle.
-- @tparam integer x upper-left x-coordinate (1-based)
-- @tparam integer y upper-left y-coordinate (1-based)
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect
function Screen.rect(x, y, w, h)
	_seamstress.screen_rect(x, y, w, h)
end

--- draws a filled-in rectangle.
-- @tparam integer x upper-left x-coordinate (1-based)
-- @tparam integer y upper-left y-coordinate (1-based)
-- @tparam integer w width in pixels
-- @tparam integer h height in pixels
-- @function screen.rect_fill
function Screen.rect_fill(x, y, w, h)
	_seamstress.screen_rect_fill(x, y, w, h)
end

--- draws text to the screen.
-- @tparam integer x upper-left x-coordinate (1-based)
-- @tparam integer y upper-left y-coordinate (1-based)
-- @tparam string text text to draw
-- @function screen.text
function Screen.text(x, y, text)
	_seamstress.screen_text(x, y, text)
end

_seamstress.screen = {
  key = function (scancode)
    if Screen.key ~= nil then
      Screen.key(scancode)
    end
  end
}

--- callback executed when the user types a key into the gui window.
-- @tparam integer scancode ascii scancode
-- @function screen.key
function Screen.key(scancode) end

return Screen
