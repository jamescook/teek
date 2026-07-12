# frozen_string_literal: true

require_relative 'widget'
require_relative 'callback_registry'
require_relative 'tag_bindable'

module Teek
  # @api private
  #
  # Extended onto a {Widget} for Tk `text` widgets by {App#create_widget}
  # (registered below) - not meant to be used directly or referenced by
  # class. Adds #tag_bind/#tag_unbind/#tag_delete; see {TagBindable} for
  # why and how these track their callbacks.
  module TextBehavior
    include TagBindable
  end

  Widget.register_behavior('text', TextBehavior)
end
