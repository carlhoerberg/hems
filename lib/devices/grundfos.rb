require_relative "../modbus/tcp"

class Devices
  class Grundfos
    using Modbus::TypeExtensions

    def initialize(host = "192.168.0.6", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    # 0: Constant speed
    # 1: Constant frequency
    # 3: Constant head
    # 4: Constant pressure
    # 5: Constant differential pressure
    # 6: Proportional pressure
    # 7: Constant flow
    # 8: Constant temperature
    # 9: Constant differential temperature
    # 10: Constant level
    # 128: AUTOADAPT
    # 129: FLOWADAPT
    # 130: Closed-loop sensor
    # 131: AUTOADAPT(CP)
    def controlmode
      @modbus.read_holding_register(202)
    end

    def controlmode=(v)
      @modbus.write_holding_register(101, v)
    end

    # Percentage
    def setpoint
      @modbus.read_holding_register(307) / 100.0
    end

    def setpoint=(v)
      raise ArgumentError, "Setpoint must be between 0 and 100" unless (0..100).include?(v)
      @modbus.write_holding_register(103, v * 100)
    end

    # Maximum head/pressure range in bar
    def max_pressure_range
      @modbus.read_input_register(216) / 100.0
    end

    # Head setpoint in bar
    def head_setpoint
      max_pressure_range * setpoint / 100.0
    end

    # Set head setpoint in bar
    def head_setpoint=(v)
      max = max_pressure_range
      raise ArgumentError, "Head setpoint must be between 0 and #{max} bar" unless (0..max).include?(v)
      self.setpoint = (v / max) * 100
    end

    def setpoint_unit
      v = @modbus.read_holding_register(208)
      case v
      when 0 then "bar"
      when 1 then "mbar"
      when 2 then "m"
      when 3 then "kPa"
      when 4 then "psi"
      when 5 then "ft"
      when 6 then "m3/h"
      when 7 then "m3/s"
      when 8 then "l/s"
      when 9 then "gpm"
      when 10 then "°C"
      when 11 then "°F"
      when 12 then "%"
      when 13 then "K"
      when 14 then "W"
      else raise ArgumentError, "Unknown setpoint unit: #{v}"
      end
    end

    # 0: Auto-control (normal, setpoint control according to selected control mode)
    # 4: OpenLoopMin (running at minimum speed)
    # 6: OpenLoopMax (running at maximum speed)
    # 7: UserCurve
    # 8: StopButton
    # 9: HandMode
    def operationmode
      @modbus.read_input_register(203)
    end

    def status
      v = @modbus.read_input_register(200)
      {
        low_flow_stop: v[0] == 1,
        copy_to_local: v[1] == 1,
        max_flow_limit_enabled: v[2] == 1,
        reset_alarm_ack: v[3] == 1,
        setpoint_influence: v[4] == 1,
        at_max_power: v[5] == 1,
        rotation: v[6] == 1,
        direction: v[7] == 1,
        accessmode: v[8] == 1,
        on_off: v[9] == 1,
        alarm: v[10] == 1,
        warning: v[11] == 1,
        forced_to_local: v[12] == 1,
        at_max_speed: v[13] == 1,
        at_min_speed: v[15] == 1,
      }
    end

    def measurements
      v = @modbus.read_input_registers(300, 26)
      w = @modbus.read_input_registers(337, 2)
      { 
        head: v[0] / 1000.0, # bar
        flow: v[1] / 10.0, # m3/h
        relative_performance: v[2] / 100.0, # %
        speed: v[3], # rpm
        frequency: v[4] / 10.0, # hz
        actual_setpoint: v[7] / 100.0, # %
        motor_current: v[8] / 10.0, # A
        dc_link_voltage: v[9] / 10.0, # Volt
        power: [v[11], v[12]].to_u32, # Watt
        electronic_temp: (v[20]  - 27315) / 100.0, # celsius (from kelvin)
        pump_liquid_temp: (v[21] - 27315) / 100.0 , # celsius (from kelvin)
        specific_energy_consumption: v[25], # Wh/m3
        user_setpoint: w[0] / 100.0, # %
        diff_pressure: w[0] / 1000.0, # bar, pressure between pump flanges
      }
    end

    def counters
      v = @modbus.read_input_registers(326, 9)
      w = @modbus.read_input_registers(356, 2)
      {
        operation_time: [v[0], v[1]].to_u32, # hours
        powered_time: [v[2], v[3]].to_u32, # hours
        energy: [v[5], v[6]].to_u32, # kWh
        number_of_starts: [v[7], v[8]].to_u32,
        pumped_volume: [w[0], w[1]].to_u32 * 0.01, # m3
      }
    end

    # Code Alarm/warning description
    # 1 Leakage current
    # 2 Missing phase
    # 3 External fault signal
    # 4 Too many restarts
    # 7 Too many hardware shutdowns
    # 14 Electronic DC-link protection activated (ERP)
    # 16 Other
    # 29 Turbine operation, impellers forced backwards
    # 30 Change bearings (specific service information)
    # 31 Change varistor(s) (specific service information)
    # 32 Overvoltage
    # 40 Undervoltage
    # 41 Undervoltage transient
    # 42 Cut-in fault (dV/dt)
    # 45 Voltage asymmetry
    # 48 Overload
    # 49 Overcurrent (i_line, i_dc, i_mo)
    # 50 Motor protection function, general shutdown (MPF)
    # 51 Blocked motor or pump
    # 54 Motor protection function, 3-second limit
    # 55 Motor current protection activated (MCP)
    # 56 Underload
    # 57 Dry-running
    # 60 Low input power
    # 62 Safe Torque Off activated
    # 64 Overtemperature
    # 65 Motor temperature 1 (t_m or t_mo or t_mo1)
    # 66 Control electronics temperature high
    # 67 Temperature too high, internal frequency converter module (t_m)
    # 68 Water temperature high
    # 70 Thermal relay 2 in motor, for example thermistor
    # 72 Hardware fault, type 1
    # 73 Hardware shutdown (HSD)
    # 76 Internal communication fault
    # 77 Communication fault, twin-head pump
    # 80 Hardware fault, type 2
    # 83 Verification error, FE parameter area (EEPROM)
    # 84 Memory access error
    # 85 Verification error, BE parameter area (EEPROM)
    # 88 Sensor fault
    # 89 Signal fault, (feedback) sensor 1
    # 91 Signal fault, temperature 1 sensor
    # 93 Signal fault, sensor 2
    # 96 Setpoint signal outside range
    # 105 Electronic rectifier protection activated (ERP)
    # 106 Electronic inverter protection activated (EIP)
    # 135 Signal fault, GDS sensor
    # 148 Motor bearing temperature high (Pt100) in drive end (DE)
    # 149 Motor bearing temperature high (Pt100) in non-drive end (NDE)
    # 155 Inrush fault
    # 156 Communication fault, internal frequency converter module
    # 157 Real time clock error
    # 159 The CIM module has lost connection to the product.
    # 161 Sensor supply fault, 5 V
    # 162 Sensor supply fault, 24 V
    # 163 Measurement fault, motor protection
    # 164 Signal fault, LiqTec sensor
    # 165 Signal fault, analog input 1
    # 166 Signal fault, analog input 2
    # 167 Signal fault, analog input 3
    # 175 Signal fault, temperature sensor 2
    # 176 Signal fault, temperature sensor 3
    # 190 Limit exceeded, sensor 1
    # 191 Limit exceeded, sensor 2
    # 209 Non-return valve fault
    # 215 Soft pressure buildup timeout
    # 240 Lubricate bearings (specific service information)
    # 241 Motor phase failure
    # 242 Automatic motor model recognition failed
    def alarm
      @modbus.read_input_register(205)
    end

    def warning
      @modbus.read_input_register(204)
    end
  end
end
