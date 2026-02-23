require_relative "../modbus/tcp"

class Devices
  # Victron MultiPlus II GX inverter/charger
  # Modbus TCP with unit IDs: 100 = system, 225 = CAN-bus BMS battery, 228 = vebus
  class Victron
    using Modbus::TypeExtensions

    def initialize(host, port = 502)
      @transport = Modbus::TCP.new(host, port)
      @system = @transport.unit(100)
      @battery = @transport.unit(225)
      @vebus = @transport.unit(228)
    end

    def close
      @transport.close
    end

    def measurements
      sys = @system.read_holding_registers(817, 63)
      bat_ah = @battery.read_holding_registers(265, 1)
      bat_cycles = @battery.read_holding_registers(284, 1)
      bat_soh = @battery.read_holding_registers(304, 5)
      bat_temp = @battery.read_holding_registers(318, 2)
      bat_cell = @battery.read_holding_registers(1290, 2)
      vb = @vebus.read_holding_registers(3, 34)
      {
        # System (unit 100), base register 817
        ac_consumption: sys[817 - 817],
        grid_power: [sys[820 - 817]].to_i16,
        battery_voltage: sys[840 - 817] / 10.0,
        battery_current: [sys[841 - 817]].to_i16 / 10.0,
        battery_power: [sys[842 - 817]].to_i16,
        battery_soc: sys[843 - 817],
        battery_state: sys[844 - 817],

        # Battery (unit 225)
        consumed_amphours: bat_ah[0] / 10.0,
        charge_cycles: bat_cycles[0],
        state_of_health: bat_soh[0] / 10.0,
        max_charge_voltage: bat_soh[1] / 10.0,
        min_discharge_voltage: bat_soh[2] / 10.0,
        max_charge_current: bat_soh[3] / 10.0,
        max_discharge_current: bat_soh[4] / 10.0,
        min_cell_voltage: bat_cell[0] / 100.0,
        max_cell_voltage: bat_cell[1] / 100.0,
        min_cell_temperature: [bat_temp[0]].to_i16 / 10.0,
        max_cell_temperature: [bat_temp[1]].to_i16 / 10.0,

        # VEBus (unit 228), base register 3
        ac_input_voltage: vb[3 - 3] / 10.0,
        ac_input_current: [vb[6 - 3]].to_i16 / 10.0,
        ac_input_power: [sys[872 - 817], sys[873 - 817]].to_i32,
        ac_output_voltage: vb[15 - 3] / 10.0,
        ac_output_current: [vb[18 - 3]].to_i16 / 10.0,
        ac_output_power: [sys[878 - 817], sys[879 - 817]].to_i32,
        dc_current: [vb[27 - 3]].to_i16 / 10.0,
        state: vb[31 - 3],
        error: vb[32 - 3],
        mode: vb[33 - 3],
        alarm_high_temp: vb[34 - 3],
        alarm_low_battery: vb[35 - 3],
        alarm_overload: vb[36 - 3],
      }.freeze
    end
  end
end
