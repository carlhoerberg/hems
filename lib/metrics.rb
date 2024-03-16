require "webrick"

class PrometheusMetrics
  def initialize(devices)
    erb = ERB.new(File.read(File.join(__dir__, "..", "metrics.erb")))
    @server = WEBrick::HTTPServer.new(
      Port: ENV.fetch("PORT", 8000).to_i,
      AccessLog: [[STDOUT, "#{WEBrick::AccessLog::COMMON_LOG_FORMAT} %T"]])
    @server.mount_proc '/metrics' do |req, res|
      res.content_type = "text/plain"
      res["content_encoding"] = "gzip"
      text = erb.result_with_hash({
        unix_ms: DateTime.now.strftime("%Q"),
        next3: devices.next3,
        genset_measurements: devices.genset.measurements,
      })
      res.body = Zlib.gzip(text)
    end
  end

  def start
    @server.start
  end

  def stop
    @server.shutdown
  end
end
