-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module victron.mk2.decode
--  Reads MK2 data from a serial port, decodes them into human-readable
--  Lua records and dispatches them to whomever is interested as
--  `sched.signals`.
--
--  @usage
--
--     local uart   = serial.open(...)
--     local mk2_decode = require 'victron.mk2.decode'
--     local decoder    = mk2_decode.new(uart)
--     sched.sigrun(decoder, '*', function(ev, frame)
--         print("Incoming MK2 %s message: %s", ev, sprint(frame))
--     end)
--     decoder :start()


local bit32 = require 'bit32'
local sched = require 'sched'

-- Module
local M = { }
local M_MT = { __call = function(self, ...) return M.decoder(...) end }
setmetatable(M, M_MT)

M.command_char2name = {
  V = 'version',
  L = 'led',
  S = 'state',
  [string.char(0x20)] = 'info',
  [string.char(0x40)] = 'panel',
  [string.char(0x41)] = 'multiled'
}

-- Decoder metatable
local D = { }
local MT = { __type='victron.mk2.decoder', __index=D }

--- Creates a new decoder, hooked to a serial device presumably created through
--  `require 'serial'.open()`.
function M.new(uart)
  local instance = { uart=uart }
  return setmetatable(instance, MT)
end

--- Starts signaling every incoming frame, fully decoded, as a 'sched' signal.
--  @return `"ok"` or `nil`+message
function D :start()
  if self.loop then return nil, "already running" end
  log('VICTRON-MK2', 'INFO', "Starting to monitor decoded frames")
  local function loop()
    -- TODO: synchronize on a completed frame (we might start in the middle
    -- of a `Version` frame reception).
    while true do
      local frame, msg = self:read()
      if frame then
        log('VICTRON-MK2', 'DEBUG', "Found a frame of type %s", tostring(frame.cmd_name))
      else
        log('VICTRON-MK2', 'ERROR', "Can't read frame: %s", tostring(msg))
      end
      if frame then sched.signal(self, frame.cmd_name, frame)
      else sched.signal(self, 'error', msg); sched.wait(2) end
    end
  end
  self.loop = sched.run(loop)
  return "ok"
end

--- Stops a signalling loop started by `:start()`.
--  @return `"ok"` or `nil`+message
function D :stop()
  if not self.loop then return nil, "not running" end
  sched.kill(self.loop)
  self.loop=nil
end

--- Checks whether a sequence of bytes, received from serial, has a consistent
--  checksum, taking the length byte into account.
--  @returns bool true for success, false for inconsistency
local function verifychecksum(rawlength, bytes)
  local sum=rawlength
  for _, byte in ipairs(bytes) do sum=(sum+byte)%0x100 end
  return sum==0
end

--- Reads and decodes one frame from the serial port.
--  Causes an error in case of problem.
--  @returns the frame, decoded as a Lua record.
function D :read()
  checks('victron.mk2.decoder')
  local rawlength, chars, msg
  rawlength, msg = self.uart :read(1)
  if not rawlength then return nil, msg end
  rawlength = rawlength :byte()
  local length    = rawlength % 0x80
  local ledframe  = length~=rawlength
  chars, msg      = self.uart :read(length + 1)
  if not chars then return nil, msg end
  local bytes     = { chars :byte(1, -1) }

  if not verifychecksum(rawlength, bytes) then return nil, "Invalid checksum" end
  local frame     = { }
  self :decode(bytes, frame)

  -- TODO: just ignore and leave it for next read?
  if ledframe then frame.leds = self :read() end
  return frame
end

--- 
--  @param bytes list of bytes forming the undecoded frame, length excluded.
--  @param frame record in which human-readable fields must be pushed
--  @returns the filled frame
function D :decode (bytes, frame)
  checks('victron.mk2.decoder', 'table')
  local is_mk2 = bytes[1]==0xFF   -- MK2 frames start with FF, VE.Bus ones don't
  frame.cmd_byte = bytes[is_mk2 and 2 or 1]
  frame.cmd_char = string.char(frame.cmd_byte)
  frame.cmd_name = M.command_char2name[frame.cmd_char]
  if is_mk2 and #bytes==3 or not is_mk2 and #bytes==2 then
    -- Empty messages still have a command bytes and a checksum
    frame.empty = true
  elseif not frame.cmd_name then
    local all_bytes = { }
    for i, b in ipairs(bytes) do all_bytes[i]=string.format('%02x', b) end
    all_bytes = table.concat(all_bytes, '-')
    log('VICTRON-MK2', 'WARNING', "Unknown non-empty incoming message: "..all_bytes)
    return nil, "Unknown message"
  else
    local handler = M.decoders[frame.cmd_name]
    local data = { select(is_mk2 and 3 or 2, unpack(bytes)) } -- skip FF&cmd
    table.remove(data, pos)                               -- remove checksum
    handler(data, frame)
  end
  return frame
end

--- Extracts a multi-bytes number from a sequence of bytes,
--  starting at the `first_byte`-th byte, and reading a total
--  of `n_bytes` bytes, with the appropriate endianness.
--
--  @param bytes the argument bytes as a table of ints
--  @param first_byte 1-based index of the first byte to read
--  @param n_bytes number of bytes to read
--  @return the decoded multi-byte number
local function get_number(bytes, first_byte, n_bytes)
  local total, factor = 0, 1
  for i = first_byte, first_byte + n_bytes - 1 do
    total = total + factor * bytes[i]
    factor = factor * 0x100
  end
  return total
end

--- Explodes a byte into 8 bits in a table indexed 1..8
-- @param byte the byte to explode as a number
-- @return a list of 8 bits, as booleans true/false
--
-- @usage
--
--    local n = 5
--    local bits = bit_explode(n)
--    assert(bits[1] and not bits[2] and bits[3])
--
local function bit_explode(byte)
  local r, pow = { }, 1
  for i=1,8 do
    r[i] = bit32.band(byte, pow)~=0 or false
    pow = 2*pow
  end
  return r
end

--- All decoders are functions which take a list of bytes (all bytes in the
--  incoming frame between command and checksum excluded), and a frame table
--  to fill with command-dependent fields.
--
M.decoders = { }
local DECODE = M.decoders


--- Returns a version number (32-bits integer).
function DECODE.version(bytes, frame)
  frame.version = get_number(bytes, 1, 4)
  local mode = bytes[5]
  if mode==string.byte('W') then
    frame.mode = 'VE 9-bit RS485'
  else
    frame.mode    = 'VE.Bus'
    if mode~=string.byte('B') then frame.address = mode end
  end 
end

--- Decodes LED status description.
--
--  Each LED name is represented in the resulting frame, with a value
--  among `'unknown', 'on', 'off', 'blink', 'inverted_blink'`.
--
--  LED names are `'mains', 'absorption', 'bulk', 'float',
--  'inverter', 'overload', 'low_battery', 'temperature'`.
--
function DECODE.led(bytes, frame)
  local field_names = {
    'mains', 'absorption', 'bulk', 'float',
    'inverter', 'overload', 'low_battery', 'temperature' }
  local on_byte, blink_byte = unpack(bytes)
  if on_byte==0x1F and blink_byte==0x1F then
    for i=1, 8 do
      local name  = field_names[i]
      frame[name] = 'unknown'
    end
  else
    local on    = bit_explode(on_byte)
    local blink = bit_explode(blink_byte)
    for i=1, 8 do
      local status
      if on[i] then
        if blink[i] then status='blink' else status='on' end
      else -- on==false
        if blink[i] then status='inverted_blink' else status='off' end
      end
      local name  = field_names[i]
      frame[name] = status
    end
  end
end

--- Decodes a panel state frame, with command tag `"@"==0x40`, returning fields:
--  * `current_limit`, in amperes (can be string `low` or `ignore` depending
--   on the panel's state)
--  * `switch_position`, with a value among `"charger only", "inverter only",
--   "on", "off"`.
--  * `potentiometer` and `panel_scale`, if that info is provided by the panel.
--  * `generator_selected`, as a Boolean, if applicable.
--  * `is_extended`, indicating the format of the frame received.
--
function DECODE.panel(bytes, frame)
  local info_byte = bytes[1]
  frame.is_extended = bit32.band(info_byte, 0x8)~=0
  frame.panel_id    = bit32.rshift(info_byte, 4)
  local switch_names = { 'charger only', 'inverter only', 'on', 'off' }
  if frame.is_extended then
    frame.current_limit = get_number(bytes, 2, 2) / 10
    frame.switch_position = switch_names[bit32.band(info_byte, 0x3) + 1]
    frame.generator_selected = bit32.band(info_byte, 0x8)~=0
  else -- standard (non-extended) format
    frame.potentiometer   = bytes[2]
    frame.panel_scale     = bytes[3]
    frame.switch_position = switch_names[bit32.band(info_byte, 0x7)]
    if frame.potentiometer==0 then
      frame.current_limit = 'low'
    elseif frame.potentiometer==1 or frame.potentiometer==0xFF then
      frame.current_limit = 'ignore'
    else
      frame.current_limit = frame.panel_scale * 0x100 / frame.potentiometer
    end
  end
end

--- Parses responses to command 'F' asking for special info on a current line.
--  Current lines can be `'L1'...'L4'` or `'DC'` (batteries).
--
--  TODO: for DC line, I'd expect one of used_current or received_current
--  at least to be 0. If so I'll just provide a `current` signed field.
--
--  Fields provided:
--  * `phase_byte` (coded phase number);
--  * `phase_name` as a string;
--  * `voltage` in volts;
--  * for `DC` line only:
--  ** `used_current` in ampers;
--  ** `received_current` in ampers;
--  ** `inverter_period` in XXX;
--  * for `L?` lines only:
--  ** `bf_factor` (???)
--  ** `inverter_factor` (???);
--  ** `mains_current` in ampers;
--  ** `provided_current` in ampers;
--  ** `mains_period` in XXX.
function DECODE.info(bytes, frame)
  local phase_byte = bytes[5]
  local phase_names = { [5]='L4', [6]='L3', [7]='L2', [8]='L1', [9]='L1', 
    [0xA]='L1', [0xB]='L1', [0xC]='DC' }
  frame.phase_name = phase_names[phase_byte]
  if frame.phase_name=='L1' then frame.n_phases = phase_byte-7 end
  if frame.phase_name=='DC' then
    -- TODO: check meanings and conversions, command 'W'
    frame.voltage = get_number(bytes, 6, 2)/100
    frame.used_current = get_number(bytes, 8, 3)/100
    frame.provided_current = get_number(bytes, 11, 3)
    frame.inverter_period = bytes[14]/10
  else -- AC phase
    frame.bf_factor = bytes[1]
    frame.inverter_factor = bytes[2] -- TODO some conversion
    frame.mains_current = get_number(bytes, 8, 2)
    frame.voltage = get_number(bytes, 10, 2)/100
    frame.inverter_current = get_number(bytes, 12, 2)/10
    frame.mains_period = bytes[14]==255 and 'n/a' or bytes[14]/10
  end
end

--- Decodes a `'A'==0x41` frame, describing a MasterMultiLED's state.
function DECODE.multiled(bytes, frame)
  local config     = bytes[5]
  frame.last_input = bit32.band(config, 0x3)
  frame.overridden = bit32.band(config,0x4)~=0
  frame.minimum    = get_number(bytes,  6, 2) / 10
  frame.maximum    = get_number(bytes,  8, 2) / 10
  frame.actual     = get_number(bytes, 10, 2) / 10
end

return M