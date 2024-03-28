# Hållfjället energy management system
class EnergyManagement
  def initialize(devices)
    @devices = devices
    @stopped = false
  end

  def start
    until @stopped
      soc = @devices.next3.battery.soc
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
      sleep 5
    end
  end

  def stop
    @stopped = true
  end

  def charge_from_genset
    genset = @devices.genset
    puts "Starting genset"
    genset.auto
    sleep 3 # should have started in this time
    unless genset.status[:running]
      puts "Genset didn't start", "Status: #{genset.status}"
      raise "Genset didn't start"
    end
    puts "Genset is running"
    sleep 1 until genset.ready_to_load?
    puts "Genset is ready to load"

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
