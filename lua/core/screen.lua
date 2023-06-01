local Screen = {}
Screen.__index = Screen

function Screen.clear()
	_seamstress.screen_clear()
end

function Screen.redraw()
	_seamstress.screen_redraw()
end

function Screen.color(r, g, b, a)
	_seamstress.screen_color(r, g, b, a or 255)
end

function Screen.pixel(x, y)
	_seamstress.screen_pixel(x, y)
end

function Screen.line(ax, ay, bx, by)
	_seamstress.screen_line(ax, ay, bx, by)
end

function Screen.rect(x, y, w, h)
	_seamstress.screen_rect(x, y, w, h)
end

function Screen.rect_fill(x, y, w, h)
	_seamstress.screen_rect_fill(x, y, w, h)
end

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

function Screen.key(scancode) end

return Screen
