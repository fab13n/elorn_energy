-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module victron.bmv
--  Reads and decodes Victron BMV60x frames.
--
--  Since Lua might be a bit too slow to read without errors at 19200 bauds
--  without flow control, we delegate data acquisition to a separate process.
--
--  It could have been a C program that finds and writes back two consecutive
--  frames; but it turns out this program almost exists, it's called `cat`
--  (with a timeout, because we won't get any EOF from an UART).
--
--  So, this module runs `cat /dev/ttyXXX` for `M.TIMEOUT` seconds,
--  finds 3 `"Checksum"` lines, verifies the consistency of the 2 complete
--  frames it found, and cuts them in user-friendly Lua records. Moreover,
--  it converts the unusual units into standard ones: volts, ampere-hours etc.
--
--  BMV Data format
--  ===============
--
--  The BMV sends data as text over UART, mostly ASCII-7bits except for the
--  checksum byte (cf. below). The text is composed of frames, themselves
--  composed of lines of the form `"\13\10<label>\t<value>"`. There is no
--  explicit end-of-frame marker, but every frame ends with a line whose
--  label is `"Checksum"`.
--
--  Two frames are emitted every second: one with the instant state of the
--  device, and one with historical statistics. We want to collect the data
--  of both kinds of frames, so we need to collect two complete frames.
--  So without relying on timing clues, the simplest way to do that is to find
--  3 `"Checksum"` lines, and keep the data between after the 1st one and
--  after the 3rd one.
--
--  Checksum lines have a single ASCII-8bits byte as there value, chosen so
--  that the sum of all bytes in the frame is a multiple of 0x100.

-- TODO: the VE.Direct protocol seems very similar to that one. If so, the
-- common part about extracting frames and splitting lines should be turned
-- into objects which can be instantiated more than once, and specialized
-- with name and unit conversion tables.
-- Even otherwise, one might imagine systems with more than one battery monitor,
-- although that should be pretty uncommon.

local checks = require 'checks'
local sched  = require 'sched'
local log    = require 'log'
local lock   = require 'sched.lock'

local M = { }

--- Duration of the data acquisition
M.TIMEOUT          = "1.5s"
--- UART device
M.DEVICE           = "/dev/ttyAMA0"
--- File used to exchange between `cat` and this module
M.TMP_FILE         = os.tmpname() -- TODO Move to RAMFS
--- Configuration command for the UART
M.INIT_COMMAND     = "stty -F %DEVICE% speed 19200 cs8 -icrnl -ixon -icanon >/dev/null"
--- Data-acquisition command
M.GET_DATA_COMMAND = "timeout %TIMEOUT% cat %DEVICE% > %TMP_FILE%"

--- Number of record-reading attempts, number of successful readings.
--  If the former is significantly less than the latter, it might be worth
--  increasing `M.TIMEOUT` and/or checking the physical connection.
M.accuracy = { 0, 0 }

--- User-friendly names:
M.names = {
  BMV = 'model',
  FW  = 'firmware',
  AR  = 'alarm_reason',
  V   = 'voltage',
  VS  = 'voltage2',
  I   = 'current',
  CE  = 'consummed_energy',
  SOC = 'state_of_charge',
  TTG = 'time_to_go',
  H1  = 'discharge_max',
  H2  = 'discharge_last',
  H3  = 'discharge_average',
  H4  = 'discharge_n_cycles',
  H5  = 'discharge_n_full',
  H6  = 'ah_total',
  H7  = 'voltage_min',
  H8  = 'voltage_max',
  H9  = 'days_since_full_charge',
  H10 = 'n_auto_synchro',
  H11 = 'n_alarms_voltage_low',
  H12 = 'n_alarms_voltage_high',
  H13 = 'n_alarms_voltage2_low',
  H14 = 'n_alarms_voltage2_high',
  H15 = 'voltage2_min',
  H16 = 'voltage2_max',
  Relay = 'relay',
  Alarm = 'alarm',
}


-- Helper to generate `M.units`.
local units = {
  V='V', VS='V', I='A', CE='Ah', SOC='%', TTG='hours',
  H1='Ah', H2='Ah', H3='Ah', H6='Ah', H7='V', H8='V',
  H9='days', H15='V', H16='V'}

--- mane -> unit name correspondance table.
--  Not used by this module, but helpful for other modules exlpoiting the data.
M.units = { }; for k, v in pairs(units) do M.units[M.names[k]]=v end

--- Conversion factors, for values given in unusual units:
M.factor = {
  V   = 1000, -- mV      -> V
  VS  = 1000, -- mV      -> V
  I   = 1000, -- mA      -> A
  CE  = 1000, -- mAh     -> Ah
  SOC = 10,   -- per1000 -> percents
  TTG = 60,   -- minutes -> hours
  H1  = 1000, -- mAh     -> Ah
  H2  = 1000, -- mAh     -> Ah
  H3  = 1000, -- mAh     -> Ah
  H6  = 1000, -- mAh     -> Ah
  H7  = 1000, -- mV      -> V
  H8  = 1000, -- mV      -> V
  H9  = 86400,-- seconds -> days
  H15 = 1000, -- mV      -> V
  H16 = 1000, -- mV      -> V
}

--- Have we configured the UART yet?
M.initialized = false

--- Gets everything sent by the BMS during `M.TIMEOUT`.
--  @return #string the data acquired from UART
function M.raw_data()
  lock.lock(M) -- No parallel data acquisition!
  if not M.initialized then
    local init_cmd = M.INIT_COMMAND :gsub ('%%(.-)%%', M)
    log("VICTRON-BMV", "DEBUG", "Execute %s", init_cmd)
    os.execute(init_cmd)
    M.initialized = true
  end
  local cmd = M.GET_DATA_COMMAND :gsub ('%%(.-)%%', M)
  os.execute(cmd) -- result will be 124, return code for timeout
  log("VICTRON-BMV", "DEBUG", "Execute %s", cmd)
  local f = io.open(M.TMP_FILE, "r")
  local raw_data = f :read('*a')
  f :close()
  log('VICTRON-BMV', 'DEBUG', "Acquired %d bytes in %s", #raw_data, M.TIMEOUT)
  lock.unlock(M)
  return raw_data
end

--- Extracts a pair of consecutive frames from raw data,
--  by looking for "Checksum" lines.
--  the frames might be in any order (history first, or snapshot first).
--
-- @return #string a consecutive pair of frames with correct checksums.
--
function M.frame()
  local REGEXP = '\13\10Checksum\t.()'
  local raw_data = M.raw_data()
  M.accuracy[1] = M.accuracy[1] + 1 -- one more attempt
  local checksums = { }
  -- find 3 consecutive checksum lines in `raw_data`
  local last_position = 1
  for i=1,3 do
    local next_position = string.match(raw_data, REGEXP, last_position)
    if not next_position then
      return nil, "Not enough Checksum lines found ("..(i-1).." in "..#raw_data.." bytes)"
    end
    checksums[i]  = next_position
    last_position = next_position
  end
  if M.checksum(raw_data, checksums[1], checksums[2]-1) ~= 0 or
     M.checksum(raw_data, checksums[2], checksums[3]-1) ~= 0 then
     return nil, "Bad checksum"
  end
  M.accuracy[2] = M.accuracy[2] + 1 -- one more success
  local frame = raw_data :sub (checksums[1], checksums[3]-1)
  return frame
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

--- Gets data, extracts a frame, cuts it into lines, converts them
--  with user-friendly names and to usual units (for numeric ones).
--
-- @param  #number n_retries number of retries in case of bad checksum
-- @return #table  the formatted data, as a Lua record.
--
function M.record(n_retries)
  local frame, errmsg = M.frame()
  if not frame then 
    if n_retries and n_retries>0 then return M.record(n_retries-1)
    else return nil, errmsg end
  end
  local record = { }
  for line in frame :gmatch "[^\10\13]+" do
    local label, value = line :match '(..-)\t(.+)'
    local name = label and M.names[label]
    if label=='Checksum' then --pass
    elseif not label or not name then
      log('VICTRON-BMV', 'ERROR', "Unknown line from device: %q", line)
    else
      local num, factor = tonumber(value), M.factor[label]
      if num and factor then num = num / factor end
      record[name] = num or value
    end
  end
  return record
end

return M