require_relative "./devices/next3"
require_relative "./devices/genset"
require_relative "./devices/eta"
require_relative "./devices/starlink"
require_relative "./devices/shelly"
require_relative "./devices/relays"
require_relative "./devices/ups"
require_relative "./devices/unifi"

class Devices
  attr_reader :next3, :genset, :eta, :starlink, :shelly, :relays, :ups, :unifi

  def initialize
    @next3 = Next3.new
    @genset = Genset.new
    @eta = ETA.new("192.168.0.11")
    @starlink = Starlink.new
    @shelly = Shelly.new
    @relays = Relays.new
    @ups = UPS.new
    @unifi = Unifi.new
  end
end
