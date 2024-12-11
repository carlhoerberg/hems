require "json"

class Devices
  class Starlink
    def status
      json = `grpcurl -plaintext -d '{"get_status": {}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle`
      raise Error.new("Status failure: #{json}") unless $?.success?

      JSON.parse(json)
    end

    # History is stored in a ring buffer, per second
    # dishGetHistory:
    # current: take the length of the metric array modulus current to get the latest metric
    # powerIn, uplinkThroughputBps, downlinkThroughputBps, popPingLatencyMs, popPingDrotRate
    # outages is an array of objects with recent outages
    def history
      json = `grpcurl -plaintext -d '{"get_history": {}}' 192.168.100.1:9200 SpaceX.API.Device.Device/Handle`
      raise Error.new("Status failure: #{json}") unless $?.success?

      JSON.parse(json)
    end

    # Metrics for the last 5 seconds
    def metrics
      h = history["dishGetHistory"]
      current = h["current"].to_i
      %w(powerIn uplinkThroughputBps downlinkThroughputBps popPingLatencyMs popPingDropRate).to_h do |key|
        values = h[key]
        index = current % values.length # index of the last updated value in the ring buffer
        last_5 = values.rotate!(index - 4).take(5) # rotate the ring so that the 5 last values are first
        value = last_5.max # take the largest of the values from the past 5s
        [key.gsub(/([A-Z])/, '_\1').downcase, value]
      end
    end

    class Error < StandardError; end
  end
end
