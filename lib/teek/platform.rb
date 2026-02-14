# frozen_string_literal: true

# Standalone platform detection — no dependencies on the rest of Teek.
# Safe to require from extconf.rb or any context where the full gem
# isn't loaded yet.

module Teek
  class Platform
    def initialize(platform = RUBY_PLATFORM)
      @platform = platform.freeze
    end

    def darwin?  = @platform.include?('darwin')
    def linux?   = @platform.include?('linux')
    def windows? = !!(@platform =~ /mingw|mswin|cygwin/)

    def to_s
      if darwin? then 'darwin'
      elsif windows? then 'windows'
      elsif linux? then 'linux'
      else @platform
      end
    end
  end

  def self.platform
    @platform ||= Platform.new
  end
end
