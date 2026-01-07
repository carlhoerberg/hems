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
  DEFAULT_GENSET_ACTIVATION_SOC = 20
  DEFAULT_GENSET_DEACTIVATION_SOC = 95

  def initialize(devices)
    @devices = devices
    @stopped = false
    @solar_forecast = SolarForecast.new
    @phase_current_history = []
    @last_threshold_check = 0
    # Configure aux1 for genset control on first run
    @devices.next3.aux1.configure_for_genset(
      activation_soc: DEFAULT_GENSET_ACTIVATION_SOC,
      deactivation_soc: DEFAULT_GENSET_DEACTIVATION_SOC
    )
  end

  def start
    duration = 0
    until @stopped
      begin
        duration = Time.measure do
          @phase_current_history.shift if @phase_current_history.size >= 60
          @phase_current_history.push phase_current
          soc = @devices.next3.battery.soc
          genset_threshold_management(soc)
          load_shedding(soc)
        end
        puts "Energy management loop duration: #{duration.round(2)}s" if duration > 1
        break if @stopped
        sleep [5 - duration, 0].max
      rescue => e
        puts "[ERROR] #{e.inspect}"
        e.backtrace.each { |l| print "\t", l, "\n" }
      end
    end
  end

  def stop
    @stopped = true
  end

  # Add heater load when:
  # 1. Genset running: keep it at high load (DFS requires it)
  # 2. Solar excess: use excess solar to heat water
  # Only when battery is charge-limited by BMS, stop if discharging
  def load_shedding(soc = @devices.next3.battery.soc)
    heaters_on = @devices.relays.any_heater_on?

    # Stop heaters if battery is discharging
    if battery_discharging?
      if heaters_on
        puts "Battery discharging, turning off heaters"
        turn_off_heaters
      end
      return
    end

    # Only add load when battery is charge-limited by BMS
    unless battery_charge_limited?
      turn_off_heaters if heaters_on
      return
    end

    if genset_running?
      genset_load_shedding
    else
      solar_load_shedding
    end
  end

  def battery_discharging?
    @devices.next3.battery.charging_current < 0
  end

  def battery_charge_limited?
    recommended = @devices.next3.battery.bms_recommended_charging_current
    actual = @devices.next3.battery.charging_current
    # Limited when actual is within 5A of recommended
    recommended - actual < 5
  end

  # Add heaters to match rated_current when genset is running
  def genset_load_shedding
    rated = @devices.next3.acsource.rated_current
    max_current = (1..3).map { |p| @devices.next3.acsource.current(p) }.max
    headroom = rated - max_current

    # Heater current per phase (3-phase balanced load)
    current_6kw = 6000.0 / 3 / 230  # ~8.7A
    current_9kw = 9000.0 / 3 / 230  # ~13A

    heater_6kw_on = @devices.relays.heater_6kw?
    heater_9kw_on = @devices.relays.heater_9kw?

    if headroom >= current_6kw + current_9kw + 2
      unless heater_6kw_on && heater_9kw_on
        puts "Genset headroom #{headroom.round(1)}A, turning on both heaters"
        @devices.relays.heater_6kw = true
        @devices.relays.heater_9kw = true
      end
    elsif headroom >= current_9kw + 2
      unless heater_9kw_on && !heater_6kw_on
        puts "Genset headroom #{headroom.round(1)}A, using 9kW heater"
        @devices.relays.heater_6kw = false
        @devices.relays.heater_9kw = true
      end
    elsif headroom >= current_6kw + 2
      unless heater_6kw_on && !heater_9kw_on
        puts "Genset headroom #{headroom.round(1)}A, using 6kW heater"
        @devices.relays.heater_6kw = true
        @devices.relays.heater_9kw = false
      end
    else
      turn_off_heaters if heater_6kw_on || heater_9kw_on
    end
  end

  # Add heaters when solar production exceeds consumption
  def solar_load_shedding
    current_6kw = 6000.0 / 3 / 230  # ~8.7A
    current_9kw = 9000.0 / 3 / 230  # ~13A

    heater_6kw_on = @devices.relays.heater_6kw?
    heater_9kw_on = @devices.relays.heater_9kw?
    excess = @devices.next3.solar.excess?

    if excess
      if !heater_6kw_on && phase_current_capacity?(current_6kw)
        puts "Solar excess, turning on 6kW heater"
        @devices.relays.heater_6kw = true
      elsif heater_6kw_on && !heater_9kw_on && phase_current_capacity?(current_9kw)
        puts "Solar excess, turning on 9kW heater"
        @devices.relays.heater_9kw = true
      end
    elsif heater_6kw_on || heater_9kw_on
      # Keep heaters on if solar is contributing (discharge power < heater power)
      # Turn off one heater at a time, matching size to the deficit
      heater_power = (heater_6kw_on ? 6000 : 0) + (heater_9kw_on ? 9000 : 0)
      discharge_power = -@devices.next3.battery.power  # positive when discharging

      if discharge_power > heater_power
        # Turn off heater that best matches the discharge
        if heater_6kw_on && heater_9kw_on
          # Both on: turn off the one closest to discharge power
          if discharge_power < 9000
            puts "Discharge #{discharge_power.round}W, turning off 6kW heater"
            @devices.relays.heater_6kw = false
          else
            puts "Discharge #{discharge_power.round}W, turning off 9kW heater"
            @devices.relays.heater_9kw = false
          end
        elsif heater_9kw_on
          puts "Discharge #{discharge_power.round}W > 9kW, turning off 9kW heater"
          @devices.relays.heater_9kw = false
        else
          puts "Discharge #{discharge_power.round}W > 6kW, turning off 6kW heater"
          @devices.relays.heater_6kw = false
        end
      end
    end
  end

  def genset_running?
    @devices.next3.acsource.frequency > 0
  end

  def turn_off_heaters
    puts "Turning off heaters"
    @devices.relays.heater_6kw = false
    @devices.relays.heater_9kw = false
  end

  def phase_current
    (1..3).map do |phase|
      @devices.next3.acload.current(phase)
    end
  end

  INVERTER_CURRENT_LIMIT = 22

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

  def voltage_drop?
    (1..3).any? do |phase|
      @devices.next3.acload.voltage(phase) < 210
    end
  end

  BATTERY_KWH = 31.2

  # Manage genset start/stop thresholds via Next3 aux1 relay
  def genset_threshold_management(soc = @devices.next3.battery.soc)
    return if Time.monotonic - @last_threshold_check < 60
    @last_threshold_check = Time.monotonic

    current_deactivation = @devices.next3.aux1.soc_deactivation_threshold
    target_deactivation = DEFAULT_GENSET_DEACTIVATION_SOC

    # If weco module SoC drift > 5%, increase deactivation threshold to 99%
    # to allow batteries to balance
    soc_diff = weco_module_soc_diff
    if soc_diff > 5
      target_deactivation = 99
      puts "Battery module SoC drift #{soc_diff.round(1)}% > 5%, setting genset deactivation to 99%"
    # If solar forecast shows we'll survive, decrease threshold to stop genset earlier
    elsif genset_running? && will_survive_on_solar?(soc)
      target_deactivation = [soc.ceil + 5, DEFAULT_GENSET_DEACTIVATION_SOC].min
      puts "Solar forecast positive, lowering genset deactivation to #{target_deactivation}%"
    end

    if current_deactivation != target_deactivation
      puts "Adjusting genset deactivation threshold: #{current_deactivation}% -> #{target_deactivation}%"
      @devices.next3.aux1.soc_deactivation_threshold = target_deactivation
    end
  end

  # Check if solar will sustain us for the rest of the day
  def will_survive_on_solar?(soc)
    return false if @phase_current_history.size < 5

    avg_power_kw = @phase_current_history.sum { |phases| phases.sum } * 230 / @phase_current_history.size / 1000.0
    battery_kwh = BATTERY_KWH * soc / 100.0

    produced_solar_today = @devices.next3.solar.total_day_energy / 1000.0
    @solar_forecast.actual = produced_solar_today if produced_solar_today > 1

    last_time = start = Time.now
    @solar_forecast.estimate_watt_hours.each do |t, watthours|
      time = Time.parse(t)
      next if time <= last_time

      period = (time - last_time) / 3600
      battery_kwh += ((watthours / 1000.0) - (avg_power_kw * period))
      estimated_soc = (battery_kwh / BATTERY_KWH * 100).round
      return false if estimated_soc <= DEFAULT_GENSET_ACTIVATION_SOC

      last_time = time
    end
    return false if last_time == start
    true
  rescue => e
    puts "[ERROR] Solar forecast: #{e.inspect}"
    false
  end

  def weco_module_soc_diff
    min_soc = nil
    max_soc = nil
    @devices.weco.modules.each do |mod|
      min_soc = mod[:soc_value] if min_soc.nil? || mod[:soc_value] < min_soc
      max_soc = mod[:soc_value] if max_soc.nil? || mod[:soc_value] > max_soc
    end
    max_soc - min_soc
  end
end
