local widget_name = "FlyLog"

local libGUI

-- Return GUI library table
function loadGUI()
	if not libGUI then
		libGUI = loadScript("/WIDGETS/libGUI/libgui.lua")
	end
	return libGUI()
end

local function create(zone, options)
    return loadScript("/WIDGETS/".. widget_name .. "/loadable.lua")(zone, options)
end

local function update(widget, options)
  -- Runs if options are changed from the Widget Settings menu
end

local function background(widget)
  -- Runs periodically only when widget instance is not visible
end

local function refresh(widget, event, touchState)
  -- Runs periodically only when widget instance is visible
  -- If full screen, then event is 0 or event value, otherwise nil
  widget.refresh(event, touchState)
end

return {
  name = widget_name,
  options = {},
  create = create,
  update = update,
  refresh = refresh,
  background = background
}