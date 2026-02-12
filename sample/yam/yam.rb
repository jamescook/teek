# frozen_string_literal: true
# teek-record: title=Yet Another Minesweeper, audio=1
#
# Minesweeper clone built with Teek.
#
# Demonstrates:
#   - Loading and resizing PNG images with Tk's photo system
#   - Canvas-based game grid using image items
#   - Click handling via canvas coordinate math (not per-item bindings)
#   - Tcl variables for live-updating labels (-textvariable)
#   - Menus with radiobuttons and keyboard accelerators
#   - Scheduling repeated work with app.after
#   - register_callback to bridge Ruby procs into Tcl event handlers
#
# Tile artwork: "Minesweeper Tile Set" by eugeneloza (CC0)
# https://opengameart.org/content/minesweeper-tile-set
#
# Sound effects: generated with jsfxr (https://sfxr.me), public domain
# Music: "Vaporware" by The Cynic Project (CC0)
#   https://opengameart.org/content/calm-piano-1-vaporware
#   cynicmusic.com / pixelsphere.org

require_relative '../../lib/teek'
require_relative '../../teek-sdl2/lib/teek/sdl2'

class Minesweeper
  # The source PNGs are 216x216. Tk can shrink them with "copy -subsample N N"
  # which keeps every Nth pixel. 216 / 6 = 36, giving us nice 36px tiles.
  TILE_SIZE = 36
  SUBSAMPLE = 6

  LEVELS = {
    beginner:     { cols: 9,  rows: 9,  mines: 10 },
    intermediate: { cols: 16, rows: 16, mines: 40 },
    expert:       { cols: 30, rows: 16, mines: 99 }
  }.freeze

  attr_reader :app

  def initialize(app, level: :beginner)
    @app = app
    @level = level
    apply_level
    load_images
    load_sounds
    build_ui
    new_game
  end

  # Simulate press/release on a cell for demo/test automation.
  def press_cell(r, c) = on_left_press(r, c)
  def release_cell(r, c) = on_left_release(r, c)

  private

  # -- Setup ---------------------------------------------------------------

  def apply_level
    cfg = LEVELS[@level]
    @cols  = cfg[:cols]
    @rows  = cfg[:rows]
    @num_mines = cfg[:mines]
  end

  # Tk's "image create photo" loads a PNG into a named in-memory image.
  # The full 216x216 images are too large for game tiles, so we create a
  # second (empty) photo and copy into it with -subsample to shrink.
  # After copying, we delete the full-size image to free memory.
  #
  # The resulting @img hash maps game state keys (:hidden, :flag, 1..8, etc.)
  # to Tk photo names we can assign to canvas image items later.
  def load_images
    dir = File.join(__dir__, 'assets')
    @img = {}

    # Map game state keys to the PNG filename suffixes in assets/
    tiles = { hidden: 'X', empty: '0', flag: 'F', mine: 'M' }
    (1..8).each { |n| tiles[n] = n.to_s }

    tiles.each do |key, suffix|
      full  = "ms_full_#{suffix}"
      small = "ms_#{suffix}"
      path  = File.join(dir, "MINESWEEPER_#{suffix}.png")

      # Load full-size PNG into a temporary Tk photo
      @app.command(:image, :create, :photo, full, file: path)

      # Create the smaller photo and copy with subsampling.
      # -subsample takes two separate int args (x y), which command() can't
      # express as a single kwarg, so this line stays as tcl_eval.
      @app.command(:image, :create, :photo, small)
      @app.tcl_eval("#{small} copy #{full} -subsample #{SUBSAMPLE} #{SUBSAMPLE}")

      # Free the full-size image -- we only need the 36x36 version
      @app.command(:image, :delete, full)
      @img[key] = small
    end
  end

  def load_sounds
    dir = File.join(__dir__, 'assets')
    @snd_click     = Teek::SDL2::Sound.new(File.join(dir, 'click.wav'))
    @snd_sweep     = Teek::SDL2::Sound.new(File.join(dir, 'sweep.wav'))
    @snd_flag      = Teek::SDL2::Sound.new(File.join(dir, 'flag.wav'))
    @snd_explosion = Teek::SDL2::Sound.new(File.join(dir, 'explosion.wav'))
    @music = Teek::SDL2::Music.new(File.join(dir, 'music.mp3'))
    @music.volume = 48
    @music_on = true
  end

  def build_ui
    # "wm" commands control the window manager -- title, resizability, etc.
    # "." is the root Tk window (every widget path starts from here).
    @app.command(:wm, :title, '.', 'Yet Another Minesweeper')
    @app.command(:wm, :resizable, '.', 0, 0)

    build_menu
    build_header
    build_canvas
  end

  # Tk menus: create a menu widget, attach it to the window with "configure
  # -menu", then add items. Each item that triggers Ruby code needs a
  # registered callback -- register_callback returns an integer ID, and
  # "ruby_callback <id>" in Tcl invokes the corresponding Ruby proc.
  def build_menu
    @app.command(:menu, '.menubar')
    @app.command('.', :configure, menu: '.menubar')
    @app.command(:menu, '.menubar.game', tearoff: 0)
    @app.command('.menubar', :add, :cascade, label: 'Game', menu: '.menubar.game')

    # "add command" creates a clickable menu item.
    # -accelerator is cosmetic (shows "F2" in the menu) -- the actual
    # keybinding is set separately with "bind".
    # With command(), procs are auto-registered as callbacks -- no need
    # to manually call register_callback + interpolate the ID.
    new_game_proc = proc { |*| new_game }
    @app.command('.menubar.game', :add, :command,
                 label: 'New Game', accelerator: 'F2', command: new_game_proc)
    @app.command(:bind, '.', '<F2>', new_game_proc)

    @app.command('.menubar.game', :add, :separator)

    # "add radiobutton" items share a Tcl variable -- Tk automatically shows
    # a bullet next to the selected one. The -variable points to a global
    # Tcl variable (:: prefix), and -value is what gets stored when selected.
    @level_var = '::ms_level'
    @app.command(:set, @level_var, @level)
    LEVELS.each_key do |lvl|
      @app.command('.menubar.game', :add, :radiobutton,
                   label: lvl.capitalize, variable: @level_var, value: lvl,
                   command: proc { |*| change_level(lvl) })
    end

    @app.command('.menubar.game', :add, :separator)

    @app.command('.menubar.game', :add, :command,
                 label: 'Exit', command: proc { |*| @app.command(:destroy, '.') })
  end

  # The header bar uses "pack" geometry: mine counter on the left, face
  # button expanding to fill the center, timer on the right.
  #
  # -textvariable connects a label to a Tcl variable. When we later do
  # "set ::ms_mines 7", the label updates automatically -- no manual
  # refresh needed. This is one of Tk's nicest features.
  def build_header
    @app.command(:frame, '.hdr', relief: :raised, bd: 2)
    @app.command(:pack, '.hdr', fill: :x)

    # Mine counter (left) -- red digits on black, like the classic LCD look
    @mine_var = '::ms_mines'
    @app.command(:set, @mine_var, @num_mines)
    @app.command(:label, '.hdr.mines', textvariable: @mine_var, width: 4,
                 font: 'TkFixedFont 14 bold', fg: :red, bg: :black,
                 relief: :sunken, anchor: :center)
    @app.command(:pack, '.hdr.mines', side: :left, padx: 5, pady: 3)

    # Face button (center) -- doubles as new-game button
    @face = '.hdr.face'
    @app.command(:button, @face, text: ':)', width: 3,
                 font: 'TkFixedFont 12 bold',
                 command: proc { |*| new_game })
    @app.command(:pack, @face, side: :left, expand: 1, padx: 5, pady: 3)

    # Timer (right)
    @time_var = '::ms_time'
    @app.command(:set, @time_var, 0)
    @app.command(:label, '.hdr.time', textvariable: @time_var, width: 4,
                 font: 'TkFixedFont 14 bold', fg: :red, bg: :black,
                 relief: :sunken, anchor: :center)
    @app.command(:pack, '.hdr.time', side: :right, padx: 5, pady: 3)

    # Music toggle (right, next to timer)
    @music_btn = '.hdr.music'
    @app.command(:button, @music_btn, text: "\u266A", width: 2,
                 font: 'TkDefaultFont 10',
                 command: proc { |*| toggle_music })
    @app.command(:pack, @music_btn, side: :right, padx: 2, pady: 3)
  end

  # The game grid is a single Tk canvas filled with image items.
  #
  # Instead of binding a click handler to each of the 81+ cells (which would
  # mean hundreds of registered callbacks), we bind ONE handler to the whole
  # canvas. The trick: Tk's bind substitution "%x %y" gives us the pointer
  # coordinates. We stash them in Tcl variables, then in the Ruby callback
  # we read those variables and divide by TILE_SIZE to get row/col.
  #
  # "canvasx %x" converts window coords to canvas coords (matters if the
  # canvas is scrolled, though we don't scroll here).
  def build_canvas
    cw = @cols * TILE_SIZE
    ch = @rows * TILE_SIZE
    @canvas = '.c'
    @app.command(:canvas, @canvas, width: cw, height: ch, highlightthickness: 0)
    @app.command(:pack, @canvas)

    # Left-click: press shows sunken tile + suspense face, release reveals.
    # This mimics classic Windows Minesweeper's press-and-hold behavior.
    @pressed_cell = nil

    press_cb = @app.register_callback(proc { |*|
      row, col = canvas_cell
      on_left_press(row, col) if row
    })
    @app.tcl_eval("bind #{@canvas} <ButtonPress-1> " \
                  "{set ::_ms_x [#{@canvas} canvasx %x]; " \
                  "set ::_ms_y [#{@canvas} canvasy %y]; " \
                  "ruby_callback #{press_cb}}")

    release_cb = @app.register_callback(proc { |*|
      row, col = canvas_cell
      on_left_release(row, col) if row
    })
    @app.tcl_eval("bind #{@canvas} <ButtonRelease-1> " \
                  "{set ::_ms_x [#{@canvas} canvasx %x]; " \
                  "set ::_ms_y [#{@canvas} canvasy %y]; " \
                  "ruby_callback #{release_cb}}")

    # Right-click: toggle flag. Binding all three events covers:
    #   Button-2  -- right-click on macOS
    #   Button-3  -- right-click on Linux/Windows
    #   Ctrl+click -- fallback for single-button trackpads
    rcb = @app.register_callback(proc { |*|
      row, col = canvas_cell
      on_right_click(row, col) if row
    })
    %w[Button-2 Button-3 Control-Button-1].each do |ev|
      @app.tcl_eval("bind #{@canvas} <#{ev}> " \
                    "{set ::_ms_x [#{@canvas} canvasx %x]; " \
                    "set ::_ms_y [#{@canvas} canvasy %y]; " \
                    "ruby_callback #{rcb}}")
    end
  end

  # Read the stashed click coordinates and convert to grid position.
  # Returns [row, col] or [nil, nil] if the click was outside the grid.
  def canvas_cell
    mx = @app.command(:set, '::_ms_x').to_f
    my = @app.command(:set, '::_ms_y').to_f
    col = (mx / TILE_SIZE).to_i
    row = (my / TILE_SIZE).to_i
    in_bounds?(row, col) ? [row, col] : [nil, nil]
  end

  # -- Game state ----------------------------------------------------------

  def new_game
    stop_timer
    @game_over   = false
    @first_click = true
    @flags_placed = 0
    @elapsed = 0

    @mine     = Array.new(@rows) { Array.new(@cols, false) }
    @revealed = Array.new(@rows) { Array.new(@cols, false) }
    @flagged  = Array.new(@rows) { Array.new(@cols, false) }
    @adjacent = Array.new(@rows) { Array.new(@cols, 0) }

    # Update the header displays via their Tcl variables
    @app.command(:set, @mine_var, @num_mines)
    @app.command(:set, @time_var, 0)
    @app.command(@face, :configure, text: ':)')

    draw_board
    @music.play if @music_on && !@music.playing?
  end

  # Changing difficulty resizes the canvas and resets. The window auto-shrinks
  # because we set "wm resizable . 0 0" -- Tk recomputes the geometry.
  def change_level(level)
    return if level == @level

    @level = level
    apply_level

    cw = @cols * TILE_SIZE
    ch = @rows * TILE_SIZE
    @app.command(@canvas, :configure, width: cw, height: ch)

    new_game
  end

  # Populate the canvas with hidden-cell images. "canvas create image" places
  # a Tk photo at (x, y) with -anchor nw (top-left corner). It returns a
  # numeric item ID that we store in @cell_id so we can update each cell's
  # image later with "itemconfigure <id> -image <photo>".
  def draw_board
    @app.command(@canvas, :delete, :all)
    @cell_id = Array.new(@rows) { Array.new(@cols) }

    @rows.times do |r|
      @cols.times do |c|
        x = c * TILE_SIZE
        y = r * TILE_SIZE
        @cell_id[r][c] = @app.command(@canvas, :create, :image, x, y,
                                      image: @img[:hidden], anchor: :nw)
      end
    end
  end

  # -- Mine placement ------------------------------------------------------

  # Mines are placed on the first click, not at game start. This guarantees
  # the player's first click is always safe (and so are its neighbors).
  def place_mines(safe_r, safe_c)
    safe = { [safe_r, safe_c] => true }
    neighbors(safe_r, safe_c).each { |nr, nc| safe[[nr, nc]] = true }

    candidates = []
    @rows.times { |r| @cols.times { |c| candidates << [r, c] unless safe[[r, c]] } }
    rng = ENV['SEED'] ? Random.new(ENV['SEED'].to_i) : Random.new
    candidates.shuffle!(random: rng).first(@num_mines).each { |r, c| @mine[r][c] = true }

    # Precompute how many mines neighbor each cell
    @rows.times do |r|
      @cols.times do |c|
        next if @mine[r][c]
        @adjacent[r][c] = neighbors(r, c).count { |nr, nc| @mine[nr][nc] }
      end
    end
  end

  # -- Click handlers ------------------------------------------------------

  def on_left_press(r, c)
    return if @game_over || @flagged[r][c] || @revealed[r][c]

    # Show sunken/pressed tile and suspense face
    @pressed_cell = [r, c]
    set_cell_image(r, c, :empty)
    @app.command(@face, :configure, text: ':o')
  end

  def on_left_release(r, c)
    prev = @pressed_cell
    @pressed_cell = nil

    # Restore face
    @app.command(@face, :configure, text: ':)') unless @game_over

    # If released on a different cell than pressed, restore the pressed cell
    if prev && prev != [r, c]
      pr, pc = prev
      set_cell_image(pr, pc, :hidden) unless @revealed[pr][pc]
      return
    end

    return if @game_over || @flagged[r][c] || @revealed[r][c]

    if @first_click
      @first_click = false
      place_mines(r, c)
      start_timer
    end

    if @mine[r][c]
      @snd_explosion.play
      game_over_lose(r, c)
    else
      @cascading = false
      reveal(r, c)
      check_win
    end
  end

  def on_right_click(r, c)
    return if @game_over || @revealed[r][c]

    @snd_flag.play
    if @flagged[r][c]
      @flagged[r][c] = false
      @flags_placed -= 1
      set_cell_image(r, c, :hidden)
    else
      @flagged[r][c] = true
      @flags_placed += 1
      set_cell_image(r, c, :flag)
    end
    @app.command(:set, @mine_var, @num_mines - @flags_placed)
  end

  # -- Reveal / win / lose -------------------------------------------------

  # Classic minesweeper flood fill: reveal a cell, and if it has zero
  # adjacent mines, recursively reveal all its neighbors. This produces
  # the satisfying "clearing" effect when you click an open area.
  def reveal(r, c)
    return unless in_bounds?(r, c)
    return if @revealed[r][c] || @flagged[r][c] || @mine[r][c]

    @revealed[r][c] = true
    count = @adjacent[r][c]

    if count == 0
      set_cell_image(r, c, :empty)
      unless @cascading
        @cascading = true
        @snd_sweep.play
      end
      neighbors(r, c).each { |nr, nc| reveal(nr, nc) }
    else
      @snd_click.play unless @cascading
      set_cell_image(r, c, count)
    end
  end

  # Win when every non-mine cell is revealed.
  def check_win
    unrevealed = 0
    @rows.times { |r| @cols.times { |c| unrevealed += 1 unless @revealed[r][c] } }
    return unless unrevealed == @num_mines

    @game_over = true
    stop_timer
    @app.command(@face, :configure, text: 'B)')

    # Auto-flag remaining mines as a visual cue
    @rows.times do |r|
      @cols.times do |c|
        next unless @mine[r][c] && !@flagged[r][c]
        @flagged[r][c] = true
        set_cell_image(r, c, :flag)
      end
    end
    @app.command(:set, @mine_var, 0)
  end

  def game_over_lose(_hit_r, _hit_c)
    @game_over = true
    stop_timer
    @app.command(@face, :configure, text: ':(')
    Teek::SDL2.fade_out_music(1500) if @music_on

    @rows.times do |r|
      @cols.times do |c|
        set_cell_image(r, c, :mine) if @mine[r][c]
      end
    end
  end

  # -- Timer ---------------------------------------------------------------

  # app.after(ms) schedules a Ruby block to run after a delay. It's a
  # one-shot timer, so for repeating work we schedule the next tick at the
  # end of each callback. Checking @timer_running lets us stop the chain
  # cleanly -- the next queued tick just returns without rescheduling.
  def start_timer
    @timer_running = true
    @app.after(1000) { tick_timer }
  end

  def stop_timer
    @timer_running = false
  end

  def tick_timer
    return unless @timer_running
    @elapsed += 1
    @app.command(:set, @time_var, @elapsed)
    @app.after(1000) { tick_timer }
  end

  # -- Music ---------------------------------------------------------------

  def toggle_music
    if @music_on
      @music.pause
      @music_on = false
      @app.command(@music_btn, :configure, text: '--')
    else
      if @music.paused?
        @music.resume
      else
        @music.play
      end
      @music_on = true
      @app.command(@music_btn, :configure, text: "\u266A")
    end
  end

  # -- Helpers -------------------------------------------------------------

  def in_bounds?(r, c)
    r >= 0 && r < @rows && c >= 0 && c < @cols
  end

  # Return [row, col] pairs for all valid neighbors of a cell (up to 8).
  def neighbors(r, c)
    [[-1, -1], [-1, 0], [-1, 1],
     [0, -1],           [0, 1],
     [1, -1],  [1, 0],  [1, 1]].filter_map do |dr, dc|
      nr, nc = r + dr, c + dc
      [nr, nc] if in_bounds?(nr, nc)
    end
  end

  # Swap a cell's displayed image. "itemconfigure" changes properties of an
  # existing canvas item by its numeric ID -- here we just swap -image.
  def set_cell_image(r, c, key)
    @app.command(@canvas, :itemconfigure, @cell_id[r][c], image: @img[key])
  end
end

# -- Main ------------------------------------------------------------------

# track_widgets: false because we manage canvas items ourselves and don't
# need Teek's automatic widget tracking overhead.
app = Teek::App.new(track_widgets: false)

# The root window starts withdrawn by default in Teek -- show it.
app.show

game = Minesweeper.new(app)

# Automated demo support (for rake docker:test and recording)
require_relative '../../lib/teek/demo_support'
TeekDemo.app = app

if TeekDemo.active?
  ENV['SEED'] = '42'
  game.send(:new_game) # restart with deterministic layout

  if TeekDemo.recording?
    app.set_window_geometry('+0+0')
    app.tcl_eval('. configure -cursor none')
    TeekDemo.signal_recording_ready
  end

  # Capture all audio output to WAV when TEEK_RECORD_AUDIO is set.
  # The WAV can be muxed with the screen recording via ffmpeg:
  #   ffmpeg -i screen.mp4 -i yam_audio.wav -c:v copy -c:a aac -shortest out.mp4
  audio_capture_path = ENV['TEEK_RECORD_AUDIO']
  audio_capture_path = nil if audio_capture_path&.empty?
  Teek::SDL2.start_audio_capture(audio_capture_path) if audio_capture_path

  TeekDemo.after_idle {
    d = TeekDemo.method(:delay)

    # Click (row=2, col=3) — safe reveal, then (row=0, col=4) — mine. Boom!
    steps = [
      -> { game.press_cell(2, 3) },
      -> { game.release_cell(2, 3) },
      nil,
      -> { game.press_cell(0, 4) },
      -> { game.release_cell(0, 4) },
      nil, nil,
      -> {
        Teek::SDL2.stop_audio_capture if audio_capture_path
        TeekDemo.finish
      },
    ]

    i = 0
    run_step = proc {
      steps[i]&.call
      i += 1
      if i < steps.length
        app.after(d.call(test: 50, record: 1500)) { run_step.call }
      end
    }
    run_step.call
  }
end

app.mainloop
