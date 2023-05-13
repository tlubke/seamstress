local vport = {}

function vport.wrap(method)
	return function(self, ...)
    if self.device then self.device[method](self.device, ...) end
  end
end

return vport
