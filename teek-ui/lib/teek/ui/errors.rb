# frozen_string_literal: true

module Teek
  module UI
    # Raised by any genuinely realize-only method (Session#app, dialogs,
    # #clipboard, Handle#path/#configure/#modal/#grab_release, ...) called
    # before its node/session has been realized. These don't queue for
    # later - the whole point of a Tk-free build phase is that nothing is
    # pretending to talk to an interpreter that doesn't exist yet, and
    # each of these either IS the live app/widget by definition or needs
    # one to do anything meaningful (grabbing input, popping a native
    # dialog). In practice this is rarely hit in real code: all of them
    # are normally called from inside an on_* event handler, which only
    # ever runs after realize - see {Session#every}/{Session#after} for
    # the one case that genuinely IS deferrable, and queues instead.
    class NotRealizedError < StandardError
      def initialize(msg = "not realized yet - call this from an on_* event handler (already " \
                            "post-realize), or after #run/#run_async/#realize")
        super
      end
    end

    # Raised by {Validator#validate!} when the build tree has one or more
    # raise-level problems. The message lists every one found, not just the
    # first, so a build can be fixed in one pass instead of a cycle of
    # "run, hit the next cryptic Tcl error, fix, repeat."
    class ValidationError < StandardError; end

    # Raised when a DSL build method (`ui.button`, `ui.panel`, `ui.raw`,
    # `ui.var`, ...) is called after the build has already realized - the
    # tree is only ever walked into Tk once, at realize, so anything
    # appended to it afterward would just silently never show up. Use
    # {Session#add} instead, which builds and realizes a subtree into the
    # already-running app immediately.
    class ClosedBuilderError < StandardError
      def initialize(msg = "the build has already realized - use session.add(parent_name) { } to add widgets to an already-running app instead")
        super
      end
    end
  end
end
