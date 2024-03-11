require "webrick"
require_relative "./devices/next3"

class PrometheusMetrics
  def self.serve
    server = WEBrick::HTTPServer.new :Port => ENV.fetch("PORT", 8000).to_i
    trap('INT') { server.shutdown }
    trap('TERM') { server.shutdown }

    next3 = Devices::Next3.new
    server.mount_proc '/metrics' do |req, res|
      res.content_type = "text/plain"
      #res.content_encoding = "gzip"
      unix_ms = DateTime.now.strftime("%Q")
      res.body = <<~EOF
      # HELP soc Battery state of charge
      # TYPE soc gauge
      soc #{next3.battery.soc} #{unix_ms}
      # HELP temp Battery temperature
      # TYPE temp gauge
      temp #{next3.battery.temp} #{unix_ms}
      # HELP charging_current Battery charging current
      # TYPE charging_current gauge
      charging_current #{next3.battery.charging_current} #{unix_ms}
      # TYPE charging_power gauge
      charging_power #{next3.battery.charging_power} #{unix_ms}
      # TYPE day_charging_energy counter
      day_charging_energy #{next3.battery.day_charging_energy} #{unix_ms}
      # TYPE day_discharging_energy counter
      day_discharging_energy #{next3.battery.day_discharging_energy} #{unix_ms}
      # TYPE acload_l1_current gauge
      acload_l1_current #{next3.acload.current(1)} #{unix_ms}
      # TYPE acload_l1_voltage gauge
      acload_l1_voltage #{next3.acload.voltage(1)} #{unix_ms}
      # TYPE acload_l1_active_power gauge
      acload_l1_active_power #{next3.acload.active_power(1)} #{unix_ms}
      # TYPE acload_l1_reactive_power gauge
      acload_l1_reactive_power #{next3.acload.reactive_power(1)} #{unix_ms}
      # TYPE acload_l1_apparent_power gauge
      acload_l1_apparent_power #{next3.acload.apparent_power(1)} #{unix_ms}
      # TYPE acload_l1_power_factor gauge
      acload_l1_power_factor #{next3.acload.power_factor(1)} #{unix_ms}
      # TYPE acload_l1_day_consumed_energy counter
      acload_l1_day_consumed_energy #{next3.acload.day_consumed_energy(1)} #{unix_ms}
      # TYPE acload_l2_current gauge
      acload_l2_current #{next3.acload.current(2)} #{unix_ms}
      # TYPE acload_l2_voltage gauge
      acload_l2_voltage #{next3.acload.voltage(2)} #{unix_ms}
      # TYPE acload_l2_active_power gauge
      acload_l2_active_power #{next3.acload.active_power(2)} #{unix_ms}
      # TYPE acload_l2_reactive_power gauge
      acload_l2_reactive_power #{next3.acload.reactive_power(2)} #{unix_ms}
      # TYPE acload_l2_apparent_power gauge
      acload_l2_apparent_power #{next3.acload.apparent_power(2)} #{unix_ms}
      # TYPE acload_l2_power_factor gauge
      acload_l2_power_factor #{next3.acload.power_factor(2)} #{unix_ms}
      # TYPE acload_l2_day_consumed_energy counter
      acload_l2_day_consumed_energy #{next3.acload.day_consumed_energy(2)} #{unix_ms}
      # TYPE acload_l3_current gauge
      acload_l3_current #{next3.acload.current(3)} #{unix_ms}
      # TYPE acload_l3_voltage gauge
      acload_l3_voltage #{next3.acload.voltage(3)} #{unix_ms}
      # TYPE acload_l3_active_power gauge
      acload_l3_active_power #{next3.acload.active_power(3)} #{unix_ms}
      # TYPE acload_l3_reactive_power gauge
      acload_l3_reactive_power #{next3.acload.reactive_power(3)} #{unix_ms}
      # TYPE acload_l3_apparent_power gauge
      acload_l3_apparent_power #{next3.acload.apparent_power(3)} #{unix_ms}
      # TYPE acload_l3_power_factor gauge
      acload_l3_power_factor #{next3.acload.power_factor(3)} #{unix_ms}
      # TYPE acload_l3_day_consumed_energy counter
      acload_l3_day_consumed_energy #{next3.acload.day_consumed_energy(1)} #{unix_ms}
      # TYPE acsource_l1_voltage gauge
      acsource_l1_voltage #{next3.acsource.voltage(1)} #{unix_ms}
      # TYPE acsource_l1_current gauge
      acsource_l1_current #{next3.acsource.current(1)} #{unix_ms}
      # TYPE acsource_l1_power_factor gauge
      acsource_l1_power_factor #{next3.acsource.power_factor(1)} #{unix_ms}
      # TYPE acsource_l2_voltage gauge
      acsource_l2_voltage #{next3.acsource.voltage(2)} #{unix_ms}
      # TYPE acsource_l2_current gauge
      acsource_l2_current #{next3.acsource.current(2)} #{unix_ms}
      # TYPE acsource_l2_power_factor gauge
      acsource_l2_power_factor #{next3.acsource.power_factor(2)} #{unix_ms}
      # TYPE acsource_l3_voltage gauge
      acsource_l3_voltage #{next3.acsource.voltage(3)} #{unix_ms}
      # TYPE acsource_l3_current gauge
      acsource_l3_current #{next3.acsource.current(3)} #{unix_ms}
      # TYPE acsource_l3_power_factor gauge
      acsource_l3_power_factor #{next3.acsource.power_factor(3)} #{unix_ms}
      EOF
    end

    server.start
  end
end
