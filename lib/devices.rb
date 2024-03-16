require_relative "./devices/next3"
require_relative "./devices/genset"

class Devices
  attr_reader :next3, :genset

  def initialize
    @next3 = Next3.new
    @genset = Genset.new
  end
end
