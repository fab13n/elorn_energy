-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module datalog.airvantage.
--  Accumulates and periodically sends data to an AirVantage server through
--  the embedded agent.

local log        = require 'log'
local sched      = require 'sched'
local airvantage = require 'airvantage'
local timer      = require 'timer'
local devicetree = require 'devicetree'

--- @module datalog.airvantage
--  Regularly log data and pushes it to an AirVantage server.
--  
local M = { }

-- TODO should be remotely configurable (stored in airvantage.tree)
M.PERIOD = 60 -- in seconds
M.DEFAULT_POLICY_LATENCY = 3600 -- in seconds

--- Airvantage data-staging tables
M.tables = { }
--- Data-providing local devices
M.assets = assets

--- Columns to report from BMV records

M.column_list = { }
M.column_list.bmv = { 
  'voltage', 'current', 'state_of_charge', 'time_to_go', 
  'power', 'timestamp', 'consumed_energy' }

M.column_list.mppt = {
  'power_max_today',
  -- 'yield_yesterday',
  'power_panels',
  'yield_total',
  --'product_id',
  --'error_code',
  'converter_state',
  --'serial_number',
  -- 'power_max_yesterday',
  'yield_today',
  'current_battery',
  'voltage_battery',
  'voltage_panels',
  -- 'firmware',
  'timestamp'
}

M.column_set = { }

for name, list in pairs(M.column_list) do
  local set = { }
  M.column_set[name]=set
  for _, x in pairs(list) do  set[x]=true end
end

--- Removes unwanted columns, adds missing ones.
--  The record is modified in-place.
local function clean_record(record, set)
  for k in pairs(record) do
    if not set[k] then record[k]=nil end
  end
  record.timestamp = os.time()
end

--- Acquires and accumulates one BMV record.
--  @param with_greetings #boolean if true, sends model and version information
function M.log_bmv(with_greetings)
  local record, msg = M.assets.bmv :record()
  if not record then
    log('DATALOG-AIRVANTAGE', 'ERROR', "Can't read BMV data: %s", msg)
  else
    if with_greetings then
      local greetings_record = {
        model     = record.model,
        firmware  = record.firmware,
        timestamp = os.time() }
      M.asset :pushdata ('bmv', greetings_record, 'now')
    end
    clean_record(record, M.column_set.bmv)
    if tonumber(record.voltage) and tonumber(record.current) then
      record.power = record.voltage * record.current
    end
    M.tables.bmv :pushrow(record)
  end
end

--- Acquires and accumulates one BMV record.
--  @param with_greetings #boolean if true, sends model and version information
function M.log_mppt(with_greetings)
  local record, msg = M.assets.mppt :record()
  if not record then
    log('DATALOG-AIRVANTAGE', 'ERROR', "Can't read MPPT data: %s", msg)
  else
    if with_greetings then
      local greetings_record = {
        yield_yesterday = record.yield_yesterday,
        power_max_yesterday = record.power_max_yesterday,
        product_id = record.product_id,
        serial_number = record.serial_number,
        firmware = record.firmware,
        timestamp = os.time() }
      M.asset :pushdata ('mppt', greetings_record, 'now')
    end
    clean_record(record, M.column_set.mppt)
    M.tables.mppt :pushrow(record)
  end
end

function M.log(with_greetings)
  M.log_bmv(with_greetings)
  M.log_mppt(with_greetings)
end

--- Start periodically logging
function M.start()
  if M.timer then return nil, "Already started" end
  log('DATALOG-AIRVANTAGE', 'INFO', "Start logging electrical data")
  M.log(true)
  M.timer = timer.new(-math.abs(M.PERIOD), M.log)
  return 'ok'
end

--- Stops periodically logging
function M.stop()
  if not M.timer then return nil, "Was not started" end
  M.timer :cancel()
  M.timer=nil
  return 'ok'
end

--- Initializes the agent and logging tables.
function M.init(assets)
  checks('table')
  airvantage.init()
  devicetree.init()
  local _, policy = devicetree.get('config.data.policy.electricity_uploads')
  if not policy then
    devicetree.set('config.data.policy.electricity_uploads.latency', M.DEFAULT_POLICY_LATENCY)
    log('DATALOG-AIRVANTAGE', 'ERROR', "Missing policy. Fixed, but the application needs to restart")
    os.exit(-1)
  end
  M.assets=assets
  M.asset = airvantage.newasset 'boat'
  M.asset :start()
  
  M.tables.bmv = assert(M.asset:newtable('bmv', M.column_list.bmv, 'ram', 'electricity_uploads'))
  M.tables.mppt = assert(M.asset:newtable('mppt', M.column_list.mppt, 'ram', 'electricity_uploads'))
end

return M