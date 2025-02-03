require "zlib"

class HTTPServer
  class Metrics < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, devices)
      super(server)
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

    def do_GET(req, res)
      res.content_type = "text/plain"
      threads = [
        Thread.new { @@next3.result_with_hash({ t:, next3: @devices.next3 }) },
        Thread.new { @@eta.result_with_hash({ t:, eta: @devices.eta }) },
        Thread.new { @@starlink.result_with_hash({ t:, metrics: @devices.starlink.metrics }) },
        Thread.new { @@shelly.result_with_hash({ t:, devices: @devices.shelly.devices }) },
        Thread.new { @@ups.result_with_hash({ t:, ups: @devices.ups }) },
        Thread.new { @@unifi.result_with_hash({ t:, unifi_health: @devices.unifi.health }) },
        Thread.new { @@topas.result_with_hash({ t:, measurements: @devices.topas.measurements, status: @devices.topas.status }) },
        Thread.new { @@weco.result_with_hash({ t:, status: @devices.weco.status }) },
        Thread.new do
          @@genset.result_with_hash({ t:, measurements: @devices.genset.measurements })
        rescue EOFError
          warn "Genset is offline"
        end,
      ]
      metrics = ""
      threads.each do |t|
        metrics << (t.value || "")
      rescue
        # Thread#report_on_exception
      end
      if req.accept_encoding.include? "gzip"
        res["content-encoding"] = "gzip"
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
