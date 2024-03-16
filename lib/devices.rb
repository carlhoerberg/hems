require_relative "./devices/next3"
require_relative "./devices/genset"
require_relative "./devices/eta"

class Devices
  attr_reader :next3, :genset, :eta

  def initialize
    @next3 = Next3.new
    @genset = Genset.new
    @eta = ETA.new
  end
end
