# frozen_string_literal: true

module Teek
  module UI
    # What a {Node} gets in its +realized+ slot once the realizer creates a
    # live widget for it: just enough for a {Handle} to act on the real
    # thing - which app owns it, and its live Tk path.
    RealizedNode = Data.define(:app, :path)
  end
end
