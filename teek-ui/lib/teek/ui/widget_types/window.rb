# frozen_string_literal: true

require_relative '../widget_type'

module Teek
  module UI
    # @api private
    #
    # A freshly created :window's post-creation setup: title/geometry/
    # resizable setup, transient-to-parent, the macOS shared-menubar quirk
    # (each platform other than macOS gets its own menu bar per window;
    # macOS has a single app-wide menu bar, so without this a new window
    # falls back to Tk's default "wish" menu instead of the parent's), and
    # withdrawn by default - shown explicitly via Handle#show. Registered
    # as :window's own `post_create:` below.
    module WindowRealize
      def self.post_create(app, node, path, parent_path)
        opts = node.opts
        window = app.window(path)

        window.set_title(opts[:title]) if opts[:title]
        window.set_geometry(opts[:geometry]) if opts[:geometry]
        if opts.key?(:resizable)
          pair = opts[:resizable]
          width, height = pair.is_a?(Array) ? pair : [pair, pair]
          window.set_resizable(width, height)
        end
        app.command(:wm, :transient, path, parent_path) unless opts[:transient] == false
        share_macos_menu(app, path, parent_path) if Teek.platform.darwin?
        window.withdraw
      end

      def self.share_macos_menu(app, path, parent_path)
        parent_menu = app.command(parent_path, :cget, '-menu')
        app.command(path, :configure, menu: parent_menu) unless parent_menu.nil? || parent_menu.empty?
      rescue Teek::TclError
        nil
      end
    end
  end
end

# A toplevel - placed by the window manager, never pack/grid-managed by
# its nominal parent.
Teek::UI::WidgetTypes.register(
  Teek::UI::WidgetType.new(
    type: :window, tk_command: 'toplevel', leaf: false, arranged: false,
    post_create: Teek::UI::WindowRealize.method(:post_create)
  )
)
