require "webrick"
require "zlib"

class PrometheusMetrics
  def initialize(devices)
    next3 = ERB.new(File.read(File.join(__dir__, "..", "views", "next3.erb")))
    genset = ERB.new(File.read(File.join(__dir__, "..", "views", "genset.erb")))
    eta = ERB.new(File.read(File.join(__dir__, "..", "views", "eta.erb")))
    starlink = ERB.new(File.read(File.join(__dir__, "..", "views", "starlink.erb")))
    shelly = ERB.new(File.read(File.join(__dir__, "..", "views", "shelly.erb")))
    @server = WEBrick::HTTPServer.new(
      Port: ENV.fetch("PORT", 8000).to_i,
      AccessLog: [[STDOUT, "#{WEBrick::AccessLog::COMMON_LOG_FORMAT} %T"]])
    @server.mount_proc("/metrics") do |req, res|
      res.content_type = "text/plain"
      threads = [
        Thread.new { next3.result_with_hash({ next3: devices.next3 }) },
        Thread.new { genset.result_with_hash({ measurements: devices.genset.measurements }) },
        Thread.new { eta.result_with_hash({ eta: devices.eta }) },
        Thread.new { starlink.result_with_hash({ status: devices.starlink.status }) },
        Thread.new { shelly.result_with_hash({ plugs: devices.shelly.plugs }) },
      ]
      metrics = ""
      threads.each do |t|
        metrics << (t.value || "")
      rescue => e
        warn "Could not fetch metrics: #{e.inspect}"
        e.backtrace.each { |l| warn "\t#{l}" }
      end
      if req.accept_encoding.include? "gzip"
        res["content-encoding"] = "gzip"
        res.body = Zlib.gzip(metrics)
      else
        res.body = metrics
      end
    end
    @server.mount_proc("/eta") do |req, res|
      res.content_type = "application/xml"
      res.body = devices.eta.menu
    end
  end

  def start
    @server.start
  end

  def stop
    @server.shutdown
  end
end
