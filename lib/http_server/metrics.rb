require "zlib"

class HTTPServer
  class Metrics
    def initialize(devices)
      @devices = devices
    end

    @@next3 = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "next3.erb")))
    @@sdmo = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "sdmo.erb")))
    @@eta = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "eta.erb")))
    @@starlink = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "starlink.erb")))
    @@shelly = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "shelly.erb")))
    @@unifi = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "unifi.erb")))
    @@topas = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "topas.erb")))
    @@weco = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "weco.erb")))
    @@relays = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "relays.erb")))
    @@ecowitt = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "ecowitt.erb")))
    @@envistar = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "envistar.erb")))
    @@casa = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "casa.erb")))
    @@grundfos = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "grundfos.erb")))
    @@lk = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "lk.erb")))
    @@gencomm = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "gencomm.erb")))
    @@victron = ERB.new(File.read(File.join(__dir__, "..", "..", "views", "victron.erb")))

    def do_GET(req, res)
      res.content_type = "text/plain"
      metrics =
        case req.path
        when "/metrics/next3"
          @@next3.result_with_hash({ t:, next3: @devices.next3 })
        when "/metrics/sdmo"
          @@sdmo.result_with_hash({ t:, measurements: @devices.sdmo.measurements, status: @devices.sdmo.status_integer })
        when "/metrics/eta"
          @@eta.result_with_hash({ t:, eta: @devices.eta })
        when "/metrics/starlink"
          @@starlink.result_with_hash({ t:, metrics: @devices.starlink.metrics })
        when "/metrics/shelly"
          @@shelly.result_with_hash({ t:, devices: @devices.shelly.devices, device_names: @devices.shelly.device_names })
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
          start = t()
          lk_data = @devices.lk.map do |name, lk|
            Thread.new { [name, lk.zones, lk.actuators] }
          end.map(&:value)
          @@lk.result_with_hash({ t: start, lk_data: })
        when "/metrics/gencomm"
          @@gencomm.result_with_hash({ t:, name: "QAS45", measurements: @devices.gencomm.measurements, accumulated: @devices.gencomm.accumulated, status: @devices.gencomm.status, dpf_status: @devices.gencomm.dpf_status, digital_outputs: @devices.gencomm.digital_outputs })
        when "/metrics/victron"
          @@victron.result_with_hash({ t:, m: @devices.victron.measurements })
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
