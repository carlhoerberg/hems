require_relative "../modbus/tcp"

class Devices
  class Topas
    def initialize(host = "192.168.0.7", port = 502)
      @modbus = Modbus::TCP.new(host, port).unit(10)
    end

    def configuration
      c = @modbus.read_holding_registers(1000, 48)
      {
        reactor_minimal: c[3],
        reactor_drainage: c[4],
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
        chem_volume: m[52],
        chem_percentage: m[53],
        total_treated_water: m[58],
        average_treated_water: m[59],
        average_treated_water_reg_interval: m[59],
        total_running_time: m[61],
        max_treated_water: m[62],
        max_treated_water_10_days: m[63],
      }
    end
  end
end
