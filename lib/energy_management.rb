# Hållfjället energy management system
class EnergyManagement
  def initialize(devices)
    @devices = devices
    @stopped = false
  end

  def start
    until @stopped
      soc = next3.battery.soc
      puts "SOC: #{soc}%"
      # if soc < 15
      #   puts "Starting genset"
      #   genset.start
      #   until genset.ready_to_load?
      #     sleep 2
      #     puts "Genset is not yet ready to load"
      #   end
      #   puts "Genset is yet ready to load"
      #   puts "Enabling charging"
      #   next3.acsource.enable
      # elsif soc >= 98
      #   puts "Disable charging"
      #   next3.acsource.disable
      #   puts "Letting genset cool down for 60s"
      #   sleep 60 # let genset cool down
      #   puts "Stopping genset"
      #   genset.stop
      # end
      sleep 10
    end
  end

  def stop
    @stopped = true
  end
end
