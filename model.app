<?xml version="1.0" encoding="utf-8"?>
<app:application
    xmlns:app="http://www.sierrawireless.com/airvantage/application/1.0"
    type="elorn" name="Elorn Energy management" revision="0.4">
  <capabilities>
    <data>
      <encoding type="M3DA">
        <asset default-label="Boat" id="boat">

          <!-- Battery monitor -->
          <node default-label="Batteries" path="bmv">

            <!-- Sent once at boot -->
            <variable default-label="BMV Model" path="model" type="string"/>
            <variable default-label="BMV Firmware Version" path="firmware" type="string"/>

            <!-- Regularly monitored -->
            <variable default-label="Battery Voltage (V)" path="voltage" type="double"/>
            <variable default-label="Battery Current (A)" path="current" type="double"/>
            <variable default-label="State of charge (Ah)" path="state_of_charge" type="double"/>
            <variable default-label="Time-to-go (h)" path="time_to_go" type="double"/>
            <variable default-label="Battery Power (W)" path="power" type="double"/>
            <variable default-label="Consumed Energy (Ah)" path="consumed_energy" type="double"/>

          </node>

          <!-- Solar controller -->
          <node default-label="Solar Controller" path="mppt">

            <!-- Sent once at boot -->
            <variable default-label="MPPT Model" path="product_id" type="string"/>
            <variable default-label="MPPT Firmware Version" path="firmware" type="string"/>

            <!-- Regularly monitored -->
            <variable default-label="MPPT Voltage Batteries (V)" path="voltage_battery" type="double"/>
            <variable default-label="MPPT Current Batteries (A)" path="current_battery" type="double"/>
            <variable default-label="Voltage Panels (V)" path="voltage_panels" type="double"/>
            <variable default-label="Power Panels (W)" path="power_panels" type="double"/>
            <variable default-label="MPPT Converter State" path="converter_state" type="string"/>
            <variable default-label="Solar Yield Total (kWh)" path="yield_total" type="double"/>
            <variable default-label="Solar Yield Today (kWh)" path="yield_today" type="double"/>
            <variable default-label="Solar Yield Yesterday (kWh)" path="yield_yesterday" type="double"/>
            <variable default-label="Max Solar Power Today (W)" path="power_max_today" type="double"/>
            <variable default-label="Max Solar Power Yesterday (W)" path="power_max_yesterday" type="double"/>

          </node>
        </asset>
      </encoding>
    </data>
  </capabilities>
</app:application>
