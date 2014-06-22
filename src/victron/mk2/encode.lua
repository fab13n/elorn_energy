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
--     local mk2_encode = require 'victron.mk2.encode'
--     local encoder    = mk2_encode.new(uart)
--     encoder('state', 'on', 5.5) --switch on, don't draw more than 5.5A from mains.
--     ...
--     encoder('led') -- request a description of the LED panel
--     ...
--     encoder('frame', 'dc') -- request a description of the DC current line.
--     ...
--     encoder('version') -- request firmware version
--     ...
--
local M = { }

--- Takes a command as a list of bytes and strings, and encapsulates
--  it in an MK2 frame
--  (0xff marker, length, optional last 0xff escape and checksum).
--  @param input command and argument bytes, as a list of numbers and/or strings.
--  @return completed frame, as a list of integers between 0..255.
--  
-- @usage
-- t = mk2command('V',0x8e,0x3e,0x11,0x00,'B')
-- for _,x in ipairs(t) do io.write(string.format('%02x ',x)) end
-- 07 ff 56 8e 3e 11 00 42 85
-- 
function M.make_frame(input)
  checks('table')
  local bytes = { 0xff }
  for _, x in ipairs(input) do
    if type(x)=='number' then
      if x<0 or x>=0x100 or x~=math.floor(x) then error 'invalid byte' end
      table.insert(bytes, x)
    elseif type(x)=='string' then
      for _, k in ipairs { x:byte(s,1,-1) } do
        table.insert(bytes, k)
      end
    else
      return nil, 'invalid arg type '..type(x)
    end
  end
  if bytes[#bytes] == 0xff then table.insert(bytes, 0) end
  table.insert(bytes, 1, #bytes)
  local cks = 0
  for _, x in ipairs(bytes) do cks=cks-x end
  cks=cks%0x100
  table.insert(bytes, cks)
  --cks=0
  --for _, x in ipairs(bytes) do cks=cks+x end
  --assert(cks%0x100==0)
  return bytes
end

local ENCODE = { }
M.encoders=ENCODE

function M.encode(cmd_name, ...)
  local encoder = ENCODE[cmd_name]
  local bytes, msg
  if not encoder then
    bytes, msg = nil, 'Unknown command'
  elseif type(encoder)=='string' then
    bytes, msg = { encoder }, nil
  else
    bytes, msg = encoder(...)
  end
  if not bytes then return nil, msg end
  local msg_bytes = M.make_frame(bytes)
  return string.char(unpack(msg_bytes))
end

ENCODE.led = 'L'
ENCODE.version = 'V'

function ENCODE.state(switch, limit)
  checks('string', '?number')
  local switch_states = {charger=1,inverter=2,on=3,off=4}
  local ss = switch_states[switch:lower()]
  if not ss then error "invalid switch state" end
  if limit==nil then limit=0x8000 else limit=math.floor(10*limit) end
  return { 'S', ss, limit%0x100, math.floor(limit/0x100), 1, 0x80 }
end

function ENCODE.frame(type)
  checks('string')
  local frame_names={dc=0,ac=1,ac1=1,ac2=2,ac3=3,ac4=4,multiled=5}
  local ft = frame_names[type:lower()]
  if not ft then error "invalid frame type name" end
  return { 'F', ft }
end

return M