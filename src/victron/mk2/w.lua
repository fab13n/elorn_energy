-- W commands allow to do more advanced, and potentially more dangerous, stuff.
-- I don't need them for now, and I won't dare to test code for them on
-- MY inverter, on which my family depends, if I can help it :)

local W = { }

W.commands = {
  [0x05] = 'SendSoftwareVersionPart0',
  [0x06] = 'SendSoftwareVersionPart1',
  [0x0E] = 'GetSetDeviceState',
  [0x30] = 'ReadRAMVar',
  [0x31] = 'ReadSetting',
  [0x32] = 'WriteRAMVar',
  [0x33] = 'WriteSetting',
  [0x34] = 'WriteData',
  [0x35] = 'GetSettingInfo',
  [0x36] = 'GetRAMVarInfo' }

W.DeviceState_responses = {
  [0] = 'Down',
  [1] = 'Startup',
  [2] = 'Off',
  [3] = 'Device in slave mode',
  [4] = 'Invert full',
  [5] = 'Invert half',
  [6] = 'Invert AES',
  [7] = 'Power Assist',
  [8] = 'Bypass',
  [9] = 'Charge' }

W.DeviceState_Charge_Substate_responses = {
  [0] = 'Initializing',
  [1] = 'Bulk',
  [2] = 'Absorption',
  [3] = 'Float',
  [4] = 'Storage',
  [5] = 'Repeated Absorption',
  [6] = 'Forced Absorption',
  [7] = 'Equalise',
  [8] = 'Bulk stopped' }

W.RAMVariables = {
  [0]  = 'UMainsRMS',
  [1]  = 'IMainsRMS',
  [2]  = 'UInverterRMS',
  [3]  = 'IInverterRMS',
  [4]  = 'UBat',
  [5]  = 'IBat',
  [6]  = 'UBatRMS (RMS value of ripple voltage)',
  [7]  = 'Inverter Period Time (0.1s)',
  [8]  = 'Mains Period Time (0.1s)',
  [9]  = 'Signed AC Load Current ',
  [10] = 'Virtual switch position',
  [11] = 'Ignore AC input state',
  [12] = 'Multi functional relay state',
  [13] = 'Charge state' }

-- To send W commands, one needs first to set an address
-- Set address:
--    > 'A', 0bXXXX_XXX1, <address> with adress between 0-0x1F inclusive
--    < 'A', 0bXXXX_XXX1, <address>, 0x00
-- Check address:
--    > 'A', 0bXXXX_XXX0, <irrelevant>
--    < 'A', 0bXXXX_XXX0, <address>, 0x00
--
-- W commands:
--    > 'W', frame{1,3}
-- where each frame is made up of 3 bytes: W commands followed by 2 arg bytes
