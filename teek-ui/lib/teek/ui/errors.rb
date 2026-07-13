# frozen_string_literal: true

module Teek
  module UI
    # Raised by any runtime-only method (Session#app/#every/#after,
    # Handle#path/#configure) called before its node/session has been
    # realized. These don't queue for later - the whole point of a Tk-free
    # build phase is that nothing is pretending to talk to an interpreter
    # that doesn't exist yet.
    class NotRealizedError < StandardError
      def initialize(msg = "not realized yet - call #run, #run_async, or #realize first")
        super
      end
    end
  end
end
