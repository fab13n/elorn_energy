-- (c) Fabien Fleutot, 2014.
-- Released under the MIT public license.

--- @module victron.bmv
--  Reads and decodes Victron BlueSolar MPPT75/50 frames.
--
--  This module generates specific instances of the more generic handlers
--  provided by `victron.ve-direct`.
--

-- Incoming Frame example:
--     PID 0xA040
--     FW  111
--     SER#  HQ1337Z6DQA
--     V 26810
--     I 10200
--     VPV 30510
--     PPV 282
--     CS  3
--     ERR 0
--     H19 3461
--     H20 117
--     H21 1113
--     H22 568
--     H23 1374
--     Checksum  ?

local checks = require 'checks'
local ved    = require 'victron.ve-direct'

--- Instance prototype
local P = { n_frames=1 }

local M = { prototype=P }

--- User-friendly names:
P.names = {
  PID = 'product_id',
  FW  = 'firmware',
  V   = 'voltage_battery',
  I   = 'current_battery',
  ['SER#'] = 'serial_number',
  VPV = 'voltage_panels',
  PPV = 'power_panels',
  CS  = 'converter_state',
  ERR = 'error_code',
  H19 = 'yield_total',
  H20 = 'yield_today',
  H21 = 'power_max_today',
  H22 = 'yield_yesterday',
  H23 = 'power_max_yesterday'
}

-- Helper to generate `P.units`.
local units = {
  V='V', I='A', VPV='V', PPV='W',
  H19='kWh', H20='kWh', H21='W', H22='kWh', H23='W' }

--- mane -> unit name correspondance table.
--  Not used by this module, but helpful for other modules exlpoiting the data.
P.units = { }; for k, v in pairs(units) do P.units[P.names[k]]=v end

--- Conversion factors, for values given in unusual units:
P.factors = {
  V   = 1000, -- mV      -> V
  I   = 1000, -- mA      -> A
  VPV = 1000, -- mV      -> V
  H19 = 100,  -- DWh     ->kWh
  H20 = 100,  -- DWh     ->kWh
  H22 = 100,  -- DWh     ->kWh
  PID = { 
    ['0x300'] ='BlueSolar MPPT 70/15',
    ['0xA040']='BlueSolar MPPT 75/50',
    ['0xA042']='BlueSolar MPPT 75/15',
    ['0xA043']='BlueSolar MPPT 100/15' },
  CS  = { [0]='Off', [2]='Fault', [3]='Bulk', [4]='Absorption', [5]='Float' }
}


function M.new(dev_file)
  checks('string')
  return ved.new(M.prototype, dev_file) 
end

return M