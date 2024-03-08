require "webrick"
require_relative "./devices"

class PrometheusMetrics
  def self.serve
    server = WEBrick::HTTPServer.new :Port => ENV.fetch("PORT", 8000).to_i
    trap('INT') { server.shutdown }
    trap('TERM') { server.shutdown }

    next3 = Next3.new("localhost", 5002)
    server.mount_proc '/metrics' do |req, res|
      res.content_type = "text/plain"
      res.body = <<~EOF
      # HELP soc Battery state of charge
      # TYPE soc gauge
      soc #{next3.battery.soc} #{unix_ms}
      # HELP temp Battery temperature
      # TYPE temp gauge
      temp #{next3.battery.temp} #{unix_ms}
      # HELP charging_amps Battery charging current
      # TYPE charging_amps gauge
      charging_amps #{next3.battery.charging_amps} #{unix_ms}
      EOF
    end

    server.start
  end

  def self.unix_ms
    DateTime.now.strftime("%Q")
  end
end
