require_relative "./devices"
require "net/http"
require "json"

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

  # 2kW single-phase Shelly heaters (9A each)
  SHELLY_HEATER_2KW = [
    { host: "192.168.0.190", phase: 2, amps: 9 },  # Phase 2
    { host: "192.168.0.137", phase: 3, amps: 9 },  # Phase 3
  ].freeze

  INVERTER_CURRENT_LIMIT = 26
  GENSET_CURRENT_LIMIT = 50

  GENSET_DEMAND_START_DELAY = 180    # seconds of unmet demand before starting genset
  GENSET_DEMAND_STOP_DELAY = 15 * 60 # seconds after last demand before stopping genset

  VICTRON_INVERTER_ONLY_MIN_SOC = 50 # only shed Victron charging if SoC > this
  MIN_PHASE_VOLTAGE = 210 # turn off shelly demands if any phase drops below this
  HEATER_MAX_PHASE_CURRENT = 22 # long-term safe inverter limit per phase for heaters
  SOLAR_EXCESS_HEATER_STOP_SOC = 95   # keep solar excess heaters on until this SoC

  STATE_FILE = File.join(ENV.fetch("STATE_DIRECTORY", "/var/lib/hems"), "energy_management.json")

  def initialize(devices)
    @devices = devices
    @stopped = false
    @shelly_demands = {}  # { device_id => { amps:, active: false, unmet_since: nil } }
    @shelly_demands_mutex = Mutex.new
    @phase_current_history = []
    @genset_started_for_demand = false # true if we manually started genset for shelly demand
    @last_shelly_demand_at = nil      # monotonic time of last shelly demand registration
    @ac_source_enabled = @devices.next3.acsource.enabled?
    load_state
  end

  def start
    until @stopped
      begin
        duration = Time.measure do
          manage_ac_source
          update_phase_current_history
          manage_shelly_demands
          manage_genset_for_demand
          manage_heaters
          manage_goe_amperage
          manage_victron_mode
          save_state
        end
        puts "Energy management loop duration: #{duration.round(2)}s" if duration > 5
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
    save_state
  end

# Enable AC source only when genset mains breaker is closed (supplying power).
  # Disable during warmup/cooldown (fuel relay on but mains breaker off).
  # Fail-safe: re-enable when genset is fully off (both relays off).
  def manage_ac_source
    fuel = @devices.gencomm.fuel_relay
    mains_breaker = @devices.gencomm.mains_breaker_relay

    if fuel && mains_breaker
      # Genset running, mains breaker closed, power available
      unless @ac_source_enabled
        puts "Fuel and mains breaker relays on, enabling AC source"
        @devices.next3.acsource.enable
        @ac_source_enabled = true
      end
    elsif fuel
      # Warming up or cooling down, no stable power
      if @ac_source_enabled
        puts "Fuel relay on but mains breaker off (warmup/cooldown), disabling AC source"
        @devices.next3.acsource.disable
        @ac_source_enabled = false
      end
    else
      # Genset fully off, fail-safe: enable AC source
      unless @ac_source_enabled
        puts "Genset off (fuel relay off), enabling AC source (fail-safe)"
        @devices.next3.acsource.enable
        @ac_source_enabled = true
      end
    end
  rescue => e
    puts "[ERROR] manage_ac_source: #{e.message}"
  end

  def battery_soc
    @devices.weco.avg_soc
  rescue => e
    puts "[WARN] Weco SoC unavailable (#{e.message}), falling back to Next3"
    @devices.next3.battery.soc
  end

  def genset_running?
    @devices.gencomm.is_running?
  rescue => e
    puts "[ERROR] genset_running? check failed: #{e.message}"
    false
  end

  def victron_inverter_only?
    @devices.victron.mode == Devices::Victron::VEBUS_MODE_INVERTER_ONLY
  rescue => e
    puts "[ERROR] victron_inverter_only? check failed: #{e.message}"
    false
  end

  # Aux1 operating mode: 0 = Manual Off, 1 = Manual On, 2 = Auto
  def aux1_operating_mode
    @devices.next3.aux1.operating_mode
  end

  # Set aux1 relay operating mode on the Next3.
  # 0 = Manual Off, 1 = Manual On, 2 = Auto
  def set_aux_mode(mode)
    puts "Setting aux1 operating mode to #{mode}"
    @devices.next3.aux1.operating_mode = mode
  end

  # Per-phase current capacity: inverter 22A, genset adds 50A
  def per_phase_capacity
    genset_running? ? INVERTER_CURRENT_LIMIT + GENSET_CURRENT_LIMIT : INVERTER_CURRENT_LIMIT
  end

  def phase_current
    (1..3).map do |phase|
      @devices.next3.acload.current(phase)
    end
  end

  def phase_voltage
    (1..3).map do |phase|
      @devices.next3.acload.voltage(phase)
    end
  end

  def low_voltage?
    phase_voltage.any? { |v| v < MIN_PHASE_VOLTAGE }
  end

  def update_phase_current_history
    @phase_current_history << phase_current
    @phase_current_history.shift if @phase_current_history.size > 60
  end

  # Check if any phase is currently overloaded
  def phase_overloaded?
    capacity = per_phase_capacity
    phase_current.any? { |c| c >= capacity }
  end

  # Check if adding amps would overload any phase
  def phase_allows?(amps)
    capacity = per_phase_capacity
    phase_current.max + amps < capacity
  end

  # Returns true if the current on any phase has been over the limit for 25s in a row,
  # during the last 5 minutes
  def high_phase_current?
    not phase_current_capacity?(0)
  end

  # Can the requested current be added without overload? Look at the current draw
  # for the past 5 minutes
  def phase_current_capacity?(requested_current)
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

  # Shelly demand management
  def register_shelly_demand(host, amps)
    @shelly_demands_mutex.synchronize do
      puts "Registering Shelly demand: #{host} (#{amps}A)"
      @shelly_demands[host] = { amps:, active: false, unmet_since: nil }
      @last_shelly_demand_at = Time.monotonic

      if phase_allows?(amps)
        puts "Activating Shelly #{host} (#{amps}A) on registration"
        turn_on_shelly(host)
        @shelly_demands[host][:active] = true
        { activated: true }
      else
        @shelly_demands[host][:unmet_since] = Time.monotonic
        { activated: false, reason: "no_capacity" }
      end
    end
  end

  def deregister_shelly_demand(host)
    @shelly_demands_mutex.synchronize do
      puts "Deregistering Shelly demand: #{host}"
      @shelly_demands.delete(host)
      turn_off_shelly(host)
    end
  end

  def shelly_demands_status
    @shelly_demands_mutex.synchronize { @shelly_demands.dup }
  end

  def manage_shelly_demands
    @shelly_demands_mutex.synchronize do
      has_active = @shelly_demands.any? { |_, d| d[:active] }

      if has_active && low_voltage?
        voltages = phase_voltage.map { |v| v.round(1) }
        puts "Low voltage detected (#{voltages.join("V, ")}V), turning off all active Shelly demands"
        @shelly_demands.each do |host, demand|
          next unless demand[:active]
          turn_off_shelly(host)
          demand[:active] = false
          demand[:unmet_since] = Time.monotonic
        end
        return
      end

      @shelly_demands.each do |host, demand|
        if demand[:active]
          if phase_overloaded?
            puts "Phase overloaded, turning off Shelly #{host}"
            turn_off_shelly(host)
            demand[:active] = false
            demand[:unmet_since] = Time.monotonic
          end
        else
          if phase_allows?(demand[:amps])
            puts "Capacity available, turning on Shelly #{host} (#{demand[:amps]}A)"
            turn_on_shelly(host)
            demand[:active] = true
            demand[:unmet_since] = nil
          end
        end
      end
    end
  end

  # Shed Victron charging load when there's unmet shelly demand and SoC is sufficient.
  # Restore normal mode when all demands are met or SoC drops too low.
  def manage_victron_mode
    @shelly_demands_mutex.synchronize do
      has_unmet = @shelly_demands.any? { |_, d| !d[:active] }

      if has_unmet && !victron_inverter_only? &&
         @devices.victron.battery_soc > VICTRON_INVERTER_ONLY_MIN_SOC
        puts "Unmet shelly demand, setting Victron to inverter-only mode"
        @devices.victron.mode = Devices::Victron::VEBUS_MODE_INVERTER_ONLY
      elsif victron_inverter_only? && (!has_unmet ||
            @devices.victron.battery_soc <= VICTRON_INVERTER_ONLY_MIN_SOC)
        puts "Restoring Victron to normal mode"
        @devices.victron.mode = Devices::Victron::VEBUS_MODE_ON
      end
    end
  rescue => e
    puts "[ERROR] manage_victron_mode: #{e.message}"
  end

  def manage_genset_for_demand
    @shelly_demands_mutex.synchronize do
      now = Time.monotonic
      demand_ready = @shelly_demands.any? do |_, d|
        d[:unmet_since] && now - d[:unmet_since] >= GENSET_DEMAND_START_DELAY
      end

      if demand_ready && !@genset_started_for_demand && !genset_running?
        puts "Shelly demand unmet for #{GENSET_DEMAND_START_DELAY}s, starting genset"
        set_aux_mode(1)
        @genset_started_for_demand = true
      end

      if @genset_started_for_demand
        if @shelly_demands.empty? && @last_shelly_demand_at &&
           Time.monotonic - @last_shelly_demand_at >= GENSET_DEMAND_STOP_DELAY
          puts "No shelly demand for #{GENSET_DEMAND_STOP_DELAY / 60} minutes, stopping genset"
          set_aux_mode(2)
          @genset_started_for_demand = false
        end
      end
    end
  end


  def solar_excess?
    @devices.next3.solar.excess?
  rescue => e
    puts "[ERROR] solar_excess? check failed: #{e.message}"
    false
  end

  def phase_current_under?(limit)
    return false if @phase_current_history.empty?
    @phase_current_history.last.all? { |c| c < limit }
  end

  def has_unmet_shelly_demand?
    @shelly_demands_mutex.synchronize { @shelly_demands.any? { |_, d| !d[:active] } }
  end

  def has_shelly_demand?
    @shelly_demands_mutex.synchronize { @shelly_demands.any? }
  end

  def manage_heaters
    genset = genset_running?
    demand = has_unmet_shelly_demand?
    heater_limit = genset ? HEATER_MAX_PHASE_CURRENT + GENSET_CURRENT_LIMIT : HEATER_MAX_PHASE_CURRENT
    over_limit = !phase_current_under?(heater_limit)

    if over_limit
      turn_off_all_heaters("not under current limit for heaters (#{heater_limit}A)")
      return
    elsif demand
      turn_off_all_heaters("unmet shelly demand")
      return
    elsif !genset && (soc = battery_soc) < SOLAR_EXCESS_HEATER_STOP_SOC
      turn_off_all_heaters("SoC #{soc}% below #{SOLAR_EXCESS_HEATER_STOP_SOC}%")
      return
    end

    return if !genset && !solar_excess?
    return if has_shelly_demand?

    # Priority: 2kW shelly heaters first (one per iteration)
    SHELLY_HEATER_2KW.each do |heater|
      if heater_2kw_on?(heater)
        next # already on
      else
        turn_on_shelly(heater[:host])
        return # turn on one heater at a time and re-evaluate conditions in next loop to avoid overload
      end
    end

    # Then relay heaters (only when no shelly demand)
    unless @devices.relays.heater_6kw?
      puts "Turning on 6kW heater"
      @devices.relays.heater_6kw = true
      return
    end

    unless @devices.relays.heater_9kw?
      puts "Turning on 9kW heater"
      @devices.relays.heater_9kw = true
      return
    end
  end

  def turn_off_all_heaters(reason = nil)
    if @devices.relays.heater_9kw?
      puts "Turning off 9kW heater#{reason ? " (#{reason})" : ""}"
      @devices.relays.heater_9kw = false
    end
    if @devices.relays.heater_6kw?
      puts "Turning off 6kW heater#{reason ? " (#{reason})" : ""}"
      @devices.relays.heater_6kw = false
    end
    SHELLY_HEATER_2KW.each do |heater|
      if heater_2kw_on?(heater)
        puts "Turning off 2kW heater #{heater[:host]}#{reason ? " (#{reason})" : ""}"
        turn_off_shelly(heater[:host])
      end
    end
  end

  # Adapt go-e charger amperage so that L1 on the inverter never exceeds INVERTER_CURRENT_LIMIT.
  # Calculates the non-charger load on L1, then sets the charger to use whatever headroom remains.
  def manage_goe_amperage
    return if @goe_unavailable
    return unless @devices.goe.car_connected?

    # Only charge with solar (SoC >= 95% implies solar is producing) or genset
    soc = battery_soc
    if has_shelly_demand? || (soc < SOLAR_EXCESS_HEATER_STOP_SOC && !genset_running?)
      if @devices.goe.allow != 0
        reason = has_shelly_demand? ? "shelly demand" : "SoC #{soc.round}% < #{SOLAR_EXCESS_HEATER_STOP_SOC}% and no genset"
        puts "go-e: pausing charging (#{reason})"
        @devices.goe.allow = false
      end
      return
    end

    l1_current = @devices.next3.acload.current(1)
    current_setting = @devices.goe.ampere
    limit = per_phase_capacity

    other_load = l1_current - current_setting
    target = (limit - other_load).floor
    target = target.clamp(0, Devices::GoE::MAX_AMPS)

    if target < Devices::GoE::MIN_AMPS
      if @devices.goe.allow != 0
        puts "go-e: L1 headroom too low (#{(limit - other_load).round(1)}A), pausing charging"
        @devices.goe.allow = false
      end
    else
      if @devices.goe.allow == 0
        puts "go-e: L1 headroom available (#{target}A), resuming charging at #{target}A"
        @devices.goe.ampere = target
        @devices.goe.allow = true
      elsif current_setting != target
        puts "go-e: adjusting amperage #{current_setting}A -> #{target}A (L1: #{l1_current.round(1)}A, other: #{other_load.round(1)}A)"
        @devices.goe.ampere = target
      end
    end
  rescue SocketError, SystemCallError, IOError => e
    @goe_unavailable = true
    puts "[ERROR] go-e charger unavailable: #{e.message}"
  rescue => e
    puts "[ERROR] manage_goe_amperage: #{e.message}"
  end

  def turn_off_heaters
    puts "Turning off heaters"
    turn_off_all_heaters
  end

  def turn_on_2kw_heater(heater)
    puts "Turning on 2kW heater #{heater[:host]} (phase #{heater[:phase]})"
    turn_on_shelly(heater[:host])
  end

  def turn_off_2kw_heater(heater)
    puts "Turning off 2kW heater #{heater[:host]} (phase #{heater[:phase]})"
    turn_off_shelly(heater[:host])
  end

  def heater_2kw_on?(heater)
    response = shelly_rpc(heater[:host], "Switch.GetStatus", { id: 0 })
    JSON.parse(response.body)["result"]["output"]
  rescue => e
    puts "[ERROR] Failed to get 2kW heater status #{heater[:host]}: #{e.message}"
    false
  end

  def turn_on_shelly(host)
    puts "Turning on Shelly #{host}"
    shelly_rpc(host, "Switch.Set", { id: 0, on: true })
  rescue => e
    puts "[ERROR] Failed to turn on Shelly #{host}: #{e.message}"
  end

  def turn_off_shelly(host)
    puts "Turning off Shelly #{host}"
    shelly_rpc(host, "Switch.Set", { id: 0, on: false })
  rescue => e
    puts "[ERROR] Failed to turn off Shelly #{host}: #{e.message}"
  end

  def save_state
    @shelly_demands_mutex.synchronize do
      state = {
        shelly_demands: @shelly_demands,
        genset_started_for_demand: @genset_started_for_demand,
      }
      File.write(STATE_FILE, JSON.pretty_generate(state))
    end
  rescue => e
    puts "[ERROR] Failed to save state: #{e.message}"
  end

  def load_state
    return unless File.exist?(STATE_FILE)

    state = JSON.parse(File.read(STATE_FILE), symbolize_names: true)
    @shelly_demands = (state[:shelly_demands] || {}).transform_keys(&:to_s)
    @genset_started_for_demand = state[:genset_started_for_demand] || false
    puts "Loaded state from #{STATE_FILE}"
  rescue => e
    puts "[ERROR] Failed to load state: #{e.message}"
  end

  def shelly_rpc(host, method, params = {})
    uri = URI("http://#{host}/rpc")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 3
    http.read_timeout = 2
    request = Net::HTTP::Post.new(uri.path, { "Content-Type" => "application/json" })
    request.body = { id: 0, method:, params: }.to_json
    http.request(request)
  end

  # Manage genset start/stop thresholds via Next3 aux1 relay
  def genset_threshold_management(soc = battery_soc)
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
    end

    if current_deactivation != target_deactivation
      puts "Adjusting genset deactivation threshold: #{current_deactivation}% -> #{target_deactivation}%"
      @devices.next3.aux1.soc_deactivation_threshold = target_deactivation
    end
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
