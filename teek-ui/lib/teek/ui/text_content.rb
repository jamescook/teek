# frozen_string_literal: true

module Teek
  module UI
    # The rich text API for one +ui.text_area+ widget's content - reached
    # via {Handle#text_content}, the same shape {Handle#tagged}/{Handle#line}
    # use to hand back a {CanvasItem}: a small, focused companion object,
    # not a pile of widget-specific methods on {Handle} itself.
    #
    # Indices (every +index+/+from+/+to+/+at+ parameter below) are Tk's own
    # text index syntax, passed through verbatim as Ruby strings -
    # +"1.0"+, +"end"+, +"sel.first"+, +"insert +1 line"+, a mark name,
    # +"@12,34"+ - see the Tk +text+ manual page for the full grammar.
    # This is deliberately NOT wrapped in a new index type - sugar, not a
    # wall. Two Symbol shortcuts cover the common cases: +:end+ and
    # +:cursor+ (the +insert+ mark, renamed to something that doesn't
    # collide with {#insert} the method).
    #
    # Naming: a Tk text "tag" is not an HTML tag - it's a named, reusable
    # set of display properties you apply to ranges, like a CSS class.
    # The primary vocabulary here calls that a "format" (avoiding "style",
    # already taken by ttk's own +style:+ widget option); the Tk-named
    # methods (+tag_configure+, +tag_add+, ...) still work as plain
    # aliases, so 1:1 Tk documentation mapping and Tk-fluent muscle memory
    # both keep working.
    #
    # Every content-mutating method (insert/delete/replace/value=/clear/
    # insert_image) transparently lifts a +-state disabled+ (read-only)
    # widget to +normal+ for the duration of the call and restores it
    # after - Tk itself silently no-ops a mutation against a disabled
    # text widget, which is exactly the kind of Tk wonk this DSL exists
    # to hide. An app author building a read-only log pane never needs to
    # know this footgun exists.
    class TextContent
      INDEX_ALIASES = { end: 'end', cursor: 'insert' }.freeze

      # @api private
      def initialize(app, path)
        @app = app
        @path = path
      end

      # -- Content -------------------------------------------------------

      # @param index [String, Symbol]
      # @param text [String]
      # @param tags [Array<String, Symbol>] format name(s) to apply to
      #   the inserted text, same as Tk's own trailing tagList
      # @return [void]
      def insert(index, text, *tags)
        mutate { @app.command(@path, :insert, resolve_index(index), text, *tags) }
      end

      # @param start [String, Symbol]
      # @param end_ [String, Symbol, nil] a single character at +start+
      #   if omitted, the range +[start, end_)+ otherwise
      # @return [String]
      def get(start = '1.0', end_ = 'end')
        @app.command(@path, :get, resolve_index(start), resolve_index(end_))
      end

      # @param start [String, Symbol]
      # @param end_ [String, Symbol, nil] a single character at +start+
      #   if omitted, the range +[start, end_)+ otherwise
      # @return [void]
      def delete(start, end_ = nil)
        mutate { @app.command(@path, :delete, resolve_index(start), *(end_ ? [resolve_index(end_)] : [])) }
      end

      # Atomic delete-then-insert over +[start, end_)+.
      # @param start [String, Symbol]
      # @param end_ [String, Symbol]
      # @param text [String]
      # @return [void]
      def replace(start, end_, text)
        mutate { @app.command(@path, :replace, resolve_index(start), resolve_index(end_), text) }
      end

      # @return [String] the whole buffer's text, without the synthetic
      #   trailing newline Tk always keeps at +end+
      def value
        get('1.0', 'end-1c')
      end

      # Replaces the whole buffer's content outright.
      # @param text [String]
      # @return [void]
      def value=(text)
        mutate {
          @app.command(@path, :delete, '1.0', 'end')
          @app.command(@path, :insert, '1.0', text)
        }
      end

      # Empties the whole buffer.
      # @return [void]
      def clear
        mutate { @app.command(@path, :delete, '1.0', 'end') }
      end

      # -- Formats (Tk's own "tag") ---------------------------------------

      # Defines (or redefines) a named format - a reusable set of display
      # properties, applied to text ranges via {#apply_format}.
      # @param name [Symbol, String]
      # @param opts [Hash] Tk text-tag options, e.g. +foreground:+/+font:+/+underline:+
      # @return [void]
      def format(name, **opts)
        @app.command(@path, :tag, :configure, name, **opts)
      end
      alias_method :tag_configure, :format

      # Applies a previously-{#format}ted name to a range.
      # @param name [Symbol, String]
      # @param from [String, Symbol]
      # @param to [String, Symbol]
      # @return [void]
      def apply_format(name, from, to)
        @app.command(@path, :tag, :add, name, resolve_index(from), resolve_index(to))
      end
      alias_method :tag_add, :apply_format

      # Removes +name+ from a range - the format definition itself is
      # untouched, still applyable elsewhere; see {#delete_format} to
      # remove the definition entirely.
      # @param name [Symbol, String]
      # @param from [String, Symbol]
      # @param to [String, Symbol]
      # @return [void]
      def clear_format(name, from, to)
        @app.command(@path, :tag, :remove, name, resolve_index(from), resolve_index(to))
      end
      alias_method :tag_remove, :clear_format

      # Deletes a format's definition entirely, and with it every range
      # it was applied to.
      # @param name [Symbol, String]
      # @return [void]
      def delete_format(name)
        @app.command(@path, :tag, :delete, name)
      end
      alias_method :tag_delete, :delete_format

      # @param name [Symbol, String]
      # @return [Array<String>] a flat list of index pairs - +[start1,
      #   end1, start2, end2, ...]+, one pair per contiguous applied range
      def format_ranges(name)
        @app.split_list(@app.command(@path, :tag, :ranges, name))
      end
      alias_method :tag_ranges, :format_ranges

      # Fires on a left click anywhere text carrying +name+ is displayed.
      # Wired through +tag bind+ (not a raw +tcl_eval+), so the existing
      # leak-safe reconcile (teek core's +TagBindInterceptor+, already
      # registered for the +text+ widget) releases the callback if +name+
      # stops being applied anywhere - the same leak-safety every other
      # DSL event binding already gets.
      # @param name [Symbol, String]
      # @yield called with no arguments
      # @return [void]
      def on_format_click(name, &block)
        bind_format_event(name, '<Button-1>', block)
      end
      alias_method :on_tag_click, :on_format_click

      # {#on_format_click}, for an arbitrary Tk event pattern instead of
      # the common left-click case.
      # @param name [Symbol, String]
      # @param event [String] a Tk bind event pattern, e.g. +"Double-Button-1"+
      # @yield called with no arguments
      # @return [void]
      def on_format(name, event, &block)
        bind_format_event(name, resolve_event(event), block)
      end
      alias_method :on_tag, :on_format

      # -- Markers (Tk's own "mark") ---------------------------------------

      # A marker is a named, floating position in the text that moves
      # with edits around it - a bookmark, not a range.
      # @param name [Symbol, String]
      # @param at [String, Symbol] where to place it
      # @return [void]
      def add_marker(name, at:)
        @app.command(@path, :mark, :set, name, resolve_index(at))
      end
      alias_method :mark_set, :add_marker

      # @param name [Symbol, String]
      # @return [void]
      def remove_marker(name)
        @app.command(@path, :mark, :unset, name)
      end
      alias_method :mark_unset, :remove_marker

      # @return [Array<String>] every marker currently defined, including
      #   the built-in +insert+/+current+ ones
      def markers
        @app.split_list(@app.command(@path, :mark, :names))
      end
      alias_method :mark_names, :markers

      # Which way +name+ drifts when text is inserted exactly at it -
      # an advanced, rarely-needed Tk concept, so this stays under its Tk
      # name only (no friendlier alias).
      # @param name [Symbol, String]
      # @param direction [String, Symbol, nil] +:left+/+:right+ to set;
      #   omit to just read the current gravity
      # @return [String] +"left"+ or +"right"+
      def mark_gravity(name, direction = nil)
        if direction
          @app.command(@path, :mark, :gravity, name, direction)
        else
          @app.command(@path, :mark, :gravity, name)
        end
      end

      # -- Search ----------------------------------------------------------

      # @param pattern [String]
      # @param from [String, Symbol] where to start searching
      # @param to [String, Symbol] the search boundary - with
      #   +backwards: true+ this is the earliest index the search may
      #   reach, same as plain Tk +search+
      # @param backwards [Boolean]
      # @param regexp [Boolean] treat +pattern+ as a regular expression
      # @param nocase [Boolean]
      # @return [String, nil] the matching index, or +nil+ if not found
      def search(pattern, from: 'insert', to: 'end', backwards: false, regexp: false, nocase: false)
        args = []
        args << '-backward' if backwards
        args << '-regexp' if regexp
        args << '-nocase' if nocase
        args << '--'
        result = @app.command(@path, :search, *args, pattern, resolve_index(from), resolve_index(to))
        result.empty? ? nil : result
      end

      # -- View / cursor / state --------------------------------------------

      # Scrolls the view so +index+ is visible.
      # @param index [String, Symbol]
      # @return [void]
      def scroll_to(index)
        @app.command(@path, :see, resolve_index(index))
      end
      alias_method :see, :scroll_to

      # Resolves any index expression to its canonical +"line.char"+ form.
      # @param spec [String, Symbol]
      # @return [String]
      def index(spec)
        @app.command(@path, :index, resolve_index(spec))
      end

      # @return [String] the text cursor's current position (the +insert+
      #   mark), as +"line.char"+
      def cursor
        index('insert')
      end

      # Moves the text cursor.
      # @param spec [String, Symbol]
      # @return [void]
      def cursor=(spec)
        add_marker('insert', at: spec)
      end

      # @return [Boolean] whether this widget currently rejects direct
      #   typing/edits (its Tk +-state+ is +disabled+) - {#insert}/
      #   {#delete}/etc still work regardless, temporarily lifting this
      #   for their own duration (see the class docs)
      def read_only
        @app.command(@path, :cget, '-state') == 'disabled'
      end

      # @param value [Boolean]
      # @return [void]
      def read_only=(value)
        @app.command(@path, :configure, state: value ? :disabled : :normal)
      end

      # -- Embedded images ---------------------------------------------------

      # Embeds an image inline in the text flow at +index+.
      # @param index [String, Symbol]
      # @param image [Image, Teek::Photo] anything whose +#to_s+ is a Tcl
      #   image name - a DSL {Image} or a raw {Teek::Photo} both work
      # @return [void]
      def insert_image(index, image:)
        mutate { @app.command(@path, :image, :create, resolve_index(index), image: image) }
      end
      alias_method :image_create, :insert_image

      private

      def resolve_index(spec)
        INDEX_ALIASES.fetch(spec, spec).to_s
      end

      def resolve_event(event)
        event.start_with?('<') ? event : "<#{event}>"
      end

      def bind_format_event(name, event, handler)
        @app.command(@path, :tag, :bind, name, event, proc { |*args| handler.call(*args) })
      end

      # See the class docs - every content-mutating method routes through
      # here so a read-only (+-state disabled+) widget never silently
      # swallows the mutation.
      def mutate
        was_read_only = read_only
        self.read_only = false if was_read_only
        yield
      ensure
        self.read_only = true if was_read_only
      end
    end
  end
end
