#!/usr/bin/env ruby
# One-off script to scan 192.168.0.x for Shelly devices and enable cloud name sync

require "net/http"
require "json"

threads = (1..254).map do |i|
  ip = "192.168.0.#{i}"
  Thread.new(ip) do |ip|
    http = Net::HTTP.new(ip, 80)
    http.open_timeout = 1
    http.read_timeout = 2

    uri = URI("http://#{ip}/rpc/Shelly.GetDeviceInfo")
    res = http.get(uri.path)
    next unless res.is_a?(Net::HTTPSuccess)
    info = JSON.parse(res.body)
    id = info["id"]
    name = info["name"]
    puts "#{ip} #{id} name=#{name.inspect}"

    req = Net::HTTP::Post.new("/rpc/Sys.SetConfig")
    req.content_type = "application/json"
    req.body = JSON.generate({ config: { device: { name_sync: true } } })
    res = http.request(req)
    result = JSON.parse(res.body)
    if result["error"]
      puts "  #{ip} error: #{result["error"]}"
    else
      puts "  #{ip} name_sync enabled: #{result}"
    end
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout
    # not a shelly or not reachable
  end
end

threads.each(&:join)
