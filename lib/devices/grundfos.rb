require_relative "../modbus/tcp"

class Devices
  class Grundfos
    using Modbus::TypeExtensions

    def initialize(host = "192.168.0.6", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(1)
    end

    # ============================================================
    # CONTROL REGISTERS [W] - Writing to pump
    # ============================================================

    # Control bits register (101)
    # Bit 0: Remote access request (0=Local, 1=Remote/bus control)
    # Bit 1: On/Off request (0=Off, 1=On)
    # Bit 2: Reset alarm (0=No reset, 1=Reset)
    # Bit 4: Copy to local (0=Don't copy, 1=Copy)
    # Bit 5: Enable max flow limit (0=Disabled, 1=Enabled)
    def remote_control=(enabled)
      write_control_bit(0, enabled)
    end

    def pump_on=(enabled)
      write_control_bit(1, enabled)
    end

    def reset_alarm
      write_control_bit(2, true)
    end

    def copy_to_local
      write_control_bit(4, true)
    end

    def max_flow_limit_enabled=(enabled)
      write_control_bit(5, enabled)
    end

    # Control mode (register 102)
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
    # 128: AUTOADAPT (PP)
    # 129: FLOWADAPT
    # 130: Closed-loop sensor
    # 131: AUTOADAPT (CP)
    CONTROL_MODES = {
      0 => "Constant speed",
      1 => "Constant frequency",
      3 => "Constant head",
      4 => "Constant pressure",
      5 => "Constant differential pressure",
      6 => "Proportional pressure",
      7 => "Constant flow",
      8 => "Constant temperature",
      9 => "Constant differential temperature",
      10 => "Constant level",
      128 => "AUTOADAPT (PP)",
      129 => "FLOWADAPT",
      130 => "Closed-loop sensor",
      131 => "AUTOADAPT (CP)",
    }.freeze

    def controlmode
      @modbus.read_holding_register(202)
    end

    def controlmode_name
      CONTROL_MODES[controlmode] || "Unknown"
    end

    def controlmode=(v)
      @modbus.write_holding_register(101, v)
    end

    # Operation mode (register 103)
    # 0: AutoControl (Normal)
    # 4: OpenLoopMinimum (min speed)
    # 6: OpenLoopMaximum (max speed)
    OPERATION_MODES = {
      0 => "AutoControl",
      4 => "OpenLoopMinimum",
      6 => "OpenLoopMaximum",
      7 => "UserCurve",
      8 => "StopButton",
      9 => "HandMode",
    }.freeze

    def operationmode
      @modbus.read_input_register(203)
    end

    def operationmode_name
      OPERATION_MODES[operationmode] || "Unknown"
    end

    def operationmode=(v)
      @modbus.write_holding_register(102, v)
    end

    # Setpoint (register 104) - 0.01% scale
    def setpoint
      @modbus.read_holding_register(307) / 100.0
    end

    def setpoint=(v)
      raise ArgumentError, "Setpoint must be between 0 and 100" unless (0..100).include?(v)
      @modbus.write_holding_register(103, (v * 100).to_i)
    end

    # Max flow limit (register 106) - 0.01 m3/h scale
    def max_flow_limit
      @modbus.read_input_register(344) / 100.0
    end

    def max_flow_limit=(v)
      @modbus.write_holding_register(105, (v * 100).to_i)
    end

    # Sensor feedback via fieldbus (register 109) - 0.01% scale
    def sensor_feedback=(v)
      @modbus.write_holding_register(108, (v * 100).to_i)
    end

    # PI controller settings
    def kp=(v)
      @modbus.write_holding_register(109, (v * 10).to_i)
    end

    def ti=(v)
      @modbus.write_holding_register(110, (v * 10).to_i)
    end

    def direct_control=(enabled)
      @modbus.write_holding_register(111, enabled ? 1 : 0)
    end

    # ============================================================
    # STATUS REGISTERS [R] - Reading pump status
    # ============================================================

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
        direction: v[7] == 1,  # 0=CW, 1=CCW
        remote_control: v[8] == 1,
        on: v[9] == 1,
        alarm: v[10] == 1,
        warning: v[11] == 1,
        forced_to_local: v[12] == 1,
        at_max_speed: v[13] == 1,
        at_min_speed: v[15] == 1,
      }
    end

    # Process feedback (register 202) - 0.01% scale
    def process_feedback
      @modbus.read_input_register(201) / 100.0
    end

    # Feedback sensor configuration
    SENSOR_UNITS = {
      0 => "bar", 1 => "mbar", 2 => "m", 3 => "kPa", 4 => "psi",
      5 => "ft", 6 => "m3/h", 7 => "m3/s", 8 => "l/s", 9 => "gpm",
      10 => "°C", 11 => "°F", 12 => "%", 13 => "K", 14 => "l/h",
    }.freeze

    def feedback_sensor
      v = @modbus.read_input_registers(208, 4)
      {
        unit: SENSOR_UNITS[v[0]] || "unknown",
        min: v[1],
        max: v[2],
        nom_frequency: v[3] / 10.0,  # Hz
      }
    end

    # Frequency limits (registers 213-214) - 0.01% of nominal
    def frequency_limits
      v = @modbus.read_input_registers(212, 3)
      {
        nominal: v[0] / 10.0,  # Hz
        min_pct: v[1] / 100.0,
        max_pct: v[2] / 100.0,
      }
    end

    # Setpoint range (registers 215-216) - 0.01% of sensor max
    def setpoint_range
      v = @modbus.read_input_registers(214, 2)
      {
        min_pct: v[0] / 100.0,
        max_pct: v[1] / 100.0,
      }
    end

    # Flow estimation state (register 221)
    def flow_estimation_state
      v = @modbus.read_input_register(220)
      case v
      when 0 then "within_range"
      when 1 then "below_range"
      when 2 then "above_range"
      else "unknown"
      end
    end

    # PI controller status (registers 222-224)
    def pi_controller
      v = @modbus.read_input_registers(221, 4)
      {
        kp: v[0] / 10.0,
        ti: v[1] / 10.0,  # seconds
        direct_control: v[2] == 1,
      }
    end

    # ============================================================
    # MEASURED DATA [R]
    # ============================================================

    def measurements
      v = @modbus.read_input_registers(300, 40)
      {
        head: v[0] / 1000.0,                    # bar (reg 301)
        flow: v[1] / 10.0,                      # m³/h (reg 302)
        relative_performance: v[2] / 100.0,    # % (reg 303)
        speed: v[3],                            # rpm (reg 304)
        frequency: v[4] / 10.0,                 # Hz (reg 305)
        digital_input: v[5],                    # raw (reg 306)
        digital_output: v[6],                   # raw (reg 307)
        actual_setpoint: v[7] / 100.0,          # % (reg 308)
        motor_current: v[8] / 10.0,             # A (reg 309)
        dc_link_voltage: v[9] / 10.0,           # V (reg 310)
        motor_voltage: v[10] / 10.0,            # V (reg 311)
        power: [v[11], v[12]].to_u32,           # W (reg 312-313)
        remote_flow: v[13] / 10.0,              # m³/h (reg 314)
        inlet_pressure: v[14] / 1000.0 - 1.0,   # bar, offset 1000 (reg 315)
        remote_pressure1: v[15] / 1000.0,       # bar (reg 316)
        feed_tank_level: v[16] / 100.0 - 100.0, # m, offset 10000 (reg 317)
        power_electronics_temp: kelvin_to_celsius(v[17] / 100.0), # °C (reg 318)
        motor_temp: kelvin_to_celsius(v[18] / 100.0),             # °C (reg 319)
        remote_temp1: kelvin_to_celsius(v[19] / 100.0),           # °C (reg 320)
        electronics_temp: kelvin_to_celsius(v[20] / 100.0),       # °C (reg 321)
        pump_liquid_temp: kelvin_to_celsius(v[21] / 100.0),       # °C (reg 322)
        bearing_temp_de: kelvin_to_celsius(v[22] / 100.0),        # °C (reg 323)
        bearing_temp_nde: kelvin_to_celsius(v[23] / 100.0),       # °C (reg 324)
        aux_sensor_input: v[24] / 100.0,        # % (reg 325)
        specific_energy: v[25],                 # Wh/m³ (reg 326)
        user_setpoint: v[37] / 100.0,           # % (reg 338)
        diff_pressure: v[38] / 1000.0,          # bar (reg 339)
      }
    end

    def counters
      # Operation time (reg 327-328), Powered time (reg 329-330), Torque (331),
      # Energy (reg 332-333), Starts (reg 334-335)
      v1 = @modbus.read_input_registers(326, 9)
      # Volume1 (reg 357-358), Volume2 (reg 361-362)
      v2 = @modbus.read_input_registers(356, 6)
      {
        operation_time: [v1[0], v1[1]].to_u32,     # hours
        powered_time: [v1[2], v1[3]].to_u32,       # hours
        energy: [v1[5], v1[6]].to_u32,             # kWh
        number_of_starts: [v1[7], v1[8]].to_u32,
        volume1: [v2[0], v2[1]].to_u32 / 100.0,    # m³
        volume2: [v2[4], v2[5]].to_u32 / 100.0,    # m³
      }
    end

    # Heat energy data (for heating systems with temp sensors)
    def heat_data
      v = @modbus.read_input_registers(351, 6)
      {
        heat_energy1: [v[0], v[1]].to_u32,       # kWh (reg 352-353)
        heat_power: [v[2], v[3]].to_u32,         # W (reg 354-355)
        heat_diff_temp: v[4] / 100.0,            # °C (reg 356)
      }
    end

    # ============================================================
    # ALARM/WARNING CODES
    # ============================================================

    ALARM_CODES = {
      0 => "No alarm",
      1 => "Leakage current",
      2 => "Missing phase",
      3 => "External fault signal",
      4 => "Too many restarts",
      7 => "Too many hardware shutdowns",
      14 => "Electronic DC-link protection (ERP)",
      16 => "Other",
      29 => "Turbine operation",
      30 => "Change bearings",
      31 => "Change varistor(s)",
      32 => "Overvoltage",
      40 => "Undervoltage",
      41 => "Undervoltage transient",
      42 => "Cut-in fault (dV/dt)",
      45 => "Voltage asymmetry",
      48 => "Overload",
      49 => "Overcurrent",
      50 => "Motor protection (MPF)",
      51 => "Blocked motor/pump",
      54 => "Motor protection 3-second limit",
      55 => "Motor current protection (MCP)",
      56 => "Underload",
      57 => "Dry-running",
      60 => "Low input power",
      62 => "Safe Torque Off activated",
      64 => "Overtemperature",
      65 => "Motor temperature high",
      66 => "Control electronics temp high",
      67 => "Frequency converter temp high",
      68 => "Water temperature high",
      70 => "Thermal relay 2 in motor",
      72 => "Hardware fault type 1",
      73 => "Hardware shutdown (HSD)",
      76 => "Internal communication fault",
      77 => "Communication fault twin-head",
      80 => "Hardware fault type 2",
      83 => "EEPROM FE parameter error",
      84 => "Memory access error",
      85 => "EEPROM BE parameter error",
      88 => "Sensor fault",
      89 => "Feedback sensor 1 fault",
      91 => "Temperature sensor 1 fault",
      93 => "Sensor 2 fault",
      96 => "Setpoint signal outside range",
      105 => "Electronic rectifier protection (ERP)",
      106 => "Electronic inverter protection (EIP)",
      135 => "GDS sensor fault",
      148 => "Motor bearing temp high (DE)",
      149 => "Motor bearing temp high (NDE)",
      155 => "Inrush fault",
      156 => "Internal freq converter comm fault",
      157 => "Real time clock error",
      159 => "CIM module connection lost",
      161 => "Sensor supply fault 5V",
      162 => "Sensor supply fault 24V",
      163 => "Motor protection measurement fault",
      164 => "LiqTec sensor fault",
      165 => "Analog input 1 fault",
      166 => "Analog input 2 fault",
      167 => "Analog input 3 fault",
      175 => "Temperature sensor 2 fault",
      176 => "Temperature sensor 3 fault",
      190 => "Sensor 1 limit exceeded",
      191 => "Sensor 2 limit exceeded",
      209 => "Non-return valve fault",
      215 => "Soft pressure buildup timeout",
      240 => "Lubricate bearings",
      241 => "Motor phase failure",
      242 => "Auto motor model recognition failed",
    }.freeze

    def alarm
      @modbus.read_input_register(204)
    end

    def alarm_name
      ALARM_CODES[alarm] || "Unknown (#{alarm})"
    end

    def warning
      @modbus.read_input_register(205)
    end

    def warning_name
      ALARM_CODES[warning] || "Unknown (#{warning})"
    end

    # ============================================================
    # DEVICE INFO [R]
    # ============================================================

    UNIT_FAMILIES = {
      0 => "-",
      1 => "MAGNA series",
      2 => "MGE series",
      7 => "Motor Protection Unit",
      17 => "Multi-E booster",
      21 => "MPC / Multi-B",
      25 => "CR Monitor",
      26 => "Dedicated Controls",
      28 => "CIU, SEG AutoAdapt",
      30 => "Smart digital dosing pump",
      38 => "MAGNA3 multi-pump",
      39 => "Multi-E model H/I",
      46 => "SP Controller CU 2X1",
      48 => "Level controller LC 2x1",
      255 => "N/A",
    }.freeze

    def device_info
      v = @modbus.read_input_registers(29, 9)
      {
        family: UNIT_FAMILIES[v[0]] || "Unknown",
        family_code: v[0],
        type: v[1],
        version: v[2],
        battery_state: v[3],
        software_version: bcd_to_string(v[4], v[5]),
        software_date: bcd_date(v[6], v[7]),
      }
    end

    def cim_info
      v = @modbus.read_input_registers(20, 9)
      {
        crc_errors: v[0],
        data_errors: v[1],
        version: v[2],
        modbus_address: v[3],
        tx_count: [v[4], v[5]].to_u32,
        rx_count: [v[6], v[7]].to_u32,
      }
    end

    # ============================================================
    # HEAD SETPOINT HELPERS (convenience methods)
    # ============================================================

    # Get feedback sensor max value for head calculations
    def feedback_max
      @modbus.read_input_register(210)
    end

    def feedback_unit
      SENSOR_UNITS[@modbus.read_input_register(208)] || "unknown"
    end

    # Head setpoint in sensor units (bar, m, kPa depending on config)
    def head_setpoint
      feedback_max * setpoint / 100.0
    end

    def head_setpoint=(v)
      max = feedback_max
      raise ArgumentError, "Head setpoint must be between 0 and #{max}" unless v >= 0 && v <= max
      self.setpoint = (v / max.to_f) * 100
    end

    private

    def write_control_bit(bit, value)
      current = @modbus.read_holding_register(100) rescue 0
      if value
        current |= (1 << bit)
      else
        current &= ~(1 << bit)
      end
      @modbus.write_holding_register(100, current)
    end

    def kelvin_to_celsius(k)
      k - 273.15
    end

    def bcd_to_string(hi, lo)
      # BCD format aa.bb.cc.dd
      format("%02x.%02x.%02x.%02x",
        (hi >> 8) & 0xFF, hi & 0xFF,
        (lo >> 8) & 0xFF, lo & 0xFF)
    end

    def bcd_date(day_month, year)
      # BCD format ddmm, yyyy
      day = ((day_month >> 12) & 0xF) * 10 + ((day_month >> 8) & 0xF)
      month = ((day_month >> 4) & 0xF) * 10 + (day_month & 0xF)
      y = ((year >> 12) & 0xF) * 1000 + ((year >> 8) & 0xF) * 100 +
          ((year >> 4) & 0xF) * 10 + (year & 0xF)
      "#{day}-#{month}-#{y}"
    end
  end
end
