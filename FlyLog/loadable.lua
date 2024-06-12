--Script information
local NAME = "FlyLog"
local VERSION = "v1"

--Variable
local crsf_field = { "RxBt", "Curr", "Alt", "Capa", "Bat%", "GSpd", "Sats", "1RSS", "2RSS", "RQly", "Hdg", "Ptch", "FM" }
local fport_field = { "VFAS", "Curr", "RPM1", "5250", "Fuel", "EscT", "Tmp1", "RSSI", "TRSS", "TQly", "Hdg", "RxBt", "FM" }
local display_list = { "Battery[V]", "Current[A]", "HSpd[rpm]", "FM:" }
local voltage_list = { "Battery[V]", "Bec[V]" }
local data_format = { "%.1f", "%.1f", "%d", "%s" }
local data_field = {}

--Define
local TELE_ITEMS = 13
local FM_INDEX = 13
local DISP_FM_INDEX = 4
local LOG_INFO_LEN = 22
local LOG_DATA_LEN = 114
local BUTTON_WIDTH = 50
local BUTTON_HEIGHT = 30
local BUTTON_CORNER_RADIUS = 2

--Variable
local model_name = ""
local protocol_type = 0
local value_min_max = {}
local data_hag = { 11, 10 }
local data_ptch = { 12, 4 }
local power_max = { 0, 0 }
local capa_start = 0
local fuel_start = 0
local field_id = {}
local time_os = 0
local ring_data = 0
local sync_fuel_value = 0
local wait_count = 0
local pic_obj
local file_name = ""
local file_path = ""
local file_obj
local log_info = ""
local log_data = {}
local sele_number = 0
local second = { 0, 0, 0 }
local total_second = 0
local hours = 0
local minutes = { 0, 0 }
local seconds = { 0, 0 }
local play_speed = 0

local model_flight_stats = {}
-- local selected_day_index = 1

--Flag
local paint_color_flag = BLACK
local telemetry_value_color_flag
local batter_on_flag
local init_sync_flag
local sync_end_flag
local spoolup_flag
local display_log_flag
local write_en_flag
local sliding_flag
local ring_start_flag
local ring_end_flag
local alternate_flag

local options = {
  { "ValueColor", COLOR,  BLACK },
  { "LabelColor", COLOR,  BLACK },
  { "GridColor", COLOR,  BLACK },
  { "ThrottleChannel",     SOURCE, 215 }, --CH6
  { "LowVoltageValue_x10", VALUE,  216,  0, 550 },
  { "LowFuelValue",        VALUE,  0,    0, 100 },
  { "VoltageDisplayMode",  VALUE,  0,    0, 2 }
}

-- Sorting table
local function spairs(t, order)
  -- collect the keys
  local keys = {}
  for k in pairs(t) do keys[#keys+1] = k end
  -- if order function given, sort by it by passing the table and keys a, b,
  -- otherwise just sort the keys 
  if order then
    table.sort(keys, function(a,b) return order(t, a, b) end)
  else
    table.sort(keys)
  end
  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
        return keys[i], t[keys[i]]
    end
  end
end

--fuel_percentage
local function fuel_percentage(xs, ys, capa, number)
  local color = lcd.RGB(255 - number * 2.55, number * 2.55, 0)
  lcd.drawAnnulus(xs, ys, 65, 70, 0, 360, lcd.RGB(100, 100, 100))
  if number ~= 0 then
      lcd.drawAnnulus(xs, ys, 45, 65, (100 - number) * 3.6, 360, color)
  end
  if number ~= 100 then
      lcd.drawAnnulus(xs, ys, 45, 65, 0, (100 - number) * 3.6, lcd.RGB(220, 220, 220))
  end
  lcd.drawText(xs + 2, ys - 10, string.format("%d%%", number), CENTER + VCENTER + DBLSIZE + telemetry_value_color_flag)
  lcd.drawText(xs, ys + 15, string.format("%dmAh", capa), CENTER + VCENTER + telemetry_value_color_flag)
end

--read_all_model_logs
local function read_all_model_logs(current_model_name)
  local total_flight_time = 0
  local flight_count = 0
  for fname in dir("/WIDGETS/Test/logs/") do
    if string.find(fname, current_model_name) then
      file_obj = io.open("/WIDGETS/Test/logs/" .. fname, "r")
      line = io.read(file_obj, LOG_INFO_LEN + 1)
      
      hours = string.sub(line, 12, 13)
      minutes[2] = string.sub(line, 15, 16)
      seconds[2] = string.sub(line, 18, 19)
    
      total_seconds = tonumber(string.sub(line, 12, 13)) * 3600
      total_seconds = total_seconds + tonumber(string.sub(line, 15, 16)) * 60
      total_seconds = total_seconds + tonumber(string.sub(line, 18, 19))

      current_log_file_flight_count = tonumber(string.sub(line, 21, 22))
      total_flight_time = total_flight_time + total_seconds
      flight_count = flight_count + current_log_file_flight_count

      current_read_count = 0
      log_data[fname] = {
          flight_count = current_log_file_flight_count,
          logs = {}
      }
      while true do
          log_data[fname]["logs"][current_read_count] = io.read(file_obj, LOG_DATA_LEN + 1)
          if #log_data[fname]["logs"][current_read_count] == 0 then
              break
          else
              current_read_count = current_read_count + 1
          end
      end
      io.close(file_obj)
    end
  end
  return {
    total_minutes = string.format("%02d", math.floor(total_flight_time % 3600 / 60)),
    total_seconds = string.format("%02d", total_flight_time % 3600 % 60),
    total_hours = string.format("%02d", math.floor(total_flight_time / 3600)),
    flight_count = flight_count
  }
end

local zone, options = ...
local widget = {
  zone = zone,
  options = options
}

local function widget_create()
  local module = {}
  --Head speed ratio
  --local _, _, major, minor, rev, osname = getVersion()

  --Variable initialization
  sele_number = 1
  for i = 1, #second do
    second[i] = 0
  end
  total_second = 0
  --Flag
  write_en_flag = false
  sliding_flag = false
  ring_start_flag = false
  ring_end_flag = false
  alternate_flag = false

  --Model Name
  model_name = model.getInfo().name

  --Initialize the array
  for i = 1, TELE_ITEMS - 1 do
      value_min_max[i] = { 0, 0, 0 }
  end
  for i = 1, TELE_ITEMS do
      field_id[i] = { 0, 0 }
  end

  --Protocol Type
  module[1] = model.getModule(0) --Internal
  module[2] = model.getModule(1) --External
  protocol_type = 0              --CRSF
  for m = 1, 2 do
    if module[m] ~= nil then
      if module[m].Type == 6 and module[m].protocol == 64 then -- MULTIMODULE D16
        protocol_type = 1                                    -- FPORT
        break
      end
    end
  end

  --Redefine fields
  data_field = protocol_type == 1 and fport_field or crsf_field

  --Get ID
  for k, v in pairs(data_field) do
    local field_info = getFieldInfo(v)
    if field_info ~= nil then
      field_id[k][1] = field_info.id
      field_id[k][2] = true
    else
      field_id[k][1] = 0
      field_id[k][2] = false
    end
  end

  --Loading pic
  pic_obj = Bitmap.open("/WIDGETS/Test/a.png")

  --log
  file_name = '[' .. model_name .. ']' ..
      string.format("%d", getDateTime().year) ..
      string.format("%02d", getDateTime().mon) ..
      string.format("%02d", getDateTime().day) .. ".log"
  file_path = "/WIDGETS/Test/logs/" .. file_name

  local file_info = fstat(file_path)
  local read_count = 1
  if file_info ~= nil then
    if file_info.size > 0 then
      file_obj = io.open(file_path, "r")
      log_info = io.read(file_obj, LOG_INFO_LEN + 1)
      log_data[file_name] = {}
      while true do
        log_data[file_name][read_count] = io.read(file_obj, LOG_DATA_LEN + 1)
        if #log_data[file_name][read_count] == 0 then
          break
        else
          read_count = read_count + 1
        end
      end
      io.close(file_obj)
      hours = string.sub(log_info, 12, 13)
      minutes[2] = string.sub(log_info, 15, 16)
      seconds[2] = string.sub(log_info, 18, 19)
      total_second = tonumber(string.sub(log_info, 12, 13)) * 3600
      total_second = total_second + tonumber(string.sub(log_info, 15, 16)) * 60
      total_second = total_second + tonumber(string.sub(log_info, 18, 19))
    end
  else
    file_obj = io.open(file_path, "w")
    log_info =
        string.format("%d", getDateTime().year) .. '/' ..
        string.format("%02d", getDateTime().mon) .. '/' ..
        string.format("%02d", getDateTime().day) .. '|' ..
        "00:00:00" .. '|' ..
        "00\n"
    io.write(file_obj, log_info)
    io.close(file_obj)
  end
  model_flight_stats = read_all_model_logs(model_name)
end

widget_create()

-- Miscellaneous constants
local HEADER = 40
local WIDTH  = 100
local COL1   = 10
local COL2   = 130
local COL3   = 250
local COL4   = 370
local COL2s  = 120
local TOP    = 44
local ROW    = 28
local HEIGHT = 24

-- The widget table will be returned to the main script
local widget = { }

-- Load the GUI library by calling the global function declared in the main script.
-- As long as LibGUI is on the SD card, any widget can call loadGUI() because it is global.
local libGUI = loadGUI()

-- Instantiate a new GUI object
local gui = libGUI.newGUI()

-- Make a minimize button from a custom element
local custom = gui.custom({ }, LCD_W - 34, 6, 28, 28)

function custom.draw(focused)
  lcd.drawRectangle(LCD_W - 34, 6, 28, 28, libGUI.colors.primary2)
  lcd.drawFilledRectangle(LCD_W - 30, 19, 20, 3, libGUI.colors.primary2)
  if focused then
    custom.drawFocus()
  end
end

function custom.onEvent(event, touchState)
  if event == EVT_VIRTUAL_ENTER then
    lcd.exitFullScreen()
  end
end

-- A timer
-- gui.label(COL1, TOP, WIDTH, HEIGHT, "Timer", BOLD)

local function timerChange(steps, timer)
  if steps < 0 then
    return (math.ceil(timer.value / 60) + steps) * 60
  else
    return (math.floor(timer.value / 60) + steps) * 60
  end
end

-- gui.timer(COL1, TOP + ROW, WIDTH, 1.4 * HEIGHT, 0, timerChange, DBLSIZE + RIGHT)

-- -- A sub-gui
-- gui.label(COL2, TOP, WIDTH, HEIGHT, "Group of elements", BOLD)
-- local subGUI = gui.gui(COL2, TOP + ROW, COL4 + WIDTH - COL3, 2 * ROW + HEIGHT)

-- -- A number that can be edited
-- subGUI.label(0, 0, WIDTH, HEIGHT, "Number:")
-- subGUI.number(COL2s, 0, WIDTH, HEIGHT, 0)

-- -- A drop-down with physical switches
-- subGUI.label(0, ROW, WIDTH, HEIGHT, "Drop-down:")
-- labelDropDown = subGUI.label(0, 2 * ROW, 2 * WIDTH, HEIGHT, "")

-- local dropDownIndices = { }
-- local dropDownItems = { }
-- local lastSwitch = getSwitchIndex(CHAR_TRIM .. "Rl") - 1

-- for i, s in switches(-lastSwitch, lastSwitch) do
--   if i ~= 0 then 
--     local j = #dropDownIndices + 1
--     dropDownIndices[j] = i
--     dropDownItems[j] = s
--   end
-- end

-- local function dropDownChange(dropDown)
--   local i = dropDown.selected
--   labelDropDown.title = "Selected switch: " .. dropDownItems[i] .. " [" .. dropDownIndices[i] .. "]"
-- end

-- local dropDown = subGUI.dropDown(COL2s, ROW, WIDTH, HEIGHT, dropDownItems, #dropDownItems / 2 + 1, dropDownChange)
-- dropDownChange(dropDown)

-- Menu that does nothing
-- gui.label(COL4, TOP, WIDTH, HEIGHT, "Menu", BOLD)

-- local menuItems = {
--   "First",
--   "Second",
--   "Third",
--   "Fourth",
--   "Fifth",
--   "Sixth",
--   "Seventh",
--   "Eighth",
--   "Ninth",
--   "Tenth"
-- }

-- gui.menu(COL4, TOP + ROW, WIDTH, 5 * ROW, menuItems, function(menu) playNumber(menu.selected, 0) end)

-- Horizontal slider
-- gui.label(COL1, TOP + 6 * ROW, WIDTH, HEIGHT, "Horizontal slider:", BOLD)
-- local horizontalSliderLabel = gui.label(COL1 + 2 * WIDTH, TOP + 7 * ROW, 30, HEIGHT, "", RIGHT)

-- local function horizontalSliderCallBack(slider)
--   horizontalSliderLabel.title = slider.value
-- end

-- local horizontalSlider = gui.horizontalSlider(COL1, TOP + 7 * ROW + HEIGHT / 2, 2 * WIDTH, 0, -20, 20, 1, horizontalSliderCallBack)
-- horizontalSliderCallBack(horizontalSlider)

-- Toggle button
-- local toggleButton = gui.toggleButton(COL3, TOP + 7 * ROW, WIDTH, HEIGHT, "Border", false, nil)

-- Prompt showing About text
local aboutPage = 1
local aboutText = {
  "LibGUI is a Lua library for creating graphical user interfaces for Lua widgets on EdgeTX transmitters with color screens. " ..
  "It is a code library embedded in a widget. Since all Lua widgets are always loaded into memory, whether they are used or not, " ..
  "the global function named 'loadGUI()', defined in the 'main.lua' file of this widget, is always available to be used by other widgets.",
  "The library code is implemented in the 'libgui.lua' file of this widget. This code is loaded on demand, i.e. it is only loaded if " ..
  "loadGUI() is called by a client widget to create a new libGUI Lua table object. That way, the library is not using much of " ..
  "the radio's memory unless it is being used. And since it is all Lua code, you can inspect the file yourself, if you are curious " ..
  "or you have found a problem.",
  "When you add the widget to your radio's screen, then this demo is loaded. It is implemented in the 'loadable.lua' file of this " ..
  "widget. Hence, like the LibGUI library itself, it does not waste your radio's memory, unless it is being used. And you can view " ..
  "the 'loadable.lua' file in the widget folder to see for yourself how this demo is loading LibGUI and using it, so you can start " ..
  "creating your own awesome widgets!",
   "Copyright (C) EdgeTX\n\nLicensed under GNU Public License V2:\nwww.gnu.org/licenses/gpl-2.0.html\n\nAuthored by Jesper Frickmann."
}

local logViewer = libGUI.newGUI()

function logViewer.fullScreenRefresh()
  lcd.drawFilledRectangle(40, 30, LCD_W - 80, 30, COLOR_THEME_SECONDARY1)
  lcd.drawText(50, 45, "Flight Log  " .. aboutPage .. "/" .. #aboutText, VCENTER + MIDSIZE + libGUI.colors.primary2)
  lcd.drawFilledRectangle(40, 60, LCD_W - 80, LCD_H - 90, libGUI.colors.primary2)
  lcd.drawRectangle(40, 30, LCD_W - 80, LCD_H - 60, libGUI.colors.primary1, 2)
  lcd.drawTextLines(50, 70, LCD_W - 120, LCD_H - 110, aboutText[aboutPage])
end

-- Button showing Log Viewer prompt
-- gui.button(COL4, TOP + 7 * ROW, WIDTH, HEIGHT, "About", function() gui.showPrompt(logViewer) end)

-- Make a dismiss button from a custom element
local custom2 = logViewer.custom({ }, LCD_W - 65, 36, 20, 20)

function custom2.draw(focused)
  lcd.drawRectangle(LCD_W - 65, 36, 20, 20, libGUI.colors.primary2)
  lcd.drawText(LCD_W - 55, 45, "X", MIDSIZE + CENTER + VCENTER + libGUI.colors.primary2)
  if focused then
    custom2.drawFocus()
  end
end

function custom2.onEvent(event, touchState)
  if event == EVT_VIRTUAL_ENTER then
    gui.dismissPrompt()
  end
end

-- Add a vertical slider to scroll pages
local function verticalSliderCallBack(slider)
  aboutPage = #aboutText + 1 - slider.value
end

local verticalSlider = gui.verticalSlider(LCD_W - 20, 60, LCD_H - 80, #aboutText, 1, #aboutText, 1, verticalSliderCallBack)

local y_position = 20
for log_file_name, data in spairs(log_data, function(t,a,b) return b < a end) do
  if data.flight_count ~= 0 and log_file_name then
      if display_log_flag then
          --View the log contents
          -- draw_log_content(40, 55, string.format(sele_number) .. "#  " .. string.sub(data.logs[sele_number], 4, 11), data.logs[sele_number], telemetry_value_color_flag)
      else
          gui.label(30,  y_position + 40, 20, HEIGHT, "Date: ", BOLD)
          gui.label(70,  y_position + 40, 50, HEIGHT, log_file_name)

          gui.label(270, y_position + 40, 30, HEIGHT, "Flight count: ", BOLD)
          gui.label(370, y_position + 40, 30, HEIGHT, data.flight_count)
        
          -- Flights
          xs = 30
          ys = y_position + 100
          --Log menu
          for m = 0, data.flight_count - 1 do
            if m % 7 == 0 then
              xs = 30
              if m > 0 then
                ys = ys + 35
                y_position= y_position + 65
              end
            else
              xs = xs + 58
            end
            gui.button(xs, ys, 50, 30, string.sub(data.logs[m], 13, 17), function() gui.showPrompt(logViewer) end)
        end
      end
    break
  end
end


-- Draw on the screen before adding gui elements
function gui.fullScreenRefresh()
  -- Draw header
  lcd.drawFilledRectangle(0, 0, LCD_W, HEADER, COLOR_THEME_SECONDARY1)
  lcd.drawText(COL1, HEADER / 2, "Flight Viewer: " .. model_name, VCENTER + DBLSIZE + libGUI.colors.primary2)
  -- Border
  -- if toggleButton.value then
  --   lcd.drawRectangle(0, HEADER, LCD_W, LCD_H - HEADER, libGUI.colors.edit, 5)
  -- end
end

-- Draw in widget mode
function libGUI.widgetRefresh()
  local y_offset = 13
  local line_height = 48
  local xs = zone.x --0
  local ys = zone.y --0
  local xe = zone.w --392
  local ye = zone.h --168
  local get_value
  local widget_flag = false
  local touch_key
  local protocol_str

  --Layout Mode
  if xe < 480 and ye < 272 then --Widget 392x168 Full 480x272
    widget_flag = true
    display_log_flag = false
  end

  -- Options
  -- lcd.setColor(CUSTOM_COLOR, widget.options.ValueColor)
  telemetry_value_color_flag = lcd.getColor(BLACK)

  -- lcd.setColor(CUSTOM_COLOR, widget.options.LabelColor)
  telemetry_label_color_flag = lcd.getColor(BLACK)

  -- lcd.setColor(CUSTOM_COLOR, widget.options.GridColor)
  display_gird_color_flag = lcd.getColor(BLACK)
  
  protocol_str = protocol_type == 1 and "[FPORT]" or "[CRSF]"

  --Widget 392x168
  if widget_flag then
    lcd.drawText(xs, ys, NAME .. ' ' .. VERSION .. ' ' .. protocol_str .. ' ' .. '[' .. model_name .. ']', telemetry_value_color_flag)
    lcd.drawText(xs + 261, ys, display_list[DISP_FM_INDEX], telemetry_value_color_flag)
    if field_id[FM_INDEX][2] then
      get_value = getValue(field_id[FM_INDEX][1])
      if get_value == 0 then
        lcd.drawText(xs + 261 + 30, ys, "No Tele", BLINK + telemetry_value_color_flag)
        ring_data = 0
        wait_count = 0
        sync_fuel_value = 0
        play_speed = 0
        time_os = getTime() --10ms
        batter_on_flag = false
        init_sync_flag = false
        sync_end_flag = false
        spoolup_flag = false
        if ring_end_flag then
          ring_start_flag = false
          ring_end_flag = false
        end
      else
        --Hint
        if protocol_type == 1 then --FPORT
          get_value = bit32.band(get_value, 0x0007)
          if get_value == 1 then
            lcd.drawText(xs + 261 + 30, ys, "DISARMED", telemetry_value_color_flag)
          elseif get_value == 5 then
            lcd.drawText(xs + 261 + 30, ys, "ARMED", telemetry_value_color_flag)
          else
            lcd.drawText(xs + 261 + 30, ys, "ARMING", telemetry_value_color_flag)
          end
        else --CRSF
          lcd.drawText(xs + 261 + 30, ys, string.format(data_format[DISP_FM_INDEX], get_value), telemetry_value_color_flag)
        end
        --Control
        if get_value == "DISARMED" or get_value == 1 then
          if batter_on_flag == false then
            if getTime() - time_os > 350 then --350*10=3500ms
                time_os = getTime()
                init_sync_flag = true
                batter_on_flag = true
                --Zeros
                for i = 1, #value_min_max do
                  for j = 1, #value_min_max[i] do
                    value_min_max[i][j] = 0
                  end
                end
                power_max[1] = 0
                power_max[2] = 0
            end
          end
          if spoolup_flag then
            spoolup_flag = false
            write_en_flag = true
          end
        elseif spoolup_flag == false and (get_value == "OFF" or get_value == "SPOOLUP" or get_value == 5) then
          second[1] = 0
          spoolup_flag = true
          --Synchronize data before starting
          capa_start = value_min_max[4][1]
          fuel_start = value_min_max[5][1]
          power_max[1] = 0
          power_max[2] = 0
          for s = 1, TELE_ITEMS - 1 do
            value_min_max[s][2] = value_min_max[s][1]
            value_min_max[s][3] = value_min_max[s][1]
          end
        end
      end
    else
      lcd.drawText(xs + 261 + 30, ys, "No Tele", BLINK + telemetry_value_color_flag)
    end
  end

  --Telemetry data
  for k = 1, TELE_ITEMS - 1 do
    if k == 1 then
      xs = 150
      ys = 20
    end
    if k < 4 and widget_flag then
      lcd.drawText(xs, ys, display_list[k], telemetry_label_color_flag)
    end
    if field_id[k][2] then
      get_value = getValue(field_id[k][1])
      --CRSF
      if protocol_type == 0 then
          if k == data_hag[1] then
              get_value = get_value * data_hag[2];
          end
          if k == data_ptch[1] then
              get_value = get_value * data_ptch[2];
          end
      end
      value_min_max[k][1] = get_value
      if init_sync_flag then
        value_min_max[k][2] = get_value
        value_min_max[k][3] = get_value
        --Ring
        if ring_start_flag == false and value_min_max[5][1] > 0 then
            sync_fuel_value = sync_fuel_value + 1
            if sync_fuel_value > 29 then
                wait_count = 0
                ring_start_flag = true
                ring_end_flag = false
            end
        else
            sync_fuel_value = 0
        end
      else
        if batter_on_flag and get_value ~= 0 then
          if get_value > value_min_max[k][2] then
            value_min_max[k][2] = get_value
          elseif get_value < value_min_max[k][3] then
            value_min_max[k][3] = get_value
          end
        end
      end

      --Voltage display mode
      --Display Real time
      if k < 4 and widget_flag then
        if k == 1 then
          if alternate_flag then
            lcd.drawText(xs, ys + y_offset, string.format(data_format[k], value_min_max[12][1]), DBLSIZE + telemetry_value_color_flag) --Bec Real time
            lcd.drawText(xs + 85, ys + y_offset, string.format(data_format[k], value_min_max[12][2]), telemetry_value_color_flag)      --Bec Max
            lcd.drawText(xs + 85, ys + y_offset + 15, string.format(data_format[k], value_min_max[12][3]), telemetry_value_color_flag) --Bec Min
          else
            lcd.drawText(xs, ys + y_offset, string.format(data_format[k], value_min_max[k][1]), DBLSIZE + telemetry_value_color_flag)  --Battery Real time
            lcd.drawText(xs + 85, ys + y_offset, string.format(data_format[k], value_min_max[k][2]), telemetry_value_color_flag)       --Battery Max
            lcd.drawText(xs + 85, ys + y_offset + 15, string.format(data_format[k], value_min_max[k][3]), telemetry_value_color_flag)  --Battery Min
          end
        else
          lcd.drawText(xs, ys + y_offset, string.format(data_format[k], value_min_max[k][1]), DBLSIZE + telemetry_value_color_flag)                                                         --Real time
          lcd.drawText(xs + 85, ys + y_offset, string.format(data_format[k], value_min_max[k][2]), telemetry_value_color_flag)                                                              --Max
          if k == 2 then
              lcd.drawText(xs + 85, ys + y_offset + 15, string.format("%dW", power_max[2]), telemetry_value_color_flag)                                                                     --Power
          elseif k == 3 then
              if protocol_type == 1 then                                                                                                                                        --FPORT
                  lcd.drawText(xs + 85, ys + y_offset + 15, string.format("%.f%%", (getOutputValue(widget.options.ThrottleChannel - 210) + 1024) / 2048 * 100), telemetry_value_color_flag) --Throttle [Remote control channel value]
              else                                                                                                                                                              --CRSF
                  lcd.drawText(xs + 85, ys + y_offset + 15, string.format("%d%%", value_min_max[11][1]), telemetry_value_color_flag)                                                        --Throttle [FC real-time value]
              end
          else
              lcd.drawText(xs + 85, ys + y_offset + 15, string.format(data_format[k], value_min_max[k][3]), telemetry_value_color_flag) --Min
          end
        end
      end
    else
      if k < 4 and widget_flag then
        lcd.drawText(xs, ys + y_offset, "----", DBLSIZE + telemetry_value_color_flag)
      end
    end
    ys = ys + line_height
  end

  --Limit RPM maximum
  value_min_max[3][2] = math.min(value_min_max[3][2], 9999)

  --Power
  power_max[2] = math.min(math.floor(value_min_max[1][1] * value_min_max[2][1]), 9999)
  if power_max[1] < power_max[2] then
    power_max[1] = power_max[2]
  end

  --Synchronize
  if init_sync_flag then
    if getTime() - time_os > 1000 then --1000*10=10000ms
      time_os = getTime()
      init_sync_flag = false
      sync_end_flag = true
    end
  end

  --Timer Warning
  if spoolup_flag then
    second[3] = getRtcTime()
    if second[2] ~= second[3] then
      second[2] = second[3]
      --Subtotal
      second[1] = second[1] + 1
      --Total
      total_second = total_second + 1
      --Warning
      if widget.options.LowVoltageValue_x10 ~= 0 or widget.options.LowFuelValue ~= 0 then
        if value_min_max[1][1] < widget.options.LowVoltageValue_x10 / 10 or value_min_max[5][1] < widget.options.LowFuelValue then
          play_speed = play_speed + 1
          if play_speed > 2 then
            play_speed = 0
            playFile("/WIDGETS/Test/batlow.wav")
            playHaptic(25, 50, 0)
            playHaptic(10, 20, 1)
          end
        else
          play_speed = 0
        end
      end
    end
  end

  --Format Timer
  minutes[1] = string.format("%02d", math.floor(second[1] % 3600 / 60))
  seconds[1] = string.format("%02d", second[1] % 3600 % 60)
  hours = string.format("%02d", math.floor(total_second / 3600))
  minutes[2] = string.format("%02d", math.floor(total_second % 3600 / 60))
  seconds[2] = string.format("%02d", total_second % 3600 % 60)

  --Display mode
  --Widget 392x168
  if widget_flag then 
    xs = zone.x
    ys = zone.y
    --Dividing line
    lcd.drawLine(xs + 145, ys + 66, xe, ys + 66, SOLID, display_gird_color_flag)
    lcd.drawLine(xs + 145, ys + 66 + line_height, xe, ys + 66 + line_height, SOLID, display_gird_color_flag)
    lcd.drawLine(xs + 285, ys + 20, xs + 285, ye - 6, SOLID, display_gird_color_flag)
    --Fuel Percentage
    if ring_start_flag and ring_end_flag == false then
        if ring_data >= value_min_max[5][1] then
            wait_count = wait_count + 1
            if wait_count > 99 then
                ring_end_flag = true
            end
        else
            ring_data = ring_data + 1
            wait_count = 0
        end
    else
        if ring_end_flag then
            ring_data = value_min_max[5][1]
        else
            ring_data = 0
        end
    end
    fuel_percentage(xs + 70, ys + 90, value_min_max[4][1], ring_data)

    --Timer 48x112
    xs = 280
    ys = 20
    --T1 (Current flight time)
    lcd.drawText(xs + 12, ys, "CFT", telemetry_label_color_flag)
    lcd.drawText(xs + 45, ys, "M", telemetry_label_color_flag)
    lcd.drawText(xs + 45 + 53, ys, "S", telemetry_label_color_flag)
    lcd.drawText(xs + 12, ys + y_offset, minutes[1], DBLSIZE + telemetry_value_color_flag)
    lcd.drawText(xs + 65, ys + y_offset, seconds[1], DBLSIZE + telemetry_value_color_flag)
    --T2 (Total flight time)
    ys = ys + line_height
    lcd.drawText(xs + 12, ys, "TFT", telemetry_label_color_flag)
    if tonumber(total_seconds) >= 3600 then
        lcd.drawText(xs + 45, ys, "H", telemetry_label_color_flag)
        lcd.drawText(xs + 45 + 53, ys, "M", telemetry_label_color_flag)
        lcd.drawText(xs + 12, ys + y_offset, model_flight_stats.total_hours, DBLSIZE + telemetry_value_color_flag)
        lcd.drawText(xs + 65, ys + y_offset, model_flight_stats.total_minutes, DBLSIZE + telemetry_value_color_flag)
    else
        lcd.drawText(xs + 45, ys, "M", telemetry_label_color_flag)
        lcd.drawText(xs + 45 + 53, ys, "S", telemetry_label_color_flag)
        lcd.drawText(xs + 12, ys + y_offset, model_flight_stats.total_minutes, DBLSIZE + telemetry_value_color_flag)
        lcd.drawText(xs + 65, ys + y_offset, model_flight_stats.total_seconds, DBLSIZE + telemetry_value_color_flag)
    end
    --Number of flights
    ys = ys + line_height
    lcd.drawText(xs + 12, ys, "TFC", telemetry_label_color_flag)
    lcd.drawText(xs + 12, ys + y_offset, string.format("%02d", model_flight_stats.flight_count), DBLSIZE + telemetry_value_color_flag)
    lcd.drawText(xs + 45 + 53, ys, "N", telemetry_label_color_flag)  
  end
  -- lcd.drawRectangle(0, 0, zone.w, zone.h, libGUI.colors.primary3)
  -- lcd.drawText(zone.w / 2, zone.h / 2, protocol_str, DBLSIZE + CENTER + VCENTER + libGUI.colors.primary3)
end

-- This function is called from the refresh(...) function in the main script
function widget.refresh(event, touchState)
  gui.run(event, touchState)
end

-- Return to the create(...) function in the main script
return widget
