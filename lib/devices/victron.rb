require_relative "../modbus/tcp"

class Devices
  # Victron MultiPlus II GX inverter/charger
  # Modbus TCP with unit IDs: 100 = system, 227 = vebus
  class Victron
    using Modbus::TypeExtensions

    def initialize(host, port = 502)
      @transport = Modbus::TCP.new(host, port)
      @system = @transport.unit(100)
      @vebus = @transport.unit(228)
    end

    def close
      @transport.close
    end

    def measurements
      sys = @system.read_holding_registers(817, 28)
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

        # VEBus (unit 227), base register 3
        ac_input_voltage: vb[3 - 3] / 10.0,
        ac_input_current: [vb[6 - 3]].to_i16 / 10.0,
        ac_input_power: [vb[12 - 3]].to_i16,
        ac_output_voltage: vb[15 - 3] / 10.0,
        ac_output_current: vb[18 - 3] / 10.0,
        ac_output_power: [vb[23 - 3]].to_i16,
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
