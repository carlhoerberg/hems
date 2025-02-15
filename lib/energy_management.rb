require_relative "./devices"
require_relative "./solar_forecast"

class Time
  # Monotonic seconds since boot
  def self.monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.measure(&)
    start = monotonic
    yield
    monotonic - start
  end
end

# Hållfjället energy management system
class EnergyManagement
  def initialize(devices)
    @devices = devices
    @stopped = false
    @solar_forecast = SolarForecast.new
    @phase_current_history = []
    @last_solar_check = 0
    @last_current_raise = 0 # last time the acsource.rated_current was increased
  end

  def start
    duration = 0
    until @stopped
      begin
        sleep [5 - duration, 0].max
        duration = Time.measure do
          @phase_current_history.shift if @phase_current_history.size >= 60
          @phase_current_history.push phase_current
          soc = @devices.next3.battery.soc
          genset_support(soc)
          load_shedding(soc)
        end
        puts "Energy management loop duration: #{duration.round(2)}s" if duration > 1
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
      elsif high_phase_current?
        puts "Over power, turning off 6kw heater"
        @devices.relays.heater_6kw = false
      #elsif @devices.next3.solar.total_power < 1000
      #  puts "Weak solar power, turning off 6kw heater"
      #  @devices.relays.heater_6kw = false
      end
    else # 6kw heater is off
      if soc > 95 &&
          phase_current_capacity?(6000.0 / 3 / 230) &&
          @devices.next3.solar.total_power > 5000
        puts "Solar excess, turning on 6kw heater"
        @devices.relays.heater_6kw = true
        return # so that we don't enable the 9kW too
      end
    end
    if @devices.relays.heater_9kw?
      if soc <= 90
        puts "SOC #{soc}%, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      elsif high_phase_current?
        puts "Over power, turning off 9kw heater"
        @devices.relays.heater_9kw = false
      #elsif @devices.next3.solar.total_power < 1000
      #  puts "Weak solar power, turning off 9kw heater"
      #  @devices.relays.heater_9kw = false
      end
    else # 9kw heater is off
      if soc > 95 &&
          phase_current_capacity?(9000.0 / 3 / 230) &&
          @devices.next3.solar.total_power > 5000
        puts "Solar excess, turning on 9kw heater"
        @devices.relays.heater_9kw = true
      end
    end
  end

  def phase_current
    (1..3).map do |phase|
      @devices.next3.acload.current(phase)
    end
  end

  INVERTER_CURRENT_LIMIT = 20

  # Returns true if the current on any phase has been over 20A for 25s in a row,
  # during the last 5 minutes. That will result in a voltage drop. 
  def high_phase_current?
    not phase_current_capacity?(0)
  end

  # Can the requested current be added without overload? Look at the current draw
  # for the past 5 minutes
  def phase_current_capacity?(requested_current)
    # we can't know if there's capacity until we have 5 or more measurments
    return false if @phase_current_history.size < 5

    (0..2).each do |phase|
      streak = 0
      @phase_current_history.each do |phases|
        if INVERTER_CURRENT_LIMIT - phases[phase] - requested_current < 0
          streak += 1
        else
          streak = 0
        end
        return false if streak >= 5
      end
    end
    true
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
      elsif @devices.weco.min_soc >= 97
        puts "SoC #{soc}%, battery current limited, stopping genset"
        stop_genset
      elsif will_reach_full_battery_with_solar?(soc)
        puts "Battery will reach full charge with solar, stopping genset"
        stop_genset
      end
    else # genset is not running
      battery_current = @devices.weco.currents
      discharge_limit = battery_current[:discharge_limit]
      if discharge_limit <= 350 # open air vents well before any battery problems
        @devices.relays.open_air_vents
      else # close vents if genset is not running and we are ok on batteries
        @devices.relays.close_air_vents
      end

      discharge_current = battery_current[:current]
      #if high_phase_current?
      #  puts "Starting genset. High phase current, avoid voltage drop"
      #  start_genset
      #  return
      #end
      if discharge_limit - discharge_current < 130 || soc <= 7
        puts "Starting genset. SoC=#{soc}% discharge_limit=#{discharge_limit}A discharge_current=#{discharge_current}A"
        start_genset
      end
    end
  end

  def will_reach_full_battery_with_solar?(soc)
    return if Time.monotonic - @last_solar_check < 60 # only check every minute
    @last_solar_check = Time.monotonic

    avg_power_kw = @phase_current_history.sum { |phases| phases.sum } * 230 / @phase_current_history.size / 1000.0
    puts "Avg power usage: #{avg_power_kw.round(1)} kW"

    battery_kwh = BATTERY_KWH * soc / 100.0
    puts "Battery charge: #{soc}% #{battery_kwh.round(1)} kWh"

    # improve accuracy of forecast by telling how much is produced so far today
    produced_solar_today = @devices.next3.solar.total_day_energy / 1000.0
    puts "Solar produced today: #{produced_solar_today.round(1)} kWh"
    @solar_forecast.actual = produced_solar_today if produced_solar_today > 1 # don't report too early in the day

    last_time = Time.now
    @solar_forecast.estimate_watt_hours.each do |t, watthours|
      time = Time.parse(t)

      period = (time - last_time) / 3600
      battery_kwh += ((watthours / 1000.0) - (avg_power_kw * period))
      estimated_soc = (battery_kwh / BATTERY_KWH * 100).round
      puts "Estimated battery SoC at #{time}: #{estimated_soc}%"
      return true if estimated_soc >= 85
      return false if estimated_soc <= 12 # % SoC required otherwise genset starts again

      last_time = time
    end
    true # we will be solar powered the rest of the day, so stop genset now
  rescue => e
    puts "[ERROR] #{e.inspect}"
    e.backtrace.each { |l| print "\t", l, "\n" }
    false
  end

  def start_genset
    @devices.relays.open_air_vents

    puts "Starting genset"
    @devices.genset.start
    sleep 3 # should have started in this time
    unless @devices.genset.is_running?
      status = @devices.genset.status.select { |_, v| v }.keys
      puts "Genset didn't start, status:", status
      if status == [:general_alarm, :common_shutdown, :min_generator_frequency]
        puts "Min generator frequency alarm, resetting"
        @devices.genset.stop
      end
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
  end

  def keep_hz
    hz = @devices.genset.frequency # frequency from genset got 1 decimal
    temp = @devices.genset.coolant_temperature

    if temp >= 94
      rated_current = @devices.next3.acsource.rated_current
      puts "coolant_temperature=#{temp} adjusting current down to #{rated_current - 1}"
      @devices.next3.acsource.rated_current = rated_current - 1
    elsif hz <= 49.5
      rated_current = @devices.next3.acsource.rated_current
      puts "hz=#{hz} adjusting current down to #{rated_current - 1}"
      @devices.next3.acsource.rated_current = rated_current - 1
    elsif hz >= 50.5
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
