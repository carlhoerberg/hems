require_relative "../modbus/tcp"

class Devices
  class Topas
    def initialize(host = "192.168.0.7", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(10)
    end

    def reset_alarms
      @modbus.write_holding_register(10000, 5555)
    end

    def configuration
      c = @modbus.read_holding_registers(1000, 48)
      {
        reactor_minimal: c[3],
        reactor_drainage: c[4],
        reactor_filling_max: c[5],
        reactor_emergency: c[6],
        reactor_probe_calibration: c[7],
        acc_overload: c[8],
        acc_emergency: c[9],
        acc_probe_calibration: c[10],
        acc_working: c[11],
        acc_p_100: c[12],
        acc_min_denitrification: c[13],
        post_areation: c[16],
        min_time_oxic_filling: c[17],
        sedimentation: c[18],
        decanter_preparation: c[19],
        max_filling_time: c[20],
        max_desludging_time: c[21],
        excess_sludge_layer: c[22],
        anoxic_sedimentation: c[23],
        registration_interval: c[24],
        pollution_coefficient: c[25],
        reactor_size: c[26],
        design_capacity_scale: c[28],
        running_level_wwtp: c[29],
        anoxic_filling: c[30],
        blower_interval: c[31],
        probes_preparation: c[32],
        delay_pressure_drop_error: c[33],
        max_treated_water_pumping: c[34],
        overload_delay: c[35],
        max_recirculation_time: c[36],
        max_filling_time2: c[37],
        uv_type: c[38],
        uv_min_time: c[39],
        chem_storage_volume: c[40],
        phosphorus_pump_performance: c[41],
        chem_dose: c[42],
        min_reactor_level_for_dosing: c[43],
        configuration_of_wwtp: c[44],
        serial_treated_water_pumping_blocking: c[47],
        din1: c[47] & 1 > 0,
        din2: c[47] & 2 > 0,
        din3: c[47] & 4 > 0,
        din4: c[47] & 8 > 0,
        discharge_delay: c[47] >> 7
      }
    end

    def status
      c = @modbus.read_holding_registers(10000, 8)
      c.concat Array.new(50)
      c.concat @modbus.read_holding_registers(10058, 17)
      {
        error_state: c[0],
        minute: c[3] & 255,
        hour: c[3] >> 8,
        sec: c[4],
        day: c[5] & 31,
        month: (c[5] >> 5) & 15,
        year: 2000 + (c[5] >> 9),
        temperature: c[6],
        blower_running: c[7] & 1 > 0,
        relay_p1: c[7] & 2 > 0,
        relay_v1: c[7] & 4 > 0,
        relay_v2: c[7] & 8 > 0,
        relay_v3: c[7] & 16 > 0,
        relay_v4: c[7] & 32 > 0,
        relay_p2: c[7] & 64 > 0,
        relay_p3: c[7] & 128 > 0,
        relay_p4: c[7] & 256 > 0,
        relay_p5: c[7] & 512 > 0,
        in_d1: c[7] & 1024 > 0,
        in_d2: c[7] & 2048 > 0,
        in_d3: c[7] & 4096 > 0,
        in_d4: c[7] & 8192 > 0,
        gsm_signal: c[58],
        total_running_time: c[59],
        time_v1_closed: c[60],
        time_v1_open: c[61],
        time_v2_closed: c[62],
        time_v2_open: c[63],
        time_v3_closed: c[64],
        time_v3_open: c[65],
        time_v4_closed: c[66],
        time_v4_open: c[67],
        blower_time: c[68],
        running_time_p1: c[69],
        running_time_p2: c[70],
        running_time_p3: c[71],
        running_time_p4: c[72],
        running_time_p5: c[73],
        count_impulses_d1: c[74],
      }
    end

    def measurements
      m = @modbus.read_holding_registers(11000, 64)
      {
        reactor_level: m[0],
        accumulation_level: m[1],
        aperformance: m[2] / 10.0,
        current_phase: m[3],
        time_of_current_phase: m[4],
        filling_reactor_last_time: m[5],
        sedimentation_last_time: m[6],
        decanter_filling_last_time: m[7],
        desludging_last_time: m[8],
        pumping_treated_water_last_time: m[9],
        denitr_filling_last_time: m[10],
        denitr_sedimentation_last_time: m[11],
        denitr_recirculation_last_time: m[12],
        info: m[47],
        warning: m[48],
        emergency: m[49],
        chem_volume_remaining: m[52],
        chem_percentage_remaining: (m[53] & 127),
        chem_days_remaining: (m[53] >> 7),
        analog_v1_input: m[54] / 1000.0,
        analog_i1_input: m[55],
        analog_v2_input: m[56] / 1000.0,
        analog_i2_input: m[57],
        total_treated_water: m[58],
        average_treated_water: m[59],
        average_treated_water_reg_interval: m[60],
        total_running_time: m[61],
        max_treated_water: m[62],
        max_treated_water_10_days: m[63],
      }
    end
  end
end
