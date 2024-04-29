require_relative "./devices"

# Hållfjället energy management system
class EnergyManagement
  def initialize
    @devices = Devices.new
    @stopped = false
  end

  def start
    until @stopped
      soc = @devices.next3.battery.soc
      genset_support(soc)
      load_shedding(soc)
      sleep 5
    end
  end

  def stop
    @stopped = true
  end

  # Turn on the 9kw heater when solar is power limited
  # Turn off if load > 16kw
  # Turn off when SOC < 85
  # Turn off if forecast doesn't expect us to reach 100% SOC at the end of the solar day
  def load_shedding(soc = @devices.next3.battery.soc)
    if @devices.relays.heater_9kw?
      if soc < 85
        puts "SOC #{soc}%, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      elsif (tp = @devices.next3.acload.total_apparent_power) > 16_000
        puts "Total power #{tp}, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      end
    else
      if @devices.next3.solar.excess? &&
          15_000 - @devices.next3.acload.total_apparent_power > 9_000
        puts "Solar excess, turning on 9kw heater"
        @devices.relays.heater_9kw = true
      end
    end
  end

  def genset_support(soc = @devices.next3.battery.soc)
    if @devices.genset.is_running?
      if soc >= 80
        stop_genset
      end
    else # genset is not running
      if soc <= 10
        start_genset
      end
    end
  end

  def start_genset
    @devices.relays.open_air_vents
    puts "Opening air vents, takes 2:30"
    sleep 150 # it takes 2:30 for the vents to fully open
    puts "Air vents should be fully open"

    puts "Starting genset"
    @devices.genset.start
    sleep 3 # should have started in this time
    unless @devices.genset.is_running?
      puts "Genset didn't start", "Status: #{@devices.genset.status}"
      raise "Genset didn't start"
    end
  end

  def stop_genset
    puts "Stopping genset"
    @devices.genset.stop
    sleep 3
    if @devices.genset.is_running?
      puts "Genset did not stop", "Status: #{genset.status}"
      raise "Genset didn't stop"
    end
    puts "Closing air vents"
    @devices.relays.close_air_vents
  end
end
