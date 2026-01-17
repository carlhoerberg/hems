require_relative "../modbus/tcp"

class Devices
  # GenComm standard for generating set control equipment
  # Developed by Deep Sea Electronics, used by various manufacturers
  class GenComm
    using Modbus::TypeExtensions

    # GenComm page addresses
    PAGE_STATUS = 0x0300          # Page 3 - Status
    PAGE_BASIC = 0x0400           # Page 4 - Basic Instrumentation
    PAGE_ACCUMULATED = 0x0700     # Page 7 - Accumulated Instrumentation
    PAGE_CONTROL = 0x1000         # Page 16 - Control

    # Control keys (write to PAGE_CONTROL+8 and ones-complement to PAGE_CONTROL+9)
    CONTROL_STOP = 35700
    CONTROL_AUTO = 35701
    CONTROL_MANUAL = 35702
    CONTROL_RESET_ALARMS = 35734

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
        kva_l1: [m[40], m[41]].to_i32,
        kva_l2: [m[42], m[43]].to_i32,
        kva_l3: [m[44], m[45]].to_i32,
      }.freeze
    end

    # Read accumulated instrumentation
    def accumulated
      m = @modbus.read_holding_registers(PAGE_ACCUMULATED, 18)
      {
        current_time: [m[0], m[1]].to_u32,
        time_to_maintenance: [m[2], m[3]].to_i32,
        time_of_maintenance: [m[4], m[5]].to_u32,
        engine_run_time: [m[6], m[7]].to_u32,
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
