# frozen_string_literal: true

require 'set'

module Teek
  # Tracks Ruby callback ids scoped to something narrower than a whole
  # widget - keyed by (container, key) pairs - so they can be released
  # again without waiting for a \<Destroy> that may never come for the
  # thing the callback is actually attached to (an event binding, a menu
  # entry, ...). A single instance is shared across every feature that
  # needs this; callers namespace their own container keys (by
  # convention, [feature_tag, path] tuples) so two features tracking the
  # same underlying path never collide.
  #
  # There is exactly one way to keep the registry in sync: {#reconcile}.
  # Its block is handed the {key => id} hash tracked last time and must
  # return the {key => id} hash that should be tracked now; whatever id
  # drops out between the two gets released. What the block *does* with
  # the hash it's handed is entirely up to the caller - reuse its values
  # as a starting point for a cheap in-memory update (nothing external
  # can silently change an event binding), or ignore it and recompute
  # the truth from scratch by asking Tk (Tk silently renumbers menu
  # entries, so nothing short of asking can be trusted there). The
  # registry itself never knows or cares which one a caller chose.
  #
  # The one hard rule either way: the returned hash must be a DIFFERENT
  # object from the one the block was handed - e.g. +before.merge(...)+,
  # never +before.merge!(...)+ returned as-is. Released ids are computed
  # as +before.values - after.values+; if the block mutates +before+ in
  # place and returns that same object, +before+ and +after+ are
  # identical by the time that subtraction runs, so any id that was
  # dropped or replaced is silently never released - a leak, the exact
  # thing this class exists to prevent.
  #
  # {#forget_all_for_path} is the only thing a \<Destroy> handler needs to
  # call: it releases every container ever registered under a path,
  # regardless of which feature created it, via a reverse index built
  # automatically as a side effect of {#reconcile}.
  class CallbackRegistry
    def initialize(app)
      @app = app
      @entries = Hash.new { |h, k| h[k] = {} }
      @containers_by_path = Hash.new { |h, k| h[k] = Set.new }
    end

    # @yieldparam before [Hash] the {key => id} hash tracked for +container+
    #   as of the last call (empty on the first call)
    # @yieldreturn [Hash] the {key => id} hash that should be tracked now -
    #   must be a different object from +before+ (see class docs above);
    #   do not mutate +before+ in place and return it, or dropped/replaced
    #   ids silently never get released
    # @return [void]
    def reconcile(container)
      track(container)
      before = @entries[container]
      after = yield(before)
      (before.values - after.values).each { |id| @app.unregister_callback(id) }
      @entries[container] = after
    end

    # Release every callback tracked under any container registered for
    # +path+, regardless of which feature created it, and forget them.
    # @return [void]
    def forget_all_for_path(path)
      containers = @containers_by_path.delete(path)
      return unless containers
      containers.each do |container|
        ids = @entries.delete(container)
        ids&.each_value { |id| @app.unregister_callback(id) }
      end
    end

    # Diagnostic aggregate, not itself load-bearing for cleanup - a live
    # snapshot of how many tracked callback ids currently exist, grouped
    # by the tag every {#reconcile} container is already keyed on
    # (+:bind+, +:menu+, +:canvas_bind+, +:tag_bind+, +:widget_option+,
    # +:wm_protocol+, ...). Counts individual ids, not containers - a
    # single container can hold several (e.g. one widget bound to
    # several events). A tag with nothing currently tracked under it is
    # simply absent from the result, not present with a zero count.
    # @return [Hash{Object => Integer}]
    def counts_by_tag
      counts = Hash.new(0)
      @entries.each do |(tag, _path), ids|
        counts[tag] += ids.size unless ids.empty?
      end
      counts
    end

    private

    # Convention, not a type check: every container is [feature_tag, path].
    def track(container)
      @containers_by_path[container.last] << container
    end
  end
end
