require_relative "./devices"
require_relative "./solar_forecast"

class Time
  # Monotonic seconds since boot
  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

# Hållfjället energy management system
class EnergyManagement
  def initialize(devices)
    @devices = devices
    @stopped = false
    @solar_forecast = SolarForecast.new
    @power_measurements = []
    @phase_current_history = []
    @last_current_raise = 0 # last time the acsource.rated_current was increased
  end

  def start
    until @stopped
      begin
        sleep 5
        soc = @devices.next3.battery.soc
        genset_support(soc)
        load_shedding(soc)
      rescue => e
        puts "[ERROR] #{e.inspect}"
        e.backtrace.each { |l| print "\t", l, "\n" }
      end
    end
  end

  def stop
    @stopped = true
  end

  # Start water heaters when close to excess solar/battery capacity
  def load_shedding(soc = @devices.next3.battery.soc)
    if @devices.relays.heater_6kw?
      if soc <= 90
        puts "SOC #{soc}%, turning off 6kw heater"
        @devices.relays.heater_6kw = false
      elsif phase_capacity.any? { |p| p < 0 }
        puts "Over power, turning off 6kw heater"
        @devices.relays.heater_6kw = false
      #elsif @devices.next3.solar.total_power < 1000
      #  puts "Weak solar power, turning off 6kw heater"
      #  @devices.relays.heater_6kw = false
      end
    else # 6kw heater is off
      if soc > 95 && @devices.next3.solar.total_power > 5000 &&
          phase_capacity.all? { |p| p > 6000 / 3 }
        puts "Solar excess, turning on 6kw heater"
        @devices.relays.heater_6kw = true
      end
    end
    if @devices.relays.heater_9kw?
      if soc <= 90
        puts "SOC #{soc}%, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      elsif phase_capacity.any? { |p| p < 0 }
        puts "Over power, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      #elsif @devices.next3.solar.total_power < 1000
      #  puts "Weak solar power, turning off 9kw heater"
      #  @devices.relays.heater_9kw = false
      end
    else # 9kw heater is off
      if soc > 95 && @devices.next3.solar.total_power > 5000 &&
          phase_capacity.all? { |p| p > 9000 / 3 }
        puts "Solar excess, turning on 9kw heater"
        @devices.relays.heater_9kw = true
      end
    end
  end

  def phase_capacity
    (1..3).map do |phase|
      5_000 - @devices.next3.acload.apparent_power(phase)
    end
  end

  def phase_current
    (1..3).map do |phase|
      @devices.next3.acload.current(phase)
    end
  end

  # if the current on any phase is >20A for more than 25s the inverter needs support
  def high_phase_current?
    @phase_current_history.shift while @phase_current_history.size >= 100
    @phase_current_history.push phase_current
    (0..2).each do |phase|
      streak = 0
      @phase_current_history.each do |phases|
        if phases[phase] > 20
          streak += 1
        else
          streak = 0
        end
        return true if streak >= 5
      end
    end
    false
  end

  BATTERY_KWH = 31.2

  def genset_support(soc = @devices.next3.battery.soc)
    if @devices.genset.is_running?
      @devices.relays.open_air_vents # should already be open, but make sure

      keep_hz

      if high_phase_current?
        puts "High phase current, keeping genset running"
      elsif @devices.next3.battery.errors != 0
        puts "Battery has errors, keeping genset running"
      elsif soc >= 98
        puts "SoC #{soc}%, battery current limited, stopping genset"
        stop_genset
      elsif will_reach_full_battery_with_solar?(soc)
        puts "Battery will reach full charge with solar, stopping genset"
        stop_genset
      end
    else # genset is not running
      discharge_limit = @devices.next3.battery.bms_recommended_discharging_current
      if discharge_limit <= 350 # open air vents well before any battery problems
        @devices.relays.open_air_vents
      else # close vents if genset is not running and we are ok on batteries
        @devices.relays.close_air_vents
      end

      discharge_current = -@devices.next3.battery.charging_current
      if high_phase_current?
        puts "Starting genset. High phase current, avoid voltage drop"
        start_genset
      elsif discharge_limit - discharge_current < 100 || soc <= 7
        puts "Starting genset. SoC=#{soc}% discharge_limit=#{discharge_limit}A discharge_current=#{discharge_current}A"
        start_genset
      end
    end
  end

  def will_reach_full_battery_with_solar?(soc)
    # collect power measuremnts to be able to calculate an averge once in a while
    @power_measurements << @devices.next3.acload.total_apparent_power
    #puts "Got #{@power_measurements.size} power measurements, avg: #{@power_measurements.sum / @power_measurements.size / 1000.0}"
    return if @power_measurements.size < 60 / 5 # 1 minute, 5s interval measurements

    avg_power_kw = @power_measurements.sum / @power_measurements.size / 1000.0
    puts "Avg power kw: #{avg_power_kw}"
    @power_measurements.clear # don't use a sliding window as we don't want to poll forecast api too much

    battery_kwh = BATTERY_KWH * soc / 100.0
    puts "Battery charge: #{battery_kwh} kWh"

    # improve accuracy of forecast by telling how much is produced so far today
    produced_solar_today = @devices.next3.solar.total_day_energy / 1000.0
    puts "Solar produced today: #{produced_solar_today} kWh"
    @solar_forecast.actual = produced_solar_today if produced_solar_today > 1 # don't report too early in the day

    last_time = Time.now
    @solar_forecast.estimate_watts.each do |t, watts|
      time = Time.parse(t)
      next if time <= last_time

      period = (time - last_time) / 3600
      battery_kwh += (watts / 1000.0 - avg_power_kw) * period
      estimated_soc = (battery_kwh / BATTERY_KWH * 100).round
      puts "Estimated battery at #{time}: #{estimated_soc}% #{battery_kwh} kWh"
      return true if estimated_soc >= 99
      return false if estimated_soc <= 12 # % SoC required otherwise genset starts again

      last_time = time
    end
    false # if we get here we have not received full charge within 2 days
  end

  def start_genset
    @devices.relays.open_air_vents

    puts "Starting genset"
    @devices.genset.start
    sleep 3 # should have started in this time
    unless @devices.genset.is_running?
      puts "Genset didn't start", "Status: #{@devices.genset.status}"
      raise "Genset didn't start"
    end

    until @devices.genset.ready_to_load?
      puts "Genset not ready to load"
      sleep 1
    end
    puts "Enabling ACSource"
    @devices.next3.acsource.enable
  end

  def stop_genset
    puts "Turning of load to cool down"
    @devices.next3.acsource.disable
    loop do
      temp = @devices.genset.coolant_temperature
      break if temp < 70
      puts "Idling genset, temperature=#{temp}"
      sleep 10
    end
    puts "Stopping genset"
    @devices.genset.stop
    sleep 3
    if @devices.genset.is_running?
      puts "Genset did not stop", "Status: #{genset.status}"
      raise "Genset didn't stop"
    end
    puts "Restoring AC source values"
    @devices.next3.acsource.rated_current = 23 # safe for +0 outdoor temp
    @devices.next3.acsource.enable
    @power_measurements.clear
  end

  def keep_hz
    hz = @devices.genset.frequency # frequency from genset got 1 decimal
    temp = @devices.genset.coolant_temperature

    if temp >= 90
      rated_current = @devices.next3.acsource.rated_current
      puts "coolant_temperature=#{temp} adjusting current down to #{rated_current - 1}"
      @devices.next3.acsource.rated_current = rated_current - 1
    elsif hz <= 49.7
      rated_current = @devices.next3.acsource.rated_current
      puts "hz=#{hz} adjusting current down to #{rated_current - 1}"
      @devices.next3.acsource.rated_current = rated_current - 1
    elsif hz >= 50.6
      rated_current = @devices.next3.acsource.rated_current
      # never try to draw more than 25A
      if rated_current < 25
        # increase max once per minute
        if Time.monotonic - @last_current_raise > 60
          # Only adjust if inverter is drawing full power
          # eg. not when ramping up, or battery is almost full
          if @devices.next3.acsource.current(1) > rated_current - 2
            puts "hz=#{hz} adjusting current up to #{rated_current + 1}"
            @devices.next3.acsource.rated_current = rated_current + 1
            @last_current_raise = Time.monotonic
          end
        end
      end
    end
  end
end
