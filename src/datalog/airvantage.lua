-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module datalog.airvantage.
--  Accumulates and periodically sends data to an AirVantage server through
--  the embedded agent.

local log        = require 'log'
local sched      = require 'sched'
local bmv        = require 'victron.bmv'
local airvantage = require 'airvantage'
local timer      = require 'timer'

--- @module datalog.airvantage
--  Regularly log data and pushes it to an AirVantage server.
--  
local M = { }

-- TODO should be remotely configurable (stored in airvantage.tree)
M.PERIOD = 60
M.POLICY = "daily"

--- Airvantage data-staging tables
M.tables = { }
--- Data-providing local devices
M.devices = { }

--- Columns to report from BMV records
M.bmv_columns_list = { 
  'voltage', 'current', 'state_of_charge', 'time_to_go', 
  'power', 'timestamp' }
  
M.bmv_columns_set  = { }
for _, x in pairs(M.bmv_columns_list) do  M.bmv_columns_set[x]=true end

--- Removes unwanted columns, adds missing ones.
--  The record is modified in-place.
local function clean_bmv_record(record)
  for k in pairs(record) do
    if not M.bmv_columns_set[k] then record[k]=nil end
  end
  record.power = record.voltage * record.current
  record.timestamp = os.time()
end

--- Acquires and accumulates one BMV record.
--  @param with_greetings #boolean if true, sends model and version information
function M.log(with_greetings)
  local record, msg = M.devices.bmv :record()
  if not record then
    log('DATALOG-AIRVANTAGE', 'ERROR', "Can't read BMV data: %s", msg)
  else
    if with_greetings then
      local greetings_record = {
        model     = record.model,
        firmware  = record.firmware,
        timestamp = os.time() }
      M.asset :pushdata ('batteries', greetings_record, 'now')
    end
    clean_bmv_record(record)
    M.tables.bmv :pushrow(record)
  end
end

--- Start periodically logging
function M.start()
  if M.timer then return nil, "Already started" end
  log('DATALOG-AIRVANTAGE', 'INFO', "Start logging every %d seconds", M.PERIOD)
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
function M.init(bmv)
  checks('victron.ve-direct')
  airvantage.init()
  M.devices.bmv=bmv
  M.asset = airvantage.newasset 'boat'
  M.asset :start()
  M.tables.bmv = M.asset:newtable('batteries', M.bmv_columns_list, 'ram', M.POLICY)
end

return M