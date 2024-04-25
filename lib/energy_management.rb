# Hållfjället energy management system
class EnergyManagement
  def initialize(devices)
    @devices = devices
    @stopped = false
  end

  def run
    until @stopped
      soc = @devices.next3.battery.soc
      puts "SOC: #{soc}%"
      if soc <= 10
        start_genset
        #puts "Genset is running, wait for ready to load"
        #sleep 1 until @devices.genset.ready_to_load?
        #puts "Genset is ready to load"
        #puts "Enabling charging"
        #next3.acsource.enable
      elsif soc >= 90
        #puts "Disable charging"
        #next3.acsource.disable
        #puts "Letting genset cool down for 60s"
        #sleep 60 # let genset cool down
        stop_genset
      end
      sleep 5
    end
  end

  def stop
    @stopped = true
  end

  def start_genset
    @devices.relay.open_air_vents
    return if @devices.genset.status[:running]
    puts "Opening air vents, takes 2:30"
    sleep 150 # it takes 2:30 for the vents to fully open
    puts "Air vents should be fully open"

    puts "Starting genset"
    @devices.genset.start
    sleep 2 # should have started in this time
    unless @devices.genset.status[:running]
      puts "Genset didn't start", "Status: #{@devices.genset.status}"
      raise "Genset didn't start"
    end
    genset
  end

  def stop_genset
    puts "Stopping genset"
    @devices.genset.stop
    sleep 2
    if genset.status[:running]
      puts "Genset did not stop", "Status: #{genset.status}"
      raise "Genset didn't stop"
    end
    puts "Closing air vents"
    @devices.relay.close_air_vents
  end

  def charge_from_genset
    current = 16
    acsource = @devices.next3.acsource
    acsource.rated_current = current
    acsource.enable
    loop do
      case genset.frequency
      when 0
        puts "Genset has failed", "Status: #{genset.status}"
        raise "Genset has failed"
      when ..49.2
        current -= 1
        acsource.rated_current = current
        puts "AcSourceCurrent=#{current}"
      when 49.2..49.5
        # hold steady
      when 49.5..
        if @devices.next3.battery.charging_current_high_limit > current
          current += 1
          acsource.rated_current = current
          puts "AcSourceCurrent=#{current}"
        end
      end
      sleep 0.5
    end
  end
end
