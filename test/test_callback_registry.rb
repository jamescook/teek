# frozen_string_literal: true

# Pure-Ruby tests for Teek::CallbackRegistry - no Tk interpreter needed
# (precedent: test_platform.rb). A fake app stub stands in for the real
# Teek::App, since the registry only ever calls #unregister_callback on it.
#
# There is exactly one way to keep the registry in sync: #reconcile. Its
# block receives the {key => id} hash tracked last time and returns the
# {key => id} hash that should be tracked now - a caller can reuse the
# hash it was handed for a cheap in-memory update, or ignore it entirely
# and recompute the truth from scratch. Both are exercised below; the
# registry behaves identically either way.
#
# forget_all_for_path is the only thing a <Destroy> handler needs - it
# must release every container ever registered under a path in one call,
# regardless of which feature created it.

require 'minitest/autorun'
require_relative '../lib/teek/callback_registry'

class TestCallbackRegistry < Minitest::Test
  class FakeApp
    attr_reader :released

    def initialize
      @released = []
    end

    def unregister_callback(id)
      @released << id
    end
  end

  def setup
    @app = FakeApp.new
    @registry = Teek::CallbackRegistry.new(@app)
  end

  # -- reconcile, in-memory-update style (e.g. bind) ------------------------

  def test_reconcile_tracks_a_new_key_without_releasing_anything
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb1') }
    assert_empty @app.released
  end

  def test_reconcile_releases_the_prior_id_when_a_key_is_overwritten
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb1') }
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb2') }
    assert_equal ['cb1'], @app.released
  end

  def test_reconcile_does_not_release_ids_at_other_keys
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb1') }
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-b>' => 'cb2') }
    assert_empty @app.released
  end

  def test_reconcile_releases_a_key_removed_from_the_returned_hash
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb1') }
    @registry.reconcile([:bind, '.e']) { |before| before.reject { |k, _| k == '<Key-a>' } }
    assert_equal ['cb1'], @app.released
  end

  def test_reconcile_removing_an_untracked_key_is_a_safe_no_op
    @registry.reconcile([:bind, '.e']) { |before| before.reject { |k, _| k == '<Key-a>' } }
    assert_empty @app.released
  end

  def test_reconcile_hands_an_empty_hash_on_the_first_call
    seen = nil
    @registry.reconcile([:bind, '.e']) { |before| seen = before; before }
    assert_equal({}, seen)
  end

  # -- reconcile, recompute-from-scratch style (e.g. menu) ------------------

  def test_reconcile_from_scratch_releases_ids_that_drop_out_of_the_live_set
    @registry.reconcile([:menu, '.m']) { { 'cb1' => 'cb1', 'cb2' => 'cb2' } }
    @registry.reconcile([:menu, '.m']) { { 'cb2' => 'cb2' } }
    assert_equal ['cb1'], @app.released
  end

  def test_reconcile_from_scratch_keeps_ids_that_remain_live
    @registry.reconcile([:menu, '.m']) { { 'cb1' => 'cb1', 'cb2' => 'cb2' } }
    @registry.reconcile([:menu, '.m']) { { 'cb1' => 'cb1', 'cb2' => 'cb2' } }
    assert_empty @app.released
  end

  def test_reconcile_from_scratch_tracks_newly_appeared_ids_without_releasing_anything
    @registry.reconcile([:menu, '.m']) { { 'cb1' => 'cb1' } }
    @registry.reconcile([:menu, '.m']) { { 'cb1' => 'cb1', 'cb2' => 'cb2' } }
    assert_empty @app.released
  end

  def test_reconcile_from_scratch_on_an_empty_live_set_releases_everything_tracked
    @registry.reconcile([:menu, '.m']) { { 'cb1' => 'cb1', 'cb2' => 'cb2' } }
    @registry.reconcile([:menu, '.m']) { {} }
    assert_equal ['cb1', 'cb2'], @app.released.sort
  end

  # -- forget_all_for_path --------------------------------------------------

  def test_forget_all_for_path_releases_a_container
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb1', '<Key-b>' => 'cb2') }
    @registry.forget_all_for_path('.e')
    assert_equal ['cb1', 'cb2'], @app.released.sort
  end

  def test_forget_all_for_path_releases_every_feature_sharing_the_path_in_one_call
    @registry.reconcile([:bind, '.w']) { |before| before.merge('<Key-a>' => 'cb1') }
    @registry.reconcile([:menu, '.w']) { { 'cb2' => 'cb2' } }

    @registry.forget_all_for_path('.w')

    assert_equal ['cb1', 'cb2'], @app.released.sort
  end

  def test_forget_all_for_path_does_not_touch_other_paths
    @registry.reconcile([:bind, '.a']) { |before| before.merge('<Key-a>' => 'cb1') }
    @registry.reconcile([:bind, '.b']) { |before| before.merge('<Key-a>' => 'cb2') }

    @registry.forget_all_for_path('.a')

    assert_equal ['cb1'], @app.released
  end

  def test_forget_all_for_path_on_an_unknown_path_is_a_safe_no_op
    @registry.forget_all_for_path('.nope')
    assert_empty @app.released
  end

  def test_forget_all_for_path_forgets_so_a_second_call_is_a_no_op
    @registry.reconcile([:bind, '.e']) { |before| before.merge('<Key-a>' => 'cb1') }
    @registry.forget_all_for_path('.e')
    @registry.forget_all_for_path('.e')
    assert_equal ['cb1'], @app.released
  end
end
