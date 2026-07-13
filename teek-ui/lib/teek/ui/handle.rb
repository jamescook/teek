# frozen_string_literal: true

require_relative 'errors'
require_relative 'realized_node'
require_relative 'event_binding'
require_relative 'keysyms'

module Teek
  module UI
    # The single handle type for a node, valid across both phases (Resolved
    # decision #3 in the architecture doc - no separate build-time NodeRef).
    # During build you compose/name/record-events on it; live methods
    # (#path, #configure) raise {NotRealizedError} until the node's
    # +realized+ slot is filled in by the realizer, then the same Handle
    # object drives the real widget through it.
    class Handle
      RIGHT_CLICK_EVENTS = %w[<Button-2> <Button-3> <Control-Button-1>].freeze
      MENU_HANDLE_TYPES = %i[menu context_menu].freeze

      # @api private
      def initialize(node)
        @node = node
      end

      # @return [Symbol] the node's type, e.g. +:button+
      def type
        @node.type
      end

      # @return [Symbol, nil] the node's explicit name
      def name
        @node.name
      end

      # @return [String] the live Tk widget path
      # @raise [NotRealizedError] before realize
      def path
        realized.path
      end

      # Mutate the live widget's options.
      # @param opts [Hash] widget options, e.g. +text: "Go"+
      # @raise [NotRealizedError] before realize
      def configure(**opts)
        realized.app.command(realized.path, :configure, **opts)
      end

      # Fires on a left click.
      # @yield called with no arguments
      # @return [self]
      def on_click(&block)
        bind_event('<Button-1>', block)
        self
      end

      # Fires on a right click, however the platform spells it (Button-3 on
      # Linux/Windows, Button-2 or Control-Button-1 on macOS). Either handle
      # it yourself with a block, or hand it a `:menu`/`:context_menu`
      # handle to pop up at the click's screen position - not both.
      # @param menu [Handle, nil] a `:menu` or `:context_menu` handle to tk_popup
      # @yield called with no arguments (only when +menu+ isn't given)
      # @return [self]
      # @raise [ArgumentError] if given neither or both, or +menu+ isn't a menu handle
      def on_right_click(menu = nil, &block)
        if menu && block
          raise ArgumentError, "on_right_click takes either a menu handle or a block, not both"
        elsif menu
          unless MENU_HANDLE_TYPES.include?(menu.type)
            raise ArgumentError, "on_right_click(menu) needs a :menu or :context_menu handle (got a :#{menu.type})"
          end

          popup = lambda do |root_x, root_y|
            realized.app.popup_menu(menu.path, x: root_x, y: root_y)
          end
          RIGHT_CLICK_EVENTS.each { |event| bind_event(event, popup, subs: %i[root_x root_y]) }
        elsif block
          RIGHT_CLICK_EVENTS.each { |event| bind_event(event, block) }
        else
          raise ArgumentError, "on_right_click needs either a menu handle or a block"
        end
        self
      end

      # Fires while dragging (left button held down and moving). Delivers
      # Integer x/y, converted through the widget's own canvasx/canvasy when
      # bound to a canvas so callers never have to remember to do that
      # themselves.
      # @yield [x, y] Integer coordinates
      # @return [self]
      def on_drag(&block)
        drag_type = type
        wrapped = lambda do |raw_x, raw_y|
          block.call(*convert_drag_coords(drag_type, raw_x, raw_y))
        end
        bind_event('<B1-Motion>', wrapped, subs: %i[x y])
        self
      end

      # Fires on a key press. +spec+ is either a friendly Symbol (+:enter+,
      # +:escape+, +:up+, ...) or a "Modifier-Modifier-Key" String
      # (+"Ctrl-s"+, +"Ctrl-Shift-s"+) - see {Keysyms}.
      # @param spec [Symbol, String]
      # @yield called with no arguments
      # @return [self]
      def on_key(spec, &block)
        modifiers, keysym = Keysyms.resolve(spec)
        Keysyms.patterns_for(modifiers, keysym).each { |event| bind_event(event, block) }
        self
      end

      # Fires when the window's close button (titlebar close box, Cmd-W,
      # Alt-F4, ...) is pressed. Teek's own default (destroy the window)
      # only applies when nothing else has claimed it - the block decides
      # whether the window actually closes; call `.destroy` yourself if you
      # want that. Only valid on a `ui.window` handle.
      # @yield called with no arguments
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a window
      def on_close(&block)
        unless type == :window
          raise ArgumentError, "on_close only makes sense on a window (got a :#{type})"
        end

        if @node.realized
          @node.realized.app.on_close(window: @node.realized.path, &block)
        else
          @node.opts[:on_close] = block
        end
        self
      end

      # Show the window modally: grabs input and sets focus on it
      # immediately. Release it explicitly with {#grab_release} (typically
      # from the window's own dismiss/close handling) when the dialog is
      # done - not released automatically just because this method
      # returns, since a modal dialog stays grabbed for its whole visible
      # lifetime, not just its setup. Released immediately if the optional
      # setup block itself raises, or if the window is destroyed while
      # still grabbed - see {Teek::Window#modal}, which this delegates to
      # entirely (no grab/focus/destroy-safety-net logic lives here).
      # Only valid on a `ui.window` handle.
      # @param global [Boolean] see {Teek::Window#grab_set}
      # @yield optional - runs with the grab and focus already set
      # @return [void]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def modal(global: false, &block)
        unless type == :window
          raise ArgumentError, "modal only makes sense on a window (got a :#{type})"
        end

        window.modal(global: global, &block)
      end

      # Release a grab previously set with {#modal}. Only valid on a
      # `ui.window` handle. See {Teek::Window#grab_release}.
      # @return [void]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def grab_release
        unless type == :window
          raise ArgumentError, "grab_release only makes sense on a window (got a :#{type})"
        end

        window.grab_release
      end

      # Reveal the window: positions it just to the right of the parent
      # it's nested under (root, or another window if this one's nested
      # inside it), deiconifies, raises it to the front, and - only if
      # this window was declared `modal: true` - grabs input and focuses
      # it too (via {#modal}). Generalizes gemba's ChildWindow#show_window/
      # #show_modal. Only valid on a `ui.window` handle.
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def show
        unless type == :window
          raise ArgumentError, "show only makes sense on a window (got a :#{type})"
        end

        position_near_parent
        window.deiconify
        realized.app.command(:raise, realized.path)
        modal if @node.opts[:modal]
        self
      end

      # Hide the window: releases any grab {#show} set (a no-op if it
      # wasn't modal - {Teek::Window#grab_release} is always safe to call)
      # and withdraws it. Generalizes gemba's ChildWindow#hide_window.
      # Only valid on a `ui.window` handle.
      # @return [self]
      # @raise [ArgumentError] if this handle isn't a window
      # @raise [NotRealizedError] before realize
      def hide
        unless type == :window
          raise ArgumentError, "hide only makes sense on a window (got a :#{type})"
        end

        grab_release
        window.withdraw
        self
      end

      private

      def realized
        @node.realized or raise NotRealizedError
      end

      def window
        realized.app.window(realized.path)
      end

      # Positions the window just to the right of the parent it's nested
      # under - root by default, or another window's own path when this
      # one is declared inside it. Tk toplevel paths stay hierarchical
      # even though they're independent OS windows (allocate_path nests
      # them the same way any other widget path nests), so the parent's
      # path is just everything before this window's own last path
      # segment - no separate bookkeeping needed to recover it later.
      def position_near_parent
        parent_x, parent_y, parent_width, = realized.app.interp.window_geometry(toplevel_parent_path)
        window.set_geometry("+#{parent_x + parent_width + 12}+#{parent_y}")
      end

      def toplevel_parent_path
        path = realized.path
        last_dot = path.rindex('.')
        last_dot && last_dot.positive? ? path[0...last_dot] : '.'
      end

      def bind_event(event, handler, subs: [])
        binding = EventBinding.new(event: event, handler: handler, subs: subs)

        if @node.realized
          wire(@node.realized, binding)
        else
          @node.events << binding
        end
      end

      def wire(realized_node, binding)
        realized_node.app.bind(realized_node.path, binding.event, *binding.subs) { |*args|
          binding.handler.call(*args)
        }
      end

      def convert_drag_coords(drag_type, raw_x, raw_y)
        if drag_type == :canvas
          info = @node.realized
          x = info.app.command(info.path, :canvasx, raw_x).to_f.round
          y = info.app.command(info.path, :canvasy, raw_y).to_f.round
          [x, y]
        else
          [raw_x.to_i, raw_y.to_i]
        end
      end
    end
  end
end
