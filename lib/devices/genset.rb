require_relative "../modbus/rtu"

module Devices
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
      @genset.read_input_register(0x0019) / 10
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

    def status
      keys = %i[
        starter
        fuel_solenoid
        stop_solenoid
        general_alarm
        gcb_open
        ready_to_load
        preheat
        running
        automatic_mode
        island_operation
        common_warning,
        maintenance_required
        low_battery
        low_fuel_level
        external_warning1
        external_warning2
        external_warning3
        generator_ccw_rotation
        battery_flat
        common_shutdown
        emergency_stop_active
        overspeed
        underspeed
        low_oil_pressure
        high_coolant_temperature
        external_shutdown1
        external_shutdown2
        external_shutdown3
        gcb_fail
        max_generator_voltage
        min_generator_voltage
        max_generator_frequency
        min_generator_frequency
        start_fail
        stop_fail
        generator_short_circuit
        generating_set_overload
        choke
        glow_plugs
        valve_extinguisher
      ]
      values = @genset.read_discrete_inputs(0x0020, 40)
      keys.zip(values).to_h
    end

    def ready_to_load?
      @genset.read_discrete_input(0x0025) == 1
    end

    def measurements
      m = @genset.read_input_registers(0, 40)
      {
        gen_v_l1_n: m[0],
        gen_v_l2_n: m[1],
        gen_v_l3_n: m[2],
        gen_v_l1_l2: m[3],
        gen_v_l2_l3: m[4],
        gen_v_l1_l3: m[5],
        gen_a_l1: m[6],
        gen_a_l2: m[7],
        gen_a_l3: m[8],
        gen_kw_total: m[9],
        gen_kva_total: m[10],
        gen_pf_total: m[11] / 100,
        gen_kw_l1: m[12],
        gen_kw_l2: m[13],
        gen_kw_l3: m[14],
        gen_kva_l1: m[15],
        gen_kva_l2: m[16],
        gen_kva_l3: m[17],
        gen_pf_l1: m[18] / 100,
        gen_pf_l2: m[19] / 100,
        gen_pf_l3: m[20] / 100,
        load_character: m[21].chr,
        rpm: m[22],
        gen_frequency: m[23],
        power_reading_precision: m[24] == 0 ? "no_decimal" : "decimal",
        battery_voltage: m[25] / 10,
        binary_input: m[26],
        binary_output: m[27],
        oil_pressure: m[28],
        coolant_temperature: m[29],
        fuel_level: m[30],
        unit_system: m[31] == 0 ? "metric" : "imperial",
        d_plus: m[32] / 10,
        kWh: [m[33], m[34]].to_i32,
        maintenance_timer: m[35],
        start_counter: m[36],
        serial_number: [m[37], m[38]].to_i32,
        sw_version: m[39],
        sw_patch_version: m[40]
      }
    end
  end
end
