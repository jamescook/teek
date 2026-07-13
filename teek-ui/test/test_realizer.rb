# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestRealizer < Minitest::Test
  include TeekTestHelper

  def test_realize_creates_real_mapped_widgets_with_hierarchical_paths
    assert_tk_app("realizing a nested tree should create real, mapped widgets at hierarchical paths") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Realizer Test') do |ui|
        ui.panel(:controls) do |p|
          p.button(:go, text: 'Go')
        end
      end
      session.run_async
      session.app.update

      go_handle = session[:go]
      assert_equal '.controls.go', go_handle.path
      assert session.app.winfo.exists?(go_handle.path)
      assert session.app.winfo.ismapped?(go_handle.path), "realized widgets should be packed/visible, not just created"

      session.app.destroy
    end
  end

  def test_unnamed_nodes_get_a_valid_auto_generated_path_segment
    assert_tk_app("an unnamed node should still realize to a real, addressable Tk path") do
      require 'teek/ui'

      handle = nil
      session = Teek::UI.app(title: 'Realizer Test') { |ui| handle = ui.label(text: 'Hi') }
      session.run_async
      session.app.update

      assert session.app.winfo.exists?(handle.path)
      # unnamed nodes get their Document-assigned key (e.g. "#anon1") as
      # their path segment - unique for the whole document, not a
      # per-Realizer-instance counter, so it stays collision-free across
      # separate realize_subtree calls too (see Session#add).
      assert_match(/\A\.\S+\z/, handle.path)

      session.app.destroy
    end
  end

  def test_handle_configure_mutates_the_live_widget_post_realize
    assert_tk_app("handle.configure after realize should mutate the real widget") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Realizer Test') { |ui| ui.label(:greeting, text: 'Hi') }
      session.run_async
      session.app.update

      session[:greeting].configure(text: 'Bye')

      assert_equal 'Bye', session.app.command(session[:greeting].path, :cget, '-text')

      session.app.destroy
    end
  end

  def test_forward_event_target_reference_resolves_and_fires
    assert_tk_app("an event binding targeting a widget declared later should resolve once the whole tree is realized") do
      require 'teek/ui'

      fired = false
      session = Teek::UI.app(title: 'Realizer Test') do |ui|
        ui.button(:trigger, text: 'Trigger')
        ui.label(:downstream, text: 'Target') # declared AFTER :trigger

        # white-box: no event DSL yet (that's a separate bead), so attach the
        # binding directly the way the future DSL will - a forward reference
        # by name to a node the realizer hasn't created yet at build time.
        ui.document.find(:trigger).events <<
          Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { fired = true }, target: :downstream)
      end
      session.run_async
      session.app.update

      downstream_path = session[:downstream].path
      session.app.tcl_eval("event generate #{downstream_path} <Button-1>")
      session.app.update

      assert fired, "the forward-referenced target's binding did not fire"

      session.app.destroy
    end
  end

  def test_realize_is_atomic_on_a_mid_realize_error
    assert_tk_app("an error partway through realize should leave the root window unmapped and the session not realized") do
      require 'teek/ui'

      session = Teek::UI.app(title: 'Realizer Test') do |ui|
        ui.label(:first, text: 'Ok')
        ui.document.root.add_child(Teek::UI::Node.new(type: :not_a_real_widget_type, name: :bad))
      end

      assert_raises(StandardError) { session.realize }

      assert_raises(Teek::UI::NotRealizedError) { session.app }
    end
  end
end
