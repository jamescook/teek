# frozen_string_literal: true

require 'set'

module Teek
  # Tracks Ruby callback ids scoped to something narrower than a whole
  # widget - keyed by (container, key) pairs - so they can be released
  # again without waiting for a <Destroy> that may never come for the
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
  # the hash it's handed is entirely up to the caller - reuse it directly
  # for a cheap in-memory update (nothing external can silently change an
  # event binding), or ignore it and recompute the truth from scratch by
  # asking Tk (Tk silently renumbers menu entries, so nothing short of
  # asking can be trusted there). The registry itself never knows or
  # cares which one a caller chose.
  #
  # {#forget_all_for_path} is the only thing a <Destroy> handler needs to
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
    # @yieldreturn [Hash] the {key => id} hash that should be tracked now
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

    private

    # Convention, not a type check: every container is [feature_tag, path].
    def track(container)
      @containers_by_path[container.last] << container
    end
  end
end
