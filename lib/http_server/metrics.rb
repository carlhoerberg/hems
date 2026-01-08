require "zlib"

class HTTPServer
  class Metrics
    def initialize(devices)
      @devices = devices
    end

    @@next3 = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "next3.erb")))
    @@genset = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "genset.erb")))
    @@eta = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "eta.erb")))
    @@starlink = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "starlink.erb")))
    @@shelly = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "shelly.erb")))
    @@ups = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "ups.erb")))
    @@unifi = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "unifi.erb")))
    @@topas = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "topas.erb")))
    @@weco = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "weco.erb")))
    @@relays = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "relays.erb")))
    @@ecowitt = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "ecowitt.erb")))
    @@envistar = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "envistar.erb")))
    @@casa = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "casa.erb")))
    @@grundfos = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "grundfos.erb")))
    @@lk = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "lk.erb")))

    def do_GET(req, res)
      res.content_type = "text/plain"
      metrics =
        case req.path
        when "/metrics"
          [
            Thread.new { @@next3.result_with_hash({ t:, next3: @devices.next3 }) },
            Thread.new { @@eta.result_with_hash({ t:, eta: @devices.eta }) },
            Thread.new { @@starlink.result_with_hash({ t:, metrics: @devices.starlink.metrics }) },
            Thread.new { @@shelly.result_with_hash({ t:, devices: @devices.shelly.devices }) },
            Thread.new { @@ups.result_with_hash({ t:, ups: @devices.ups }) },
            Thread.new { @@unifi.result_with_hash({ t:, unifi_health: @devices.unifi.health }) },
            Thread.new { @@topas.result_with_hash({ t:, measurements: @devices.topas.measurements, status: @devices.topas.status }) },
            Thread.new { @@weco.result_with_hash({ t:, modules: @devices.weco.modules, total: @devices.weco.total }) },
            Thread.new { @@relays.result_with_hash({ t:, status: @devices.relays.status }) },
            Thread.new { @@envistar.result_with_hash({ t:, m: @devices.envistar }) },
            Thread.new { @@casa.result_with_hash({ t:, casa: @devices.casa }) },
            Thread.new { @@grundfos.result_with_hash({ t:, grundfos: @devices.grundfos }) },
            Thread.new { @@lk.result_with_hash({ t:, lk_devices: @devices.lk }) },
            Thread.new { @@ecowitt.result_with_hash({ t:, measurements: @devices.ecowitt.measurements }) },
            Thread.new do
              @@genset.result_with_hash({ t:, measurements: @devices.genset.measurements, status: @devices.genset.status_integer })
            rescue EOFError
              warn "Genset is offline"
            end,
          ].map do |t|
            t.value
          rescue
            # Thread#report_on_exception
          end.join
        when "/metrics/next3"
          @@next3.result_with_hash({ t:, next3: @devices.next3 })
        when "/metrics/genset"
          @@genset.result_with_hash({ t:, measurements: @devices.genset.measurements, status: @devices.genset.status_integer })
        when "/metrics/eta"
          @@eta.result_with_hash({ t:, eta: @devices.eta })
        when "/metrics/starlink"
          @@starlink.result_with_hash({ t:, metrics: @devices.starlink.metrics })
        when "/metrics/shelly"
          @@shelly.result_with_hash({ t:, devices: @devices.shelly.devices })
        when "/metrics/ups"
          @@ups.result_with_hash({ t:, ups: @devices.ups })
        when "/metrics/unifi"
          @@unifi.result_with_hash({ t:, unifi_health: @devices.unifi.health })
        when "/metrics/topas"
          @@topas.result_with_hash({ t:, measurements: @devices.topas.measurements, status: @devices.topas.status })
        when "/metrics/weco"
          @@weco.result_with_hash({ t:, modules: @devices.weco.modules, total: @devices.weco.total })
        when "/metrics/relays"
          @@relays.result_with_hash({ t:, status: @devices.relays.status })
        when "/metrics/ecowitt"
          @@ecowitt.result_with_hash({ t:, measurements: @devices.ecowitt.measurements })
        when "/metrics/envistar"
          @@envistar.result_with_hash({ t:, m: @devices.envistar })
        when "/metrics/casa"
          @@casa.result_with_hash({ t:, casa: @devices.casa })
        when "/metrics/grundfos"
          @@grundfos.result_with_hash({ t:, grundfos: @devices.grundfos })
        when "/metrics/lk"
          @@lk.result_with_hash({ t:, lk_devices: @devices.lk })
        else
          res.status = 404
          "Not Found"
        end
      if req.headers["accept-encoding"]&.include? "gzip"
        res.headers["content-encoding"] = "gzip"
        res.body = Zlib.gzip(metrics)
      else
        res.body = metrics
      end
    end

    def t
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
