require_relative "../modbus/tcp"

class Devices
  # GenComm standard for generating set control equipment
  # Developed by Deep Sea Electronics, used by various manufacturers
  class GenComm
    using Modbus::TypeExtensions

    # GenComm page addresses
    PAGE_STATUS = 0x0300          # Page 3 - Status
    PAGE_BASIC = 0x0400           # Page 4 - Basic Instrumentation
    PAGE_EXTENDED = 0x0500        # Page 5 - Extended Instrumentation
    PAGE_DERIVED = 0x0600         # Page 6 - Derived Instrumentation
    PAGE_ACCUMULATED = 0x0700     # Page 7 - Accumulated Instrumentation
    PAGE_CONTROL = 0x1000         # Page 16 - Control
    PAGE_EXTENDED2 = 0x1300       # Page 19 - Extended Instrumentation 2
    PAGE_NAMED_ALARMS = 0x9A00    # Page 154 - Named Alarm Conditions

    # Alarm condition codes
    ALARM_CONDITIONS = {
      0 => nil,                    # Disabled
      1 => nil,                    # Not active
      2 => "Warning",
      3 => "Shutdown",
      4 => "Electrical trip",
      5 => "Controlled shutdown",
      8 => nil,                    # Inactive indication
      9 => nil,                    # Inactive indication
      10 => "Active",
      15 => nil,                   # Unimplemented
    }.freeze

    # Named alarms for 72xx/73xx/61xx/74xx MKII family (register, nibble => name)
    # Nibbles: 3=bits 13-16, 2=bits 9-12, 1=bits 5-8, 0=bits 1-4
    NAMED_ALARMS_73XX = {
      [1, 3] => "Emergency stop",
      [1, 2] => "Low oil pressure",
      [1, 1] => "High coolant temperature",
      [1, 0] => "Low coolant temperature",
      [2, 3] => "Under speed",
      [2, 2] => "Over speed",
      [2, 1] => "Generator under frequency",
      [2, 0] => "Generator over frequency",
      [3, 3] => "Generator low voltage",
      [3, 2] => "Generator high voltage",
      [3, 1] => "Battery low voltage",
      [3, 0] => "Battery high voltage",
      [4, 3] => "Charge alternator failure",
      [4, 2] => "Fail to start",
      [4, 1] => "Fail to stop",
      [4, 0] => "Generator fail to close",
      [5, 3] => "Mains fail to close",
      [5, 2] => "Oil pressure sender fault",
      [5, 1] => "Loss of magnetic pick up",
      [5, 0] => "Magnetic pick up open circuit",
      [6, 3] => "Generator high current",
      [6, 2] => "Calibration lost",
      [6, 1] => "Low fuel level",
      [6, 0] => "CAN ECU Warning",
      [7, 3] => "CAN ECU Shutdown",
      [7, 2] => "CAN ECU Data fail",
      [7, 1] => "Low oil level switch",
      [7, 0] => "High temperature switch",
      [8, 3] => "Low fuel level switch",
      [8, 2] => "Expansion unit watchdog alarm",
      [8, 1] => "kW overload alarm",
      [8, 0] => "Negative phase sequence current alarm",
      [9, 3] => "Earth fault trip alarm",
      [9, 2] => "Generator phase rotation alarm",
      [9, 1] => "Auto Voltage Sense Fail",
      [9, 0] => "Maintenance alarm",
      [10, 3] => "Loading frequency alarm",
      [10, 2] => "Loading voltage alarm",
      [10, 1] => "Fuel usage running",
      [10, 0] => "Fuel usage stopped",
      [11, 3] => "Protections disabled",
      [11, 2] => "Protections blocked",
      [11, 1] => "Generator Short Circuit",
      [11, 0] => "Mains High Current",
      [12, 3] => "Mains Earth Fault",
      [12, 2] => "Mains Short Circuit",
      [12, 1] => "ECU protect",
      [12, 0] => "ECU Malfunction",
      [13, 3] => "ECU Information",
      [13, 2] => "ECU Shutdown",
      [13, 1] => "ECU Warning",
      [13, 0] => "ECU Electrical Trip",
      [14, 3] => "ECU After treatment",
      [14, 2] => "ECU Water In Fuel",
      [14, 1] => "Generator Reverse Power",
      [14, 0] => "Generator Positive VAr",
      [15, 3] => "Generator Negative VAr",
      [15, 2] => "LCD Heater Low Voltage",
      [15, 1] => "LCD Heater High Voltage",
      [15, 0] => "DEF Level Low",
      [16, 3] => "SCR Inducement",
      [16, 2] => "MSC Old version",
      [16, 1] => "MSC ID alarm",
      [16, 0] => "MSC failure",
      [17, 3] => "MSC priority Error",
      [17, 2] => "Fuel Sender open circuit",
      [17, 1] => "Over speed runaway",
      [17, 0] => "Over frequency run away",
      [18, 3] => "Coolant sensor open circuit",
      [18, 2] => "Remote display link lost",
    }.freeze

    # Control keys (write to PAGE_CONTROL+8 and ones-complement to PAGE_CONTROL+9)
    CONTROL_STOP = 35700
    CONTROL_AUTO = 35701
    CONTROL_MANUAL = 35702
    CONTROL_RESET_ALARMS = 35734
    CONTROL_DPF_REGEN_INHIBIT_ON = 35769
    CONTROL_DPF_REGEN_INHIBIT_OFF = 35770
    CONTROL_DPF_REGEN_START = 35771
    CONTROL_DPF_REGEN_STOP = 35785

    def initialize(host, port = 502, unit: 1)
      @modbus = Modbus::TCP.new(host, port).unit(unit)
    end

    def close
      @modbus.close
    end

    # Control commands
    def stop
      send_control(CONTROL_STOP)
    end

    def auto
      send_control(CONTROL_AUTO)
    end

    def manual
      send_control(CONTROL_MANUAL)
    end

    def reset_alarms
      send_control(CONTROL_RESET_ALARMS)
    end

    def dpf_regen_inhibit_on
      send_control(CONTROL_DPF_REGEN_INHIBIT_ON)
    end

    def dpf_regen_inhibit_off
      send_control(CONTROL_DPF_REGEN_INHIBIT_OFF)
    end

    def dpf_regen_start
      send_control(CONTROL_DPF_REGEN_START)
    end

    def dpf_regen_stop
      send_control(CONTROL_DPF_REGEN_STOP)
    end

    # Status (Page 3)
    def control_mode
      @modbus.read_holding_register(PAGE_STATUS + 4)
    end

    def control_mode_name
      case control_mode
      when 0 then :stop
      when 1 then :auto
      when 2 then :manual
      when 3 then :test
      when 4 then :off_load_test
      when 5 then :load_test
      when 6 then :battery_test
      else :unknown
      end
    end

    def status_flags
      v = @modbus.read_holding_register(PAGE_STATUS + 6)
      {
        control_not_configured: v[0] == 1,
        control_failure: v[14] == 1,
        shutdown_alarm: v[13] == 1,
        electrical_trip: v[12] == 1,
        warning_alarm: v[11] == 1,
        telemetry_alarm: v[10] == 1,
      }
    end

    def dpf_status
      d = @modbus.read_holding_registers(PAGE_EXTENDED2 + 4, 19)
      e = @modbus.read_holding_registers(PAGE_EXTENDED + 184, 1)
      e2 = @modbus.read_holding_registers(PAGE_EXTENDED + 195, 5)
      {
        regen_status: d[0],
        auto_regen_inhibit: e[0],
        aftertreatment_status_reason: e2[0],
        aftertreatment_status_severity: e2[1],
        time_until_action_needed: e2[2],
        time_until_torque_reduction: e2[3],
        time_until_speed_reduction: e2[4],
        inhibit_accelerator_off_idle: d[12],
        inhibit_out_of_neutral: d[13],
        inhibit_parking_brake_not_set: d[14],
        inhibit_low_exhaust_temp: d[15],
        inhibit_system_timeout: d[16],
        inhibit_permanent_lockout: d[17],
        inhibit_system_fault: d[18],
      }
    end

    # Named Alarm Conditions (Page 154) - returns hash of active alarms
    def named_alarms
      regs = @modbus.read_holding_registers(PAGE_NAMED_ALARMS + 1, 18)
      alarms = {}
      regs.each_with_index do |reg, idx|
        register = idx + 1
        4.times do |nibble|
          shift = nibble * 4
          code = (reg >> shift) & 0x0F
          condition = ALARM_CONDITIONS[code]
          next unless condition

          name = NAMED_ALARMS_73XX[[register, nibble]]
          next unless name

          alarms[name] = condition
        end
      end
      alarms.freeze
    end

    def is_running?
      rpm > 0
    end

    # Basic Instrumentation (Page 4)
    def oil_pressure
      @modbus.read_holding_register(PAGE_BASIC + 0)
    end

    def coolant_temperature
      [@modbus.read_holding_register(PAGE_BASIC + 1)].to_i16
    end

    def oil_temperature
      [@modbus.read_holding_register(PAGE_BASIC + 2)].to_i16
    end

    def fuel_level
      @modbus.read_holding_register(PAGE_BASIC + 3)
    end

    def charge_alternator_voltage
      @modbus.read_holding_register(PAGE_BASIC + 4) / 10.0
    end

    def battery_voltage
      @modbus.read_holding_register(PAGE_BASIC + 5) / 10.0
    end

    def rpm
      @modbus.read_holding_register(PAGE_BASIC + 6)
    end

    def frequency
      @modbus.read_holding_register(PAGE_BASIC + 7) / 10.0
    end

    # Generator voltages (32-bit values)
    def voltage_l1_n
      @modbus.read_holding_registers(PAGE_BASIC + 8, 2).to_u32 / 10.0
    end

    def voltage_l2_n
      @modbus.read_holding_registers(PAGE_BASIC + 10, 2).to_u32 / 10.0
    end

    def voltage_l3_n
      @modbus.read_holding_registers(PAGE_BASIC + 12, 2).to_u32 / 10.0
    end

    def voltage_l1_l2
      @modbus.read_holding_registers(PAGE_BASIC + 14, 2).to_u32 / 10.0
    end

    def voltage_l2_l3
      @modbus.read_holding_registers(PAGE_BASIC + 16, 2).to_u32 / 10.0
    end

    def voltage_l3_l1
      @modbus.read_holding_registers(PAGE_BASIC + 18, 2).to_u32 / 10.0
    end

    # Generator currents (32-bit values)
    def current_l1
      @modbus.read_holding_registers(PAGE_BASIC + 20, 2).to_u32 / 10.0
    end

    def current_l2
      @modbus.read_holding_registers(PAGE_BASIC + 22, 2).to_u32 / 10.0
    end

    def current_l3
      @modbus.read_holding_registers(PAGE_BASIC + 24, 2).to_u32 / 10.0
    end

    def current_earth
      @modbus.read_holding_registers(PAGE_BASIC + 26, 2).to_u32 / 10.0
    end

    # Generator power (32-bit signed values)
    def watts_l1
      @modbus.read_holding_registers(PAGE_BASIC + 28, 2).to_i32
    end

    def watts_l2
      @modbus.read_holding_registers(PAGE_BASIC + 30, 2).to_i32
    end

    def watts_l3
      @modbus.read_holding_registers(PAGE_BASIC + 32, 2).to_i32
    end

    def watts_total
      watts_l1 + watts_l2 + watts_l3
    end

    def kw_total
      watts_total / 1000.0
    end

    # Accumulated Instrumentation (Page 7)
    def engine_run_time
      @modbus.read_holding_registers(PAGE_ACCUMULATED + 6, 2).to_u32
    end

    def engine_run_hours
      engine_run_time / 3600.0
    end

    def kwh
      @modbus.read_holding_registers(PAGE_ACCUMULATED + 8, 2).to_u32 / 10.0
    end

    def start_counter
      @modbus.read_holding_registers(PAGE_ACCUMULATED + 16, 2).to_u32
    end

    def currents
      [current_l1, current_l2, current_l3]
    end

    # Read all basic measurements in one batch
    def measurements
      m = @modbus.read_holding_registers(PAGE_BASIC, 64)
      {
        oil_pressure: m[0],
        coolant_temperature: [m[1]].to_i16,
        oil_temperature: [m[2]].to_i16,
        fuel_level: m[3],
        charge_alternator_voltage: m[4] / 10.0,
        battery_voltage: m[5] / 10.0,
        rpm: m[6],
        frequency: m[7] / 10.0,
        voltage_l1_n: [m[8], m[9]].to_u32 / 10.0,
        voltage_l2_n: [m[10], m[11]].to_u32 / 10.0,
        voltage_l3_n: [m[12], m[13]].to_u32 / 10.0,
        voltage_l1_l2: [m[14], m[15]].to_u32 / 10.0,
        voltage_l2_l3: [m[16], m[17]].to_u32 / 10.0,
        voltage_l3_l1: [m[18], m[19]].to_u32 / 10.0,
        current_l1: [m[20], m[21]].to_u32 / 10.0,
        current_l2: [m[22], m[23]].to_u32 / 10.0,
        current_l3: [m[24], m[25]].to_u32 / 10.0,
        current_earth: [m[26], m[27]].to_u32 / 10.0,
        watts_l1: [m[28], m[29]].to_i32,
        watts_l2: [m[30], m[31]].to_i32,
        watts_l3: [m[32], m[33]].to_i32,
      }.merge(extended_measurements).merge(derived_measurements).freeze
    end

    # Read extended instrumentation (Page 5)
    def extended_measurements
      e1 = @modbus.read_holding_registers(PAGE_EXTENDED, 12)
      e2 = @modbus.read_holding_registers(PAGE_EXTENDED + 66, 6)
      e3 = @modbus.read_holding_registers(PAGE_EXTENDED + 186, 2)
      e4 = @modbus.read_holding_registers(PAGE_EXTENDED2 + 4, 1)
      {
        turbo_pressure: e1[4],
        fuel_consumption: [e1[10], e1[11]].to_u32 / 100.0,
        aftertreatment_temp: [e2[0]].to_i16,
        engine_torque_pct: [e2[4], e2[5]].to_i32,
        soot_load: e3[0],
        ash_load: e3[1],
        dpf_regen_status: e4[0],
      }.freeze
    end

    # Read derived instrumentation (Page 6) for VA, Var, and load percentage values
    def derived_measurements
      d = @modbus.read_holding_registers(PAGE_DERIVED, 24)
      d2 = @modbus.read_holding_registers(PAGE_DERIVED + 82, 3)
      {
        kva_l1: [d[2], d[3]].to_u32 / 1000.0,
        kva_l2: [d[4], d[5]].to_u32 / 1000.0,
        kva_l3: [d[6], d[7]].to_u32 / 1000.0,
        kvar_l1: [d[10], d[11]].to_i32 / 1000.0,
        kvar_l2: [d[12], d[13]].to_i32 / 1000.0,
        kvar_l3: [d[14], d[15]].to_i32 / 1000.0,
        pct_full_power: [d[22]].to_i16 / 10.0,
        pct_full_var: [d[23]].to_i16 / 10.0,
        load_pct_l1: [d2[0]].to_i16 / 10.0,
        load_pct_l2: [d2[1]].to_i16 / 10.0,
        load_pct_l3: [d2[2]].to_i16 / 10.0,
      }.freeze
    end

    # Read accumulated instrumentation
    def accumulated
      m = @modbus.read_holding_registers(PAGE_ACCUMULATED, 18)
      {
        current_time: [m[0], m[1]].to_u32,
        time_to_maintenance: [m[2], m[3]].to_i32,
        time_of_maintenance: [m[4], m[5]].to_u32,
        engine_hours: [m[6], m[7]].to_u32 / 3600.0,
        kwh_positive: [m[8], m[9]].to_u32 / 10.0,
        kwh_negative: [m[10], m[11]].to_u32 / 10.0,
        kvah: [m[12], m[13]].to_u32 / 10.0,
        kvarh: [m[14], m[15]].to_u32 / 10.0,
        start_counter: [m[16], m[17]].to_u32,
      }.freeze
    end

    def status
      @modbus.read_holding_register(PAGE_STATUS + 6)
    end

    private

    def send_control(key)
      complement = key ^ 0xFFFF
      @modbus.write_holding_registers(PAGE_CONTROL + 8, [key, complement])
    end
  end
end
