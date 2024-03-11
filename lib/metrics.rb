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
      unix_ms = DateTime.now.strftime("%Q")
      res.body = <<~EOF
      # HELP soc Battery state of charge
      # TYPE soc gauge
      soc #{next3.battery.soc} #{unix_ms}
      # HELP temp Battery temperature
      # TYPE temp gauge
      temp #{next3.battery.temp} #{unix_ms}
      # HELP charging_current Battery charging current
      # TYPE charging_amps gauge
      charging_amps #{next3.battery.charging_current} #{unix_ms}
      # TYPE charging_power gauge
      charging_power #{next3.battery.charging_power} #{unix_ms}
      # TYPE day_charging_energy counter
      day_charging_energy #{next3.battery.day_charging_energy} #{unix_ms}
      # TYPE day_discharging_energy counter
      day_discharging_energy #{next3.battery.day_discharging_energy} #{unix_ms}
      EOF
    end

    server.start
  end
end
