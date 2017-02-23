require "eventmachine"

module Sensu
  class Timer < EventMachine::Timer; end

  # This fix comes from http://soohwan.blogspot.ca/2011/02/fix-eventmachineperiodictimer.html
  class PeriodicTimer < EventMachine::PeriodicTimer
    alias :original_initialize :initialize
    alias :original_schedule :schedule

    # Record initial start time and the fixed interval, used for
    # compensating for timer drift when scheduling the next call.
    def initialize(interval, callback=nil, &block)
      @start = Time.now
      @fixed_interval = interval
      original_initialize(interval, callback, &block)
    end

    # Calculate the timer drift and compensate for it.
    def schedule
      compensation = (Time.now - @start) % @fixed_interval
      @interval = @fixed_interval - compensation
      original_schedule
    end
  end
end
