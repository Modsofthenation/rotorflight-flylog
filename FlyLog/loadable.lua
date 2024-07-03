--Script information
local NAME = "FlyLogDebug"
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
local file_name = ""
local file_path = ""
local file_obj
local log_data = {}
local second = { 0, 0, 0 }
local total_second = 0
local hours = 0
local minutes = { 0, 0 }
local seconds = { 0, 0 }
local play_speed = 0

local model_flight_stats = {}
local selected_session_date = { 
  flight_index = 0, 
  log_file = "" 
}
local model_log_file_count = 0
local selected_log_file_index = 1
local total_seconds = 0

--Flag
local paint_color_flag = BLACK
local telemetry_value_color_flag
local batter_on_flag
local init_sync_flag
local sync_end_flag
local spoolup_flag
local display_log_flag
local should_write_log
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

local function get_todays_log_file_name() 
  return '[' .. model_name .. ']' ..
      string.format("%d", getDateTime().year) ..
      string.format("%02d", getDateTime().mon) ..
      string.format("%02d", getDateTime().day) .. ".log"
end

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

local function parse_log_filename_to_date(log_filename)
  local flight_session_date = string.match(log_filename, "%](%d+)%.log")
  local year = string.sub(flight_session_date, 1, 4)
  local month = string.sub(flight_session_date, 5, 6)
  local day = string.sub(flight_session_date, 7, 8)
  return day .. "/" .. month .. "/" .. year
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

--process_logs_startup
local function process_logs_startup(current_model_name)
  local total_flight_time = 0
  local running_flight_count = 0
  local todays_log_file_name = get_todays_log_file_name()
  local log_flight_time = 0

  for fname in dir("/WIDGETS/" .. NAME .. "/logs/") do
    log_flight_time = 0
    if string.find(fname, current_model_name) then
      file_obj = io.open("/WIDGETS/" .. NAME .. "/logs/" .. fname, "r")
      line = io.read(file_obj, LOG_INFO_LEN + 1)
      
      hours = string.sub(line, 12, 13)
      minutes[2] = string.sub(line, 15, 16)
      seconds[2] = string.sub(line, 18, 19)
    
      log_flight_time = tonumber(string.sub(line, 12, 13)) * 3600
      log_flight_time = log_flight_time + tonumber(string.sub(line, 15, 16)) * 60
      log_flight_time = log_flight_time + tonumber(string.sub(line, 18, 19))

      total_seconds = total_seconds + log_flight_time

      if log_flight_time > 0 then
        model_log_file_count = model_log_file_count + 1

        current_log_file_flight_count = tonumber(string.sub(line, 21, 22))
        total_flight_time = total_flight_time + log_flight_time
        running_flight_count = running_flight_count + current_log_file_flight_count

        current_read_count = 0
        log_data[fname] = {
          flight_count = current_log_file_flight_count,
          flight_time = {
            hours = string.format("%02d", math.floor(log_flight_time / 3600)),
            minutes = string.format("%02d", math.floor(log_flight_time % 3600 / 60)),
            seconds = string.format("%02d", log_flight_time % 3600 % 60),
          },
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
      end
      io.close(file_obj)
      if log_flight_time == 0 and fname ~= todays_log_file_name then
        del("/WIDGETS/" .. NAME .. "/logs/" .. fname)
      end
    end
  end
  return {
    total_minutes = string.format("%02d", math.floor(total_flight_time % 3600 / 60)),
    total_seconds = string.format("%02d", total_flight_time % 3600 % 60),
    total_hours = string.format("%02d", math.floor(total_flight_time / 3600)),
    flight_count = running_flight_count
  }
end

local zone, options = ...
local widget = {
  zone = zone,
  options = options
}

local function init_logic()
  local module = {}
  --Head speed ratio
  --local _, _, major, minor, rev, osname = getVersion()

  --Variable initialization
  for i = 1, #second do
    second[i] = 0
  end
  total_second = 0
  --Flag
  should_write_log = false
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
        protocol_type = 1                                      -- FPORT
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

  --log
  local filename = get_todays_log_file_name()
  file_path = "/WIDGETS/" .. NAME .. "/logs/" .. filename

  local file_info = fstat(file_path)
  log_data[filename] = {}
  if file_info == nil then
    file_obj = io.open(file_path, "w")
    local log_info =
        string.format("%d", getDateTime().year) .. '/' ..
        string.format("%02d", getDateTime().mon) .. '/' ..
        string.format("%02d", getDateTime().day) .. '|' ..
        "00:00:00" .. '|' ..
        "00\n"
    io.write(file_obj, log_info)
    io.close(file_obj)
  end
  model_flight_stats = process_logs_startup(model_name)
end

init_logic()

-- Miscellaneous constants
local HEADER = 40
local WIDTH  = 100
local COL1   = 10
local COL2   = 130
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

local FlightViewer = libGUI.newGUI()

FlightViewer.button(LCD_W - 35, LCD_H/2 - 12, 25, 25, " > ", 
  function()
    local newFlightIndex = selected_session_date.flight_index + 1
    selected_session_date = { flight_index = newFlightIndex, log_file = selected_session_date.log_file }
  end
)

FlightViewer.button(10, LCD_H/2 - 12, 25, 25, " < ", 
  function()
    local newFlightIndex = selected_session_date.flight_index - 1
    selected_session_date = { flight_index = newFlightIndex, log_file = selected_session_date.log_file }
  end
)


function FlightViewer.fullScreenRefresh()
  lcd.drawFilledRectangle(40, 30, LCD_W - 80, 30, COLOR_THEME_SECONDARY1)
  lcd.drawText(50, 45,  parse_log_filename_to_date(selected_session_date.log_file) .. " - " .. "Flight: " .. selected_session_date.flight_index + 1, VCENTER + MIDSIZE + libGUI.colors.primary2)
  lcd.drawFilledRectangle(40, 60, LCD_W - 80, LCD_H - 90, libGUI.colors.primary2)
  lcd.drawRectangle(40, 30, LCD_W - 80, LCD_H - 60, libGUI.colors.primary1, 2)

  -- Draw the backdrop
  lcd.drawFilledRectangle(0, 0, 40, LCD_H, LIGHTGREY, 1)

  lcd.drawFilledRectangle(LCD_W - 40, 30, 40, LCD_H, LIGHTGREY, 1)

  lcd.drawFilledRectangle(40, 0, LCD_W-40, 30, LIGHTGREY, 1)
  lcd.drawFilledRectangle(40, LCD_H - 30, LCD_W-40, 30, LIGHTGREY, 1)

  local message = log_data[selected_session_date.log_file]["logs"][selected_session_date.flight_index]
  local extract = {}
  local value
  local index, length = 4, 8
  --Date time
  extract[1] = string.sub(message, index, index + length - 1)
  --Flight time
  index = 13
  length = 5
  extract[2] = string.sub(message, index, index + length - 1)
  --Capa Fuel HSpd Current Power [[Battery ESC MCU 1RSS 2RSS RQly] MAX MIN] Throttle BEC[MAX MIN]
  for t = 1, 20 do
    index = index + length + 1
    if t == 2 or t == 16 or t == 17 or t == 18 then
      length = 3
    elseif t == 4 then
      length = 5
    else
      length = 4
    end
    value = tonumber(string.sub(message, index, index + length - 1))
    if t == 4 or t == 6 or t == 7 or t == 19 or t == 20 then
      extract[t + 2] = string.format("%.1f", value)
    else
      extract[t + 2] = string.format("%d", value)
    end
  end

  local localX = 50
  local localY = 40
  lcd.drawText(localX + 5, localY + 30,
    "Time: \n"..
    "Capacity: \n" ..
    "Bat used: \n" ..
    "HSpd: \n" ..
    "Throttle: \n" ..
    "Current: \n" ..
    "Power: "
    , flags)
  lcd.drawText(localX + 85, localY + 30,
    extract[2] .. '\n' ..
    extract[3] .. "mAh\n" ..
    extract[4] .. "%\n" ..
    extract[5] .. "rpm\n" ..
    extract[20] .. "%\n" ..
    extract[6] .. "A\n" ..
    extract[7] .. "W"
    , flags)
  lcd.drawText(localX + 195, localY + 30,
    "Battery: \n" ..
    "BEC: \n" ..
    "ESC: \n" ..
    "MCU: \n" ..
    data_field[8] .. ": \n" ..
    data_field[9] .. ": \n" ..
    data_field[10] .. ":"
    , flags)
  lcd.drawText(localX + 265, localY + 30,
    extract[8] .. "V -> " .. extract[9] .. "V\n" ..
    extract[21] .. "V -> " .. extract[22] .. "V\n" ..
    extract[11] .. "°C -> " .. extract[10] .. "°C\n" ..
    extract[13] .. "°C -> " .. extract[12] .. "°C\n" ..
    extract[14] .. "dB -> " .. extract[15] .. "dB\n" ..
    extract[16] .. "dB -> " .. extract[17] .. "dB\n" ..
    extract[18] .. "% -> " .. extract[19] .. "%"
    , flags)
end

-- Make a dismiss button from a custom element
local CustomCloseButtonFlightViewer = FlightViewer.custom({ }, LCD_W - 65, 36, 20, 20)

function CustomCloseButtonFlightViewer.draw(focused)
  lcd.drawRectangle(LCD_W - 65, 36, 20, 20, libGUI.colors.primary2)
  lcd.drawText(LCD_W - 55, 45, "X", MIDSIZE + CENTER + VCENTER + libGUI.colors.primary2)
  if focused then
    CustomCloseButtonFlightViewer.drawFocus()
  end
end

function CustomCloseButtonFlightViewer.onEvent(event, touchState)
  if event == EVT_VIRTUAL_ENTER then
    gui.dismissPrompt()
  end
end

local function renderFlightViewer()
  gui = libGUI.newGUI()

  -- Draw on the screen before adding gui elements
  function gui.fullScreenRefresh()
    lcd.drawFilledRectangle(0, 0, LCD_W, HEADER, COLOR_THEME_SECONDARY1)
    lcd.drawText(COL1, HEADER / 2, "Flight Viewer: " .. model_name, VCENTER + DBLSIZE + libGUI.colors.primary2)
    lcd.drawFilledRectangle(0, 85, LCD_W, LCD_H - 120, LIGHTWHITE)
    lcd.drawFilledRectangle(0, 85, 50, LCD_H - 85, libGUI.colors.primary2)
    lcd.drawFilledRectangle(LCD_W - 50, 85, 50, LCD_H - 50, libGUI.colors.primary2)
  end
  gui.fullScreenRefresh()

  if selected_log_file_index < model_log_file_count then
    gui.button(LCD_W - 40, 100, 30, 30, ">", 
      function()
        selected_log_file_index = selected_log_file_index + 1
        renderFlightViewer()
      end
    )
  end

  if selected_log_file_index > 1 then
    gui.button(10, 100, 30, 30, "<", 
      function()
        selected_log_file_index = selected_log_file_index - 1
        renderFlightViewer()
      end
    )
  end

  local y_position = 10
  local local_file_index = 0

  local x_offset = 55
  for log_file_name, data in spairs(log_data, function(t,a,b) return b < a end) do
    if selected_log_file_index == local_file_index then
      gui.drawFilledRectangle(0, 0, LCD_W, HEADER, COLOR_THEME_SECONDARY1)
      gui.drawText(COL1, HEADER / 2, "Flight Viewer: " .. model_name, VCENTER + DBLSIZE + libGUI.colors.primary2)

      gui.label(15,  y_position + 40, 20, HEIGHT, "Date: ", BOLD)
      gui.label(55,  y_position + 40, 50, HEIGHT, parse_log_filename_to_date(log_file_name))

      gui.label(160, y_position + 40, 30, HEIGHT, "Flight count: ", BOLD)
      gui.label(255, y_position + 40, 30, HEIGHT, data.flight_count)

      gui.label(265 + 15, y_position + 40, 30, HEIGHT, "Flight time: ", BOLD)
      gui.label(265 + 100, y_position + 40, 30, HEIGHT, data.flight_time.hours .. "h " ..  data.flight_time.minutes .. "m " ..  data.flight_time.seconds .. "s")

      -- Flights
      xs = 15 + x_offset
      ys = y_position + 90
      --Log menu
      for m = 0, data.flight_count - 1 do
        if m % 6 == 0 then
          xs = 15 + x_offset
          if m > 0 then
            ys = ys + 35
            y_position= y_position + 65
          end
        else
          xs = xs + 58
        end
        gui.button(xs, ys, 50, 30, string.sub(data.logs[m], 13, 17), 
          function()
            selected_session_date = { flight_index = m, log_file = log_file_name }
            gui.showPrompt(FlightViewer) 
          end
        )
      end
      break
    else 
      local_file_index = local_file_index + 1
    end
  end
end

renderFlightViewer()

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
            should_write_log = true
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
            playFile("/WIDGETS/" .. NAME .. "/batlow.wav")
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

  if should_write_log then
    local todays_log_file_name = get_todays_log_file_name()
    logs[todays_log_file_name].flight_count = logs[todays_log_file_name].flight_count + 1
    log_file_object = io.open(file_path, "w")
    log_info = string.format("%d", getDateTime().year) .. '/' ..
      string.format("%02d", getDateTime().mon) .. '/' ..
      string.format("%02d", getDateTime().day) .. '|' ..
      hours .. ':' .. minutes[2] .. ':' .. seconds[2] .. '|' ..
      string.format("%02d", logs[todays_log_file_name].flight_count) .. "\n"
    io.write(log_file_object, log_info)

    --Write History Log
    for w = 1, logs[todays_log_file_name].flight_count - 1 do
      io.write(log_file_object, log_data[todays_log_file_name]["logs"][w])
    end

    --Write New Log [ 10|16:20:36|04:46|4533|087|2289|159.9|10295|24.9|20.2|+099|+033|+045|+043|-032|-072|-030|-084|100|096|100|12.1|07.4 ]
    local new_log_entry =  
      string.format("%02d", fly_number) .. '|' .. --Number
      string.format("%02d", getDateTime().hour) .. ':' ..
      string.format("%02d", getDateTime().min) .. ':' ..
      string.format("%02d", getDateTime().sec) .. '|' ..                --Date time
      minutes[1] .. ':' .. seconds[1] .. '|' ..                         --Flight time
      string.format("%04d", value_min_max[4][1] - capa_start) .. '|' .. --Capa used
      string.format("%03d", fuel_start - value_min_max[5][1]) .. '|' .. --Fuel used
      string.format("%04d", value_min_max[3][2]) .. '|' ..              --HSpd Max
      string.format("%05.1f", value_min_max[2][2]) .. '|' ..            --Current Max
      string.format("%05d", power_max[1]) .. '|' ..                     --Power Max
      string.format("%04.1f", value_min_max[1][2]) .. '|' ..            --Battery Max
      string.format("%04.1f", value_min_max[1][3]) .. '|' ..            --Battery Min
      string.format("%+04d", value_min_max[6][2]) .. '|' ..             --ESC Max
      string.format("%+04d", value_min_max[6][3]) .. '|' ..             --ESC Min
      string.format("%+04d", value_min_max[7][2]) .. '|' ..             --MCU Max
      string.format("%+04d", value_min_max[7][3]) .. "|" ..             --MCU Min
      string.format("%+04d", value_min_max[8][2]) .. '|' ..             --1RSS Max
      string.format("%+04d", value_min_max[8][3]) .. '|' ..             --1RSS Min
      string.format("%+04d", value_min_max[9][2]) .. '|' ..             --2RSS Max
      string.format("%+04d", value_min_max[9][3]) .. '|' ..             --2RSS Min
      string.format("%03d", value_min_max[10][2]) .. '|' ..             --RQly Max
      string.format("%03d", value_min_max[10][3]) .. '|' ..             --RQly Min
      string.format("%03d", value_min_max[11][2]) .. '|' ..             --Throttle Max
      string.format("%04.1f", value_min_max[12][3]) .. '|' ..           --BEC Max
      string.format("%04.1f", value_min_max[12][2]) .. "\n"             --BEC Min

    io.write(log_file_object, new_log_entry)
    io.close(log_file_object)

    should_write_log = false

    -- Rebuild table with latest stats
    model_flight_stats = process_logs_startup(model_name)
  end
end

-- This function is called from the refresh(...) function in the main script
function widget.refresh(event, touchState)
  gui.run(event, touchState)
end

-- Return to the create(...) function in the main script
return widget
