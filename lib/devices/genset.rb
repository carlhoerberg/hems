require_relative "../modbus/rtu"

class Devices
  class Genset
    using Modbus::TypeExtensions

    def initialize
      @genset = Modbus::RTU.new.unit(5)
    end

    def start
      @genset.write_coil(0, true)
    end

    def stop
      @genset.write_coil(1, true)
    end

    def auto
      @genset.write_coil(2, true)
    end

    def battery_voltage
      @genset.read_input_register(0x0019) / 10.0
    end

    def oil_pressure
      @genset.read_input_register(0x001C)
    end

    def coolant_temperature
      @genset.read_input_register(0x001D)
    end

    def fuel_level
      @genset.read_input_register(0x001E)
    end

    def maintenance_timer
      @genset.read_input_register(0x0023)
    end

    def start_counter
      @genset.read_input_register(0x0024)
    end

    def ready_to_load?
      @genset.read_discrete_input(0x0025)
    end

    def frequency
      @genset.read_input_register(23) / 10.0
    end

    def status
      v = @genset.read_discrete_inputs(0x0020, 40)
      {
        starter: v[0],
        fuel_solenoid: v[1],
        stop_solenoid: v[2],
        general_alarm: v[3],
        gcb_open: v[4],
        ready_to_load: v[5],
        preheat: v[6],
        running: v[7],
        automatic_mode: v[8],
        island_operation: v[9],
        common_warning: v[10],
        maintenance_required: v[11],
        low_battery: v[12],
        low_fuel_level: v[13],
        external_warning1: v[14],
        external_warning2: v[15],
        external_warning3: v[16],
        generator_ccw_rotation: v[17],
        battery_flat: v[18],
        common_shutdown: v[19],
        emergency_stop_active: v[20],
        overspeed: v[21],
        underspeed: v[22],
        low_oil_pressure: v[23],
        high_coolant_temperature: v[24],
        external_shutdown1: v[25],
        external_shutdown2: v[26],
        external_shutdown3: v[27],
        gcb_fail: v[28],
        max_generator_voltage: v[29],
        min_generator_voltage: v[30],
        max_generator_frequency: v[31],
        min_generator_frequency: v[32],
        start_fail: v[33],
        stop_fail: v[34],
        generator_short_circuit: v[35],
        generating_set_overload: v[36],
        choke: v[37],
        glow_plugs: v[38],
        valve_extinguisher: v[39],
      }.freeze
    end

    def currents
      @genset.read_input_registers(6, 3).map { |c| c / 10.0 }
    end

    def measurements
      m = []
      15.times do |i|
        m.concat @genset.read_input_registers(i * 3, 3)
      end
      power_reading_precision = 10.0
      {
        voltage_l1_n: m[0],
        voltage_l2_n: m[1],
        voltage_l3_n: m[2],
        voltage_l1_l2: m[3],
        voltage_l2_l3: m[4],
        voltage_l1_l3: m[5],
        current_l1: m[6] / power_reading_precision,
        current_l2: m[7] / power_reading_precision,
        current_l3: m[8] / power_reading_precision,
        kw_total: m[9] / power_reading_precision,
        kva_total: m[10] / power_reading_precision,
        pf_total: m[11] / 100.0,
        kw_l1: m[12] / power_reading_precision,
        kw_l2: m[13] / power_reading_precision,
        kw_l3: m[14] / power_reading_precision,
        kva_l1: m[15] / power_reading_precision,
        kva_l2: m[16] / power_reading_precision,
        kva_l3: m[17] / power_reading_precision,
        pf_l1: m[18] / 100.0,
        pf_l2: m[19] / 100.0,
        pf_l3: m[20] / 100.0,
        load_character: m[21].chr, # R, L, C or space
        rpm: m[22],
        frequency: m[23] / 10.0,
        power_reading_precision: m[24],
        battery_voltage: m[25] / 10.0,
        binary_input: m[26], # CRC16 error when genset is running
        binary_output: m[27],
        oil_pressure: m[28] / power_reading_precision,
        coolant_temperature: m[29],
        fuel_level: m[30], # CRC16 error when genset is running
        unit_system: m[31].zero? ? :metric : :imperial,
        d_plus: m[32] / 10.0,
        kWh: [m[33], m[34]].to_i32 / power_reading_precision,
        maintenance_timer: m[35],
        start_counter: m[36],
        serial_number: [m[37], m[38]].to_i32,
        sw_version: m[39],
        sw_patch_version: m[40],
        hours: [m[41], m[42]].to_i32 / power_reading_precision,
        unknown3: m[43],
        unknown4: m[44],
      }.freeze
    end
  end
end
