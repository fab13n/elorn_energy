-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module victron.mk2
--  Sends MK2 commands to a Victron inverter, decodes responses.
--
--  This driver allows to read and modify the settings of a Victron inverter
--  supporting the proprietery MK2 protocol (Mostly Multiplus, Phoenix and
--  Quattro product lines). The actual encoding and decoding work is done by
--  two submodules `victron.mk2.encode` and `victron.mk2.decode`.
--
--  Currently supported commands are `version` (read firmware version`, led
--  (read the current state of the panel's indication LEDs), state (change
--  the device's operating mode, switch charger and inverter functions on/off,
--  and optionally limiting input current).
--
--  Advanced commands, known as "W commands" in Victron's specs, are not
--  supported yet.

local serial = require 'serial'
local encode = require 'victron.mk2.encode'
local decode = require 'victron.mk2.decode'
local sched  = require 'sched'

local M = { }

local MT = { }

--- Creates a new MK2 driver instance, using the serial device whose file
--  name is passed as argument.
--  @param UART name, e.g. `"/dev/ttyUSB0"`
--  @return a `victron.mk2` instance or `nil`+error message 
function M.new(dev_name)
  local instance = { }
  local uart = serial.open(dev_name, {baudrate=2400})
  instance.encoder = encode.new(uart)
  instance.decoder = decode.new(uart)
  return setmetatable(instance, MT)
end

--- Response(s) expected by each command
M.responses = {
  led     = { 'led' },
  version = { 'version'},
  state   = { 'info', 'multiled' }
}

--- Ensures autocompletion on smart interactive shells
function MT:__pairs() 
  return pairs{ version=self.version, led=self.led, state=self.state }
end

--- Encodes and sends the command, waits for appropriate responses,
--  returns decoded results.
function MT :__index(name)
  return function(...)
    local responses = M.responses[name]
    if not responses then return nil end 
    local r, msg = self.encoder(name, ...) -- Send the command
    if not r then return nil, msg end
    local events = { 'error', self.timeout, unpack(responses) }
    local ev, frame = sched.wait(self.decoder, events) -- wait for response
    if     ev=='error'   then return nil, frame
    elseif ev=='timeout' then return nil, 'timeout'
    else   return frame end
  end
end

--- Requests firmware version number.
--  @function [parent=#victron.mk2] version 

--- Requests the state of each LED.
--  @function [parent=#victron.mk2] led

--- Sets the switch state (one of `"on", "off", "inverter", "charger"`),
--  and optionally the maximum input current.
--
--  @function [parent=#victron.mk2] state
--  @param switch state in which the system must be switched, one of `"on",
--   "off", "inverter", "charger"`
--  @param Maximum output current, in Amperes. Ignored if out of the device's
--   range; precision up to 100mA. Leave at `nil` to leave the limit unchanged.

--- Requests an electrical line state.
--  @function [parent=#victron.mk2] frame
--  @param what which line should be described; one of `"dc", "ac1", "ac2",
--   "ac3", "ac4", "multiled"`.

return M