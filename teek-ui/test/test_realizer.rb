# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test/tk_test_helper'

class TestRealizer < Minitest::Test
  include TeekTestHelper

  tk_test "realizing a nested tree should create real, mapped widgets at hierarchical paths" do
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
  end

  tk_test "an unnamed node should still realize to a real, addressable Tk path" do
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
  end

  tk_test "handle.configure after realize should mutate the real widget" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Realizer Test') { |ui| ui.label(:greeting, text: 'Hi') }
    session.run_async
    session.app.update

    session[:greeting].configure(text: 'Bye')

    assert_equal 'Bye', session.app.command(session[:greeting].path, :cget, '-text')
  end

  tk_test "an event binding targeting a widget declared later should resolve once the whole tree is realized" do
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
  end

  tk_test "a binding target inside a component should resolve to THAT component's like-named node, never a sibling component's" do
    require 'teek/ui'

    a_fired = false
    b_fired = false
    comp_a_downstream = nil
    session = Teek::UI.app(title: 'Realizer Test') do |ui|
      # each component nested under its own panel, matching how
      # test_component_realtk.rb mounts like-named siblings - two
      # components' children only get distinct real Tk paths when they
      # sit under different real parents.
      ui.panel(:panel_a) do |p|
        p.component { |c| c.button(:trigger, text: 'Trigger A'); comp_a_downstream = c.label(:downstream, text: 'Target A') }
      end
      ui.panel(:panel_b) do |p|
        p.component { |c| c.button(:trigger, text: 'Trigger B'); c.label(:downstream, text: 'Target B') }
      end

      # white-box: target: isn't public DSL yet (see the plain forward-
      # reference test above) - a component's own nodes aren't reachable
      # by name from outside its scope, so walk the tree structurally
      # (each panel has one component's 2 children as its own children,
      # in build order) to attach each component's own binding. A
      # binding's event listener attaches to the TARGET node's path (see
      # the plain forward-reference test above), so generating the event
      # on component A's own :downstream widget below only fires
      # component A's binding if resolution correctly stayed within
      # component A's scope.
      comp_a_trigger_node, comp_a_downstream_node = ui.document.find(:panel_a).children
      comp_b_trigger_node, comp_b_downstream_node = ui.document.find(:panel_b).children
      comp_a_trigger_node.events <<
        Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { a_fired = true }, target: :downstream)
      comp_b_trigger_node.events <<
        Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { b_fired = true }, target: :downstream)
      raise "unexpected build shape" unless comp_a_downstream_node && comp_b_downstream_node
    end
    session.run_async
    session.app.update

    session.app.tcl_eval("event generate #{comp_a_downstream.path} <Button-1>")
    session.app.update

    assert a_fired, "component A's own trigger should have fired component A's own binding"
    refute b_fired, "component A's trigger firing should never fire component B's binding"
  end

  tk_test "a forward reference to a not-yet-built sibling should still resolve when both are inside the same component" do
    require 'teek/ui'

    fired = false
    session = Teek::UI.app(title: 'Realizer Test') do |ui|
      ui.component do |c|
        c.button(:trigger, text: 'Trigger')
        c.label(:downstream, text: 'Target') # declared AFTER :trigger, same component

        trigger_node, = c.document.root.children
        trigger_node.events <<
          Teek::UI::EventBinding.new(event: '<Button-1>', handler: -> { fired = true }, target: :downstream)
      end
    end
    session.run_async
    session.app.update

    _trigger_node, downstream_node = session.document.root.children
    session.app.tcl_eval("event generate #{downstream_node.realized.path} <Button-1>")
    session.app.update

    assert fired, "the intra-component forward-referenced target's binding did not fire"
  end

  tk_test "an error partway through realize should leave the root window unmapped and the session not realized" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Realizer Test') do |ui|
      ui.label(:first, text: 'Ok')
      ui.document.root.add_child(Teek::UI::Node.new(type: :not_a_real_widget_type, name: :bad))
    end

    assert_raises(StandardError) { session.realize }

    assert_raises(Teek::UI::NotRealizedError) { session.app }
  end

  # Locks the invariant the validator's "mixed pack+grid" note relies on
  # instead of checking directly: every container realizes into its own
  # dedicated Tk master, and arrange_children picks exactly one geometry
  # manager per master, so no master should ever end up with a mix of
  # pack- and grid-managed children. Verified against the REAL, realized
  # Tk widget tree (winfo children/winfo manager), not just teek-ui's own
  # Document structure.
  tk_test "every realized master frame should be managed by exactly one geometry manager - representative nested tree: column > grid > row > panel" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Realizer Test') do |ui|
      ui.column(:outer, gap: 4) do |c|
        c.grid(:g, gap: 2) do |g|
          g.cell(row: 0, col: 0) { g.label(:l1, text: 'A') }
          g.cell(row: 0, col: 1) do
            g.row(:r, gap: 2) do |r|
              r.button(:b1, text: 'B')
              r.panel(:p) { |p| p.button(:b2, text: 'C') }
            end
          end
        end
        c.button(:outer_btn, text: 'D')
      end
    end
    session.run_async
    session.app.update

    # walks the REAL, realized Tk widget tree (winfo children/winfo
    # manager) rather than teek-ui's own Document structure - this is
    # what would actually misbehave if the invariant ever broke, wherever
    # the break came from. A local recursive lambda, not a helper method -
    # assert_tk_app re-evaluates this block's own source text in a
    # separate worker context, which has no access to methods defined on
    # the surrounding Minitest::Test class.
    check = lambda do |path|
      children = session.app.split_list(session.app.tcl_eval("winfo children #{path}"))
      managers = children.map { |child| session.app.tcl_eval("winfo manager #{child}") }.reject(&:empty?).uniq
      assert_operator managers.length, :<=, 1,
        "#{path} has children managed by more than one geometry manager: #{managers.inspect}"
      children.each { |child| check.call(child) }
    end
    check.call('.')
  end

  # A genuinely mixed master turns out to be impossible to even construct
  # via pack/grid themselves - Tk's own geometry-manager framework refuses
  # a second manager type for a master once one is active, symmetrically
  # (pack-then-grid and grid-then-pack both raise), with a clear, immediate
  # Teek::TclError - NOT a silent hang, contrary to the original "Tk
  # literally HANGS on this" framing this project started from. Confirmed
  # empirically - place coexists safely with either, confirming overlay
  # (not built yet, place-based) is a genuinely different, safe case. This
  # is a second, independent safety net on top of the realizer's own
  # one-manager-per-master construction invariant the test above locks -
  # not a replacement for it.
  tk_test "Tk's own geometry-manager protection should refuse pack+grid mixing on one master with a clear error" do
    require 'teek/ui'

    session = Teek::UI.app(title: 'Realizer Test') { |ui| ui.panel(:guarded) }
    session.run_async
    session.app.update

    session.app.command('ttk::button', '.guarded.a', text: 'A')
    session.app.command('ttk::button', '.guarded.b', text: 'B')
    session.app.command(:pack, '.guarded.a')

    error = assert_raises(Teek::TclError) { session.app.command(:grid, '.guarded.b', row: 0, column: 0) }
    assert_match(/geometry manager/i, error.message)
  end
end
