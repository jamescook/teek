# frozen_string_literal: true

# A minimal stand-in for Teek::App, for headless tests that need
# something Realizer/Handle-shaped without a real Tk interpreter -
# Realizer#create/#link/#realize_subtree only ever call .command/.bind/
# .on_close (and, for a menu/window handle, .popup_menu/.window) on
# whatever app they're given, so a fake recording every call is enough
# to assert on exactly what WOULD have happened against real Tk. Shared
# across every headless suite that needs one, so there's a single
# definition to keep in sync with the real Teek::App/Teek::Window
# signatures (see test_fake_app_contract.rb) rather than one per file.
FakeWindow = Struct.new(:path, :modal_calls, :grab_releases) do
  def initialize(path, modal_calls = [], grab_releases = [])
    super
  end

  def modal(global: false, &block)
    modal_calls << { global: global }
    block.call if block
  end

  def grab_release
    grab_releases << true
  end
end

FakeApp = Struct.new(:calls, :binds, :on_closes, :popups, :windows) do
  def initialize(calls = [], binds = [], on_closes = [], popups = [], windows = [])
    super
  end

  def command(cmd, *args, **kwargs)
    calls << [[cmd, *args], kwargs]
    nil
  end

  def bind(path, event, *subs, &block)
    binds << { path: path, event: event, subs: subs, block: block }
    nil
  end

  def on_close(window:, &block)
    on_closes << { window: window, block: block }
    nil
  end

  def popup_menu(menu, x:, y:, entry: nil)
    popups << { menu: menu, x: x, y: y, entry: entry }
    nil
  end

  def window(path = '.')
    win = FakeWindow.new(path)
    windows << win
    win
  end
end
