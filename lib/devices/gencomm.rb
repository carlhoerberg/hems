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
    PAGE_ALARM = 0x0800           # Page 8 - Alarm Conditions
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

    # Status flags register bits (PAGE_STATUS + 6)
    STATUS_FLAGS = {
      0 => "Control unit not configured",
      7 => "Controlled shutdown alarm",
      8 => "No font file",
      9 => "Satellite telemetry alarm",
      10 => "Telemetry alarm",
      11 => "Warning alarm",
      12 => "Electrical trip",
      13 => "Shutdown alarm",
      14 => "Control unit failure",
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
    CONTROL_CLEAR_TELEMETRY_ALARM = 35735

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

    def clear_telemetry_alarm
      send_control(CONTROL_CLEAR_TELEMETRY_ALARM)
    end

    def set_time(time = Time.now)
      timestamp = time.to_i
      high = (timestamp >> 16) & 0xFFFF
      low = timestamp & 0xFFFF
      @modbus.write_holding_registers(PAGE_ACCUMULATED, [high, low])
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
      e = @modbus.read_holding_registers(PAGE_EXTENDED + 122, 3)
      e2 = @modbus.read_holding_registers(PAGE_EXTENDED + 184, 1)
      e3 = @modbus.read_holding_registers(PAGE_EXTENDED + 195, 5)
      e4 = @modbus.read_holding_registers(PAGE_EXTENDED + 222, 3)
      {
        regen_status: u16(d[0]),
        dptc_filter_lamp: u16(e[0]),
        dptc_regen_forced: u16(e[2]),
        auto_regen_inhibit: u16(e2[0]),
        aftertreatment_status_reason: u16(e3[0]),
        aftertreatment_status_severity: u16(e3[1]),
        time_until_action_needed: u16(e3[2]),
        time_until_torque_reduction: u16(e3[3]),
        time_until_speed_reduction: u16(e3[4]),
        dptc_filter_status: u16(e4[0]),
        dptc_active_regen_inhibit: u16(e4[1]),
        dptc_active_regen_inhibit_et: u16(e4[2]),
        inhibit_accelerator_off_idle: u16(d[12]),
        inhibit_out_of_neutral: u16(d[13]),
        inhibit_parking_brake_not_set: u16(d[14]),
        inhibit_low_exhaust_temp: u16(d[15]),
        inhibit_system_timeout: u16(d[16]),
        inhibit_permanent_lockout: u16(d[17]),
        inhibit_system_fault: u16(d[18]),
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

    # Alarm Conditions (Page 8) - returns hash of active alarms
    # This is the old alarm system, registers 1-21
    def alarm_conditions
      regs = @modbus.read_holding_registers(PAGE_ALARM + 1, 21)
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
      u16(@modbus.read_holding_register(PAGE_BASIC + 0))
    end

    def coolant_temperature
      i16([@modbus.read_holding_register(PAGE_BASIC + 1)].to_i16)
    end

    def oil_temperature
      i16([@modbus.read_holding_register(PAGE_BASIC + 2)].to_i16)
    end

    def fuel_level
      u16(@modbus.read_holding_register(PAGE_BASIC + 3))
    end

    def charge_alternator_voltage
      u16(@modbus.read_holding_register(PAGE_BASIC + 4)) / 10.0
    end

    def battery_voltage
      u16(@modbus.read_holding_register(PAGE_BASIC + 5)) / 10.0
    end

    def rpm
      u16(@modbus.read_holding_register(PAGE_BASIC + 6))
    end

    def frequency
      u16(@modbus.read_holding_register(PAGE_BASIC + 7)) / 10.0
    end

    # Generator voltages (32-bit values)
    def voltage_l1_n
      u32(@modbus.read_holding_registers(PAGE_BASIC + 8, 2).to_u32) / 10.0
    end

    def voltage_l2_n
      u32(@modbus.read_holding_registers(PAGE_BASIC + 10, 2).to_u32) / 10.0
    end

    def voltage_l3_n
      u32(@modbus.read_holding_registers(PAGE_BASIC + 12, 2).to_u32) / 10.0
    end

    def voltage_l1_l2
      u32(@modbus.read_holding_registers(PAGE_BASIC + 14, 2).to_u32) / 10.0
    end

    def voltage_l2_l3
      u32(@modbus.read_holding_registers(PAGE_BASIC + 16, 2).to_u32) / 10.0
    end

    def voltage_l3_l1
      u32(@modbus.read_holding_registers(PAGE_BASIC + 18, 2).to_u32) / 10.0
    end

    # Generator currents (32-bit values)
    def current_l1
      u32(@modbus.read_holding_registers(PAGE_BASIC + 20, 2).to_u32) / 10.0
    end

    def current_l2
      u32(@modbus.read_holding_registers(PAGE_BASIC + 22, 2).to_u32) / 10.0
    end

    def current_l3
      u32(@modbus.read_holding_registers(PAGE_BASIC + 24, 2).to_u32) / 10.0
    end

    def current_earth
      u32(@modbus.read_holding_registers(PAGE_BASIC + 26, 2).to_u32) / 10.0
    end

    # Generator power (32-bit signed values)
    def watts_l1
      i32(@modbus.read_holding_registers(PAGE_BASIC + 28, 2).to_i32)
    end

    def watts_l2
      i32(@modbus.read_holding_registers(PAGE_BASIC + 30, 2).to_i32)
    end

    def watts_l3
      i32(@modbus.read_holding_registers(PAGE_BASIC + 32, 2).to_i32)
    end

    def watts_total
      watts_l1 + watts_l2 + watts_l3
    end

    def kw_total
      watts_total / 1000.0
    end

    # Accumulated Instrumentation (Page 7)
    def engine_run_time
      u32(@modbus.read_holding_registers(PAGE_ACCUMULATED + 6, 2).to_u32)
    end

    def engine_run_hours
      engine_run_time / 3600.0
    end

    def kwh
      u32(@modbus.read_holding_registers(PAGE_ACCUMULATED + 8, 2).to_u32) / 10.0
    end

    def start_counter
      u32(@modbus.read_holding_registers(PAGE_ACCUMULATED + 16, 2).to_u32)
    end

    def currents
      [current_l1, current_l2, current_l3]
    end

    # Read all basic measurements in one batch
    def measurements
      m = @modbus.read_holding_registers(PAGE_BASIC, 64)
      {
        oil_pressure: u16(m[0]),
        coolant_temperature: i16([m[1]].to_i16),
        oil_temperature: i16([m[2]].to_i16),
        fuel_level: u16(m[3]),
        charge_alternator_voltage: u16(m[4]) / 10.0,
        battery_voltage: u16(m[5]) / 10.0,
        rpm: u16(m[6]),
        frequency: u16(m[7]) / 10.0,
        voltage_l1_n: u32([m[8], m[9]].to_u32) / 10.0,
        voltage_l2_n: u32([m[10], m[11]].to_u32) / 10.0,
        voltage_l3_n: u32([m[12], m[13]].to_u32) / 10.0,
        voltage_l1_l2: u32([m[14], m[15]].to_u32) / 10.0,
        voltage_l2_l3: u32([m[16], m[17]].to_u32) / 10.0,
        voltage_l3_l1: u32([m[18], m[19]].to_u32) / 10.0,
        current_l1: u32([m[20], m[21]].to_u32) / 10.0,
        current_l2: u32([m[22], m[23]].to_u32) / 10.0,
        current_l3: u32([m[24], m[25]].to_u32) / 10.0,
        current_earth: u32([m[26], m[27]].to_u32) / 10.0,
        watts_l1: i32([m[28], m[29]].to_i32),
        watts_l2: i32([m[30], m[31]].to_i32),
        watts_l3: i32([m[32], m[33]].to_i32),
      }.merge(extended_measurements).merge(derived_measurements).freeze
    end

    # Read extended instrumentation (Page 5)
    def extended_measurements
      e1 = @modbus.read_holding_registers(PAGE_EXTENDED, 16)
      e2 = @modbus.read_holding_registers(PAGE_EXTENDED + 66, 6)
      e3 = @modbus.read_holding_registers(PAGE_EXTENDED + 80, 1)
      e4 = @modbus.read_holding_registers(PAGE_EXTENDED + 186, 2)
      e5 = @modbus.read_holding_registers(PAGE_EXTENDED + 202, 2)
      e6 = @modbus.read_holding_registers(PAGE_EXTENDED2 + 4, 1)
      e7 = @modbus.read_holding_registers(PAGE_EXTENDED2 + 30, 7)
      e8 = @modbus.read_holding_registers(PAGE_EXTENDED + 117, 2)
      e9 = @modbus.read_holding_registers(PAGE_EXTENDED + 175, 1)
      e10 = @modbus.read_holding_registers(PAGE_EXTENDED + 231, 2)
      {
        turbo_pressure: u16(e1[4]),
        fuel_consumption: u32([e1[10], e1[11]].to_u32) / 100.0,
        water_in_fuel: u16(e1[12]),
        atmospheric_pressure: u16(e1[14]),
        fuel_temperature: i16([e1[15]].to_i16),
        aftertreatment_temp: i16([e2[0]].to_i16),
        aftertreatment_temp_t3: i16([e2[1]].to_i16),
        engine_reference_torque: u32([e2[2], e2[3]].to_u32),
        engine_torque_pct: i32([e2[4], e2[5]].to_i32),
        injector_rail_pressure: u16(e3[0]) / 100.0,
        soot_load: u16(e4[0]),
        ash_load: u16(e4[1]),
        ambient_air_temp: i16([e5[0]].to_i16),
        air_intake_temp: i16([e5[1]].to_i16),
        dpf_regen_status: u16(e6[0]),
        dpf_soot_mass: u16(e7[0]) * 4,
        air_mass_flow_rate: u16(e7[3]) * 0.05,
        dpf_diff_pressure: u16(e7[6]) * 0.1,
        trip_fuel: u32([e8[0], e8[1]].to_u32),
        trip_average_fuel: u16(e9[0]) / 100.0,
        trip_avg_fuel_efficiency: u16(e10[0]) / 100.0,
        instantaneous_fuel_efficiency: u16(e10[1]) / 100.0,
      }.freeze
    end

    # Read derived instrumentation (Page 6) for VA, Var, and load percentage values
    def derived_measurements
      d = @modbus.read_holding_registers(PAGE_DERIVED, 24)
      d2 = @modbus.read_holding_registers(PAGE_DERIVED + 82, 3)
      {
        kva_l1: u32([d[2], d[3]].to_u32) / 1000.0,
        kva_l2: u32([d[4], d[5]].to_u32) / 1000.0,
        kva_l3: u32([d[6], d[7]].to_u32) / 1000.0,
        kvar_l1: i32([d[10], d[11]].to_i32) / 1000.0,
        kvar_l2: i32([d[12], d[13]].to_i32) / 1000.0,
        kvar_l3: i32([d[14], d[15]].to_i32) / 1000.0,
        pct_full_power: i16([d[22]].to_i16) / 10.0,
        pct_full_var: i16([d[23]].to_i16) / 10.0,
        load_pct_l1: i16([d2[0]].to_i16) / 10.0,
        load_pct_l2: i16([d2[1]].to_i16) / 10.0,
        load_pct_l3: i16([d2[2]].to_i16) / 10.0,
      }.freeze
    end

    # Read accumulated instrumentation
    def accumulated
      m = @modbus.read_holding_registers(PAGE_ACCUMULATED, 18)
      m2 = @modbus.read_holding_registers(PAGE_ACCUMULATED + 34, 2)
      {
        current_time: [m[0], m[1]].to_u32,
        time_to_maintenance: i32([m[2], m[3]].to_i32),
        time_of_maintenance: u32([m[4], m[5]].to_u32),
        engine_hours: u32([m[6], m[7]].to_u32) / 3600.0,
        kwh_positive: u32([m[8], m[9]].to_u32) / 10.0,
        kwh_negative: u32([m[10], m[11]].to_u32) / 10.0,
        kvah: u32([m[12], m[13]].to_u32) / 10.0,
        kvarh: u32([m[14], m[15]].to_u32) / 10.0,
        start_counter: u32([m[16], m[17]].to_u32),
        fuel_used: u32([m2[0], m2[1]].to_u32),
      }.freeze
    end

    def status
      @modbus.read_holding_register(PAGE_STATUS + 6)
    end

    # Digital Outputs (Page 3, register 8) - returns hash of outputs A-J
    def digital_outputs
      reg = @modbus.read_holding_register(PAGE_STATUS + 8)
      {
        a: reg[0],
        b: reg[1],
        c: reg[2],
        d: reg[3],
        e: reg[4],
        f: reg[5],
        g: reg[6],
        h: reg[7],
        i: reg[8],
        j: reg[9],
      }.freeze
    end

    def active_status_flags
      v = status
      STATUS_FLAGS.filter_map { |bit, name| name if v[bit] == 1 }
    end

    private

    # Sentinel values indicating unimplemented/unavailable data
    # 0xFFF8..0xFFFF (u16), 0xFFFFFFF8..0xFFFFFFFF (u32)
    # 0x7FF8..0x7FFF (i16), 0x7FFFFFF8..0x7FFFFFFF (i32)
    # Covers: unimplemented, over/under range, transducer fault,
    # bad data, high/low digital input, reserved

    # Replace sentinel values with NaN so they don't pollute charts
    def u16(val)  = val >= 0xFFF8     ? Float::NAN : val
    def i16(val)  = val >= 0x7FF8     ? Float::NAN : val
    def u32(val)  = val >= 0xFFFFFFF8 ? Float::NAN : val
    def i32(val)  = val >= 0x7FFFFFF8 ? Float::NAN : val

    def send_control(key)
      complement = key ^ 0xFFFF
      @modbus.write_holding_registers(PAGE_CONTROL + 8, [key, complement])
    end
  end
end
