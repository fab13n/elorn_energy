local serial = require 'serial'
local encode = require 'victron.mk2.encode'
local decode = require 'victron.mk2.decode'
local sched  = require 'sched'

local M = { }

local MT = { }

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