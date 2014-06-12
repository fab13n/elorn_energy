-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module victron.bmv
--  Reads and decodes VE.Direct frames.
--
--  This module is intended to be specialized for each actual VE.Direct device,
--  cf. for instance modules `victron.bmv` and `victron.mppt`.
--
--  VE-Direct Data format
--  =====================
--
--  VE-Direct devices send data as text over UART, mostly ASCII-7bits except
--  for the checksum byte (cf. below). The text is composed of frames,
--  themselves composed of lines of the form `"\13\10<label>\t<value>"`.
--  There is no explicit end-of-frame marker, but every frame ends with a line
--  whose label is `"Checksum"`.
--
--  Some devices, such as BMV monitors, emit more than one kind of frames,
--  and therefore require to read several consecutive frames to get a sample
--  of all the data.
--
--  Checksum lines have a single ASCII-8bits byte as there value, chosen so
--  that the sum of all bytes in the frame is a multiple of 0x100.

local checks = require 'checks'
local sched  = require 'sched'
local log    = require 'log'
local lock   = require 'sched.lock'
local serial = require 'serial'

local M = { }

M.prototype = {
  dev_file   = false,       --- no reasonable default
  timeout  = '1.5',         --- Duration of the data acquisition
  max_frame_length = 150,   --- longest possible size for a frame
  tmp_file = os.tmpname(),  --- File used to exchange between `cat` and this instance
  accuracy = { 0, 0 },      --- # of attempts / # of successes
  names   = false,
  units   = { },
  factors = { },
  initialized = false,
  n_frames = 1
}

local VED    = { }
local VED_MT = { __type='victron.ve-direct', __index=VED }

--- Gets everything sent by the BMS during `M.TIMEOUT`.
--
-- @param #ve_direct self a VE.Direct instance
-- @return #string the data acquired from UART
--

function VED :raw_data()
  lock.lock(self)
  self.uart :flush() -- TODO: make it timeout-based, so that reasonably fresh data might be kept readily available
  local r, msg = self.uart :read ((self.n_frames+1)*self.max_frame_length)
  lock.unlock(self)
  if r then
    log("VICTRON-VED", "DEBUG", "Acquired %d bytes", #r)
    return r
  else
    log("VICTRON-VED", "ERROR", "Can't read UART: %s", tostring(msg))
    return nil, msg
  end
end

--- Extracts a pair of consecutive frames from raw data,
--  by looking for "Checksum" lines.
--  the frames might be in any order (history first, or snapshot first).
--
-- @param #ve_direct self a VE.Direct instance
-- @return #string a consecutive pair of frames with correct checksums.
--
function VED :frames(n)
  checks('victron.ve-direct')
  local REGEXP = '\13\10Checksum\t.()'
  local raw_data, msg = self :raw_data()
  self.accuracy[1] = self.accuracy[1] + 1 -- one more attempt
  if not raw_data then return nil, msg end
  local checksums = { }
  -- find n+1 consecutive checksum lines in `raw_data`
  local last_position = 1
  for i=1,self.n_frames+1 do
    local next_position = string.match(raw_data, REGEXP, last_position)
    if not next_position then
      return nil, "Not enough Checksum lines found ("..(i-1).." in "..#raw_data.." bytes)"
    end
    checksums[i]  = next_position
    last_position = next_position
  end
  for i=1, self.n_frames-1 do
    if M.checksum(raw_data, checksums[i], checksums[i+1]-1) ~= 0 then
      return nil, "Bad checksum"
    end
  end
  self.accuracy[2] = self.accuracy[2] + 1 -- one more success
  local frames = raw_data :sub (checksums[1], checksums[self.n_frames+1]-1)
  log('VICTRON-VED', 'DEBUG', "Acquired %d frames totaling %d bytes", self.n_frames, #frames)
  return frames
end

--- Gets data, extracts a frame, cuts it into lines, converts them
--  with user-friendly names and to usual units (for numeric ones).
--
-- @param  #number n_retries number of retries in case of bad checksum
-- @return #table  the formatted data, as a Lua record.
--
function VED :record (n_retries)
  checks('victron.ve-direct', '?number')
  local frames, errmsg = self :frames()
  if not frames then 
    if n_retries and n_retries>0 then return self :record(n_retries-1)
    else return nil, errmsg end
  end
  local record = { }
  for line in frames :gmatch "[^\10\13]+" do
    local label, value = line :match '(..-)\t(.+)'
    local name = label and self.names[label]
    if label=='Checksum' then --pass
    elseif not label then
      log('VICTRON-VED', 'ERROR', "Invalid line: %q", line)
    else
      -- Try to apply conversions on the value
      local num_value, factor = tonumber(value), self.factors[label]
      local tf = type(factor)
      if tf=='table' then
        value = num_value or value
        value = factor[value] or value
      elseif tf=='function' then
        value = num_value or value
        value = factor(value)
      elseif tf=='number' and num_value then
        value = num_value / factor
      end
      -- Try to apply conversion on the label
      if self.names then
        local name=self.names[label]
        if name then label=name
        else log('VICTRON-VED', 'ERROR', "Unknown label: %q", label) end
      end
      record[label] = value
    end
  end
  return record
end

--- Checks that the part of string `frame` between indexes `a` and `b`
--  inclusive sum to 0 modulo 0x100. That's how Victron does checksums.
--  If this function doesn't return 0, data are corrupted.
--
-- @param  #string frame a string embedding the frame to check
-- @param  #number a index of the first char to check
-- @param  #number b index of the last char to check
-- @return #number the checksum, hopefully 0.
--
function M.checksum(frame, a, b)
  local bytes = { frame:byte(a,b) }
  local sum = 0
  for i=1,#bytes do sum=sum+bytes[i] end
  return sum%256
end

function M.new(cfg, dev_file)
  checks('table', 'string')
  local function clone(x)
    if type(x)~='table' then return x end
    local t={ }
    for k, v in pairs(x) do t[k]=clone(v) end
    return t
  end
  local instance=clone(M.prototype)
  for k, v in pairs(cfg) do
    if instance[k]==nil then return nil, 'invalid field name '..k end
    instance[k]=v
  end
  if dev_file then instance.dev_file = dev_file end
  if not instance.dev_file then return nil, 'missing dev_file' end
  local msg
  instance.uart, msg = serial.open(dev_file, { baudRate=19200 })
  if not instance.uart then return nil, msg end
  instance.uart:settimeout(instance.timeout)
  return setmetatable(instance, VED_MT)
end

return M