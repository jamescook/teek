#!/usr/bin/env ruby
# frozen_string_literal: true

# Concurrency Demo - File Hasher
#
# Compares concurrency modes:
# - None: Direct execution, UI frozen. Shows what happens without background work.
# - None+update: Synchronous but with forced UI updates so progress is visible.
# - Thread: Background thread with GVL overhead. Enables Pause, UI stays responsive.
# - Ractor: True parallelism (separate GVL). Best throughput. (Ruby 4.x+ only)

require 'teek'
require 'teek/background_none'
require 'digest'
require 'tmpdir'

# Register :none mode for demo
Teek::BackgroundWork.register_background_mode(:none, Teek::BackgroundNone::BackgroundWork)

RACTOR_AVAILABLE = Teek::BackgroundWork::RACTOR_SUPPORTED

class ThreadingDemo
  attr_reader :app

  ALGORITHMS = %w[SHA256 SHA512 SHA384 SHA1 MD5].freeze

  MODES = if RACTOR_AVAILABLE
    ['None', 'None+update', 'Thread', 'Ractor'].freeze
  else
    ['None', 'None+update', 'Thread'].freeze
  end

  def initialize
    @app = Teek::App.new
    @running = false
    @paused = false
    @stop_requested = false
    @background_task = nil

    build_ui
    collect_files

    @app.update
    w = @app.command(:winfo, 'width', '.')
    h = @app.command(:winfo, 'height', '.')
    @app.command(:wm, 'geometry', '.', "#{w}x#{h}+0+0")
    @app.command(:wm, 'resizable', '.', 1, 1)

    close_proc = proc { |*|
      @background_task&.close
      @app.command(:destroy, '.')
    }
    @app.command(:wm, 'protocol', '.', 'WM_DELETE_WINDOW', close_proc)
  end

  def build_ui
    @app.command(:wm, 'deiconify', '.')
    @app.command(:wm, 'title', '.', 'Concurrency Demo - File Hasher')
    @app.command(:wm, 'minsize', '.', 600, 400)

    # Tcl variables for widget bindings
    @app.command(:set, '::chunk_size', 3)
    @app.command(:set, '::algorithm', 'SHA256')
    @app.command(:set, '::mode', 'Thread')
    @app.command(:set, '::allow_pause', 0)
    @app.command(:set, '::progress', 0)

    ractor_note = RACTOR_AVAILABLE ? "Ractor: true parallel." : "(Ractor available on Ruby 4.x+)"
    @app.command('ttk::label', '.desc',
      text: "File hasher demo - compares concurrency modes.\n" \
            "None: UI frozen. None+update: progress visible, pause works. " \
            "Thread: responsive, GVL shared. #{ractor_note}",
      justify: :left)
    @app.command(:pack, '.desc', fill: :x, padx: 10, pady: 10)

    build_controls
    build_statusbar
    build_log
  end

  def build_controls
    @app.command('ttk::frame', '.ctrl')
    @app.command(:pack, '.ctrl', fill: :x, padx: 10, pady: 5)

    @app.command('ttk::button', '.ctrl.start',
      text: 'Start', command: proc { |*| start_hashing })
    @app.command(:pack, '.ctrl.start', side: :left)

    @app.command('ttk::button', '.ctrl.pause',
      text: 'Pause', state: :disabled, command: proc { |*| toggle_pause })
    @app.command(:pack, '.ctrl.pause', side: :left, padx: 5)

    @app.command('ttk::button', '.ctrl.reset',
      text: 'Reset', command: proc { |*| reset })
    @app.command(:pack, '.ctrl.reset', side: :left)

    @app.command('ttk::label', '.ctrl.algo_lbl', text: 'Algorithm:')
    @app.command(:pack, '.ctrl.algo_lbl', side: :left, padx: 10)

    @app.command('ttk::combobox', '.ctrl.algo',
      textvariable: '::algorithm',
      values: Teek.make_list(*ALGORITHMS),
      width: 8,
      state: :readonly)
    @app.command(:pack, '.ctrl.algo', side: :left)

    @app.command('ttk::label', '.ctrl.batch_lbl', text: 'Batch:')
    @app.command(:pack, '.ctrl.batch_lbl', side: :left, padx: 10)

    @app.command('ttk::label', '.ctrl.batch_val', text: '3', width: 3)
    @app.command(:pack, '.ctrl.batch_val', side: :left)

    @app.command('ttk::scale', '.ctrl.scale',
      orient: :horizontal,
      from: 1,
      to: 100,
      length: 100,
      variable: '::chunk_size',
      command: proc { |v, *| @app.command('.ctrl.batch_val', 'configure', text: v.to_f.round.to_s) })
    @app.command(:pack, '.ctrl.scale', side: :left, padx: 5)

    @app.command('ttk::label', '.ctrl.mode_lbl', text: 'Mode:')
    @app.command(:pack, '.ctrl.mode_lbl', side: :left, padx: 10)

    @app.command('ttk::combobox', '.ctrl.mode',
      textvariable: '::mode',
      values: Teek.make_list(*MODES),
      width: 10,
      state: :readonly)
    @app.command(:pack, '.ctrl.mode', side: :left)

    @app.command('ttk::checkbutton', '.ctrl.pause_chk',
      text: 'Allow Pause',
      variable: '::allow_pause')
    @app.command(:pack, '.ctrl.pause_chk', side: :left, padx: 10)
  end

  def build_statusbar
    @app.command('ttk::frame', '.status')
    @app.command(:pack, '.status', side: :bottom, fill: :x, padx: 5, pady: 5)

    # Progress section (left)
    @app.command('ttk::frame', '.status.progress', relief: :sunken, borderwidth: 2)
    @app.command(:pack, '.status.progress', side: :left, fill: :x, expand: 1, padx: 2)

    @app.command('ttk::progressbar', '.status.progress.bar',
      orient: :horizontal,
      length: 200,
      mode: :determinate,
      variable: '::progress',
      maximum: 100)
    @app.command(:pack, '.status.progress.bar', side: :left, padx: 5, pady: 4)

    @app.command('ttk::label', '.status.progress.status', text: 'Ready', width: 20, anchor: :w)
    @app.command(:pack, '.status.progress.status', side: :left, padx: 10)

    @app.command('ttk::label', '.status.progress.file', text: '', width: 28, anchor: :w)
    @app.command(:pack, '.status.progress.file', side: :left, padx: 5)

    # Info section (right)
    @app.command('ttk::frame', '.status.info', relief: :sunken, borderwidth: 2)
    @app.command(:pack, '.status.info', side: :right, padx: 2)

    @app.command('ttk::label', '.status.info.files', text: '', width: 12, anchor: :e)
    @app.command(:pack, '.status.info.files', side: :left, padx: 8, pady: 4)

    @app.command('ttk::separator', '.status.info.sep', orient: :vertical)
    @app.command(:pack, '.status.info.sep', side: :left, fill: :y, pady: 4)

    @app.command('ttk::label', '.status.info.ruby', text: "Ruby #{RUBY_VERSION}", anchor: :e)
    @app.command(:pack, '.status.info.ruby', side: :left, padx: 8, pady: 4)
  end

  def build_log
    @app.command('ttk::labelframe', '.log', text: 'Output')
    @app.command(:pack, '.log', fill: :both, expand: 1, padx: 10, pady: 5)

    @app.command('ttk::frame', '.log.f')
    @app.command(:pack, '.log.f', fill: :both, expand: 1, padx: 5, pady: 5)
    @app.command(:pack, 'propagate', '.log.f', 0)

    @app.command(:text, '.log.f.text', width: 80, height: 15, wrap: :none)
    @app.command(:pack, '.log.f.text', side: :left, fill: :both, expand: 1)

    @app.command('ttk::scrollbar', '.log.f.vsb', orient: :vertical, command: '.log.f.text yview')
    @app.command('.log.f.text', 'configure', yscrollcommand: '.log.f.vsb set')
    @app.command(:pack, '.log.f.vsb', side: :right, fill: :y)
  end

  def collect_files
    base = File.exist?('/app') ? '/app' : Dir.pwd
    @files = Dir.glob("#{base}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
    @files.reject! { |f| f.include?('/.git/') }
    @files.sort!

    max_files = ARGV.find { |a| a.start_with?('--max-files=') }&.split('=')&.last&.to_i
    max_files ||= ENV['DEMO_MAX_FILES']&.to_i
    @files = @files.first(max_files) if max_files && max_files > 0

    @app.command('.status.info.files', 'configure', text: "#{@files.size} files")
  end

  def current_mode
    @app.command(:set, '::mode')
  end

  def get_var(name)
    @app.command(:set, name)
  end

  def set_var(name, value)
    @app.command(:set, name, value)
  end

  def set_combo_enabled(path)
    # ttk state: must clear disabled AND set readonly in one call
    @app.tcl_eval("#{path} state {!disabled readonly}")
  end

  def start_hashing
    @running = true
    @paused = false
    @stop_requested = false

    @app.command('.ctrl.start', 'state', 'disabled')
    @app.command('.ctrl.algo', 'state', 'disabled')
    @app.command('.ctrl.mode', 'state', 'disabled')
    @app.command('.log.f.text', 'delete', '1.0', 'end')
    set_var('::progress', 0)
    @app.command('.status.progress.status', 'configure', text: 'Hashing...')

    if get_var('::allow_pause').to_i == 1
      @app.command('.ctrl.pause', 'state', '!disabled')
    else
      @app.command('.ctrl.pause', 'state', 'disabled')
    end

    @app.command(:wm, 'resizable', '.', 0, 0) unless current_mode == 'Ractor'

    @metrics = {
      start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      ui_update_count: 0,
      ui_update_total_ms: 0.0,
      total: @files.size,
      files_done: 0,
      mode: current_mode
    }

    mode_sym = case current_mode
      when 'None', 'None+update' then :none
      else current_mode.downcase.to_sym
    end
    start_background_work(mode_sym)
  end

  def toggle_pause
    @paused = !@paused
    @app.command('.ctrl.pause', 'configure', text: @paused ? 'Resume' : 'Pause')
    @app.command('.status.progress.status', 'configure', text: @paused ? 'Paused' : 'Hashing...')
    @app.command(:wm, 'resizable', '.', @paused ? 1 : 0, @paused ? 1 : 0)
    if @paused
      set_combo_enabled('.ctrl.mode')
    else
      @app.command('.ctrl.mode', 'state', 'disabled')
    end

    if @background_task
      @paused ? @background_task.pause : @background_task.resume
    end

    write_metrics("PAUSED") if @paused && @metrics
  end

  def reset
    @stop_requested = true
    @paused = false
    @running = false

    @background_task&.stop
    @background_task = nil

    @app.command('.ctrl.start', 'state', '!disabled')
    @app.command('.ctrl.pause', 'state', 'disabled')
    @app.command('.ctrl.pause', 'configure', text: 'Pause')
    set_combo_enabled('.ctrl.algo')
    set_combo_enabled('.ctrl.mode')
    @app.command(:wm, 'resizable', '.', 1, 1)
    @app.command('.log.f.text', 'delete', '1.0', 'end')
    set_var('::progress', 0)
    @app.command('.status.progress.status', 'configure', text: 'Ready')
    @app.command('.status.progress.file', 'configure', text: '')

    set_var('::mode', 'Thread')
    set_var('::algorithm', 'SHA256')
    set_var('::chunk_size', 3)
    @app.command('.ctrl.batch_val', 'configure', text: '3')
    set_var('::allow_pause', 0)
  end

  def write_metrics(status = "DONE")
    return unless @metrics
    m = @metrics
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - m[:start_time]
    dir = File.writable?(__dir__) ? __dir__ : Dir.tmpdir
    File.open(File.join(dir, 'threading_demo_metrics.log'), 'a') do |f|
      f.puts "=" * 60
      f.puts "Status: #{status} at #{Time.now}"
      f.puts "Mode: #{m[:mode]}"
      f.puts "Algorithm: #{get_var('::algorithm')}"
      f.puts "Files processed: #{m[:files_done]}/#{m[:total]}"
      chunk = [get_var('::chunk_size').to_f.round, 1].max
      f.puts "Batch size: #{chunk}"
      f.puts "-" * 40
      f.puts "Elapsed: #{elapsed.round(3)}s"
      f.puts "UI updates: #{m[:ui_update_count]}"
      f.puts "UI update total: #{m[:ui_update_total_ms].round(1)}ms" if m[:ui_update_total_ms]
      f.puts "UI update avg: #{(m[:ui_update_total_ms] / m[:ui_update_count]).round(2)}ms" if m[:ui_update_count] > 0 && m[:ui_update_total_ms]
      f.puts "Files/sec: #{(m[:files_done] / elapsed).round(1)}" if elapsed > 0
      f.puts
    end
  end

  def finish_hashing
    write_metrics("DONE") unless @stop_requested
    return if @stop_requested

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @metrics[:start_time]
    files_per_sec = (@metrics[:files_done] / elapsed).round(1)
    @app.command('.status.progress.status', 'configure',
      text: "Done #{elapsed.round(2)}s (#{files_per_sec}/s)")
    @app.command('.status.progress.file', 'configure', text: '')
    @app.command('.ctrl.start', 'state', '!disabled')
    @app.command('.ctrl.pause', 'state', 'disabled')
    set_combo_enabled('.ctrl.algo')
    set_combo_enabled('.ctrl.mode')
    @app.command(:wm, 'resizable', '.', 1, 1)
    @running = false
  end

  # ─────────────────────────────────────────────────────────────
  # All modes use unified Teek::BackgroundWork API
  # ─────────────────────────────────────────────────────────────

  def start_background_work(mode)
    ui_mode = current_mode

    files = @files.dup
    algo_name = get_var('::algorithm')
    chunk_size = [get_var('::chunk_size').to_f.round, 1].max
    base_dir = Dir.pwd
    allow_pause = get_var('::allow_pause').to_i == 1

    work_data = {
      files: files,
      algo_name: algo_name,
      chunk_size: chunk_size,
      base_dir: base_dir,
      allow_pause: allow_pause
    }

    if mode == :ractor
      work_data = Ractor.make_shareable({
        files: Ractor.make_shareable(files.freeze),
        algo_name: algo_name.freeze,
        chunk_size: chunk_size,
        base_dir: base_dir.freeze,
        allow_pause: allow_pause
      })
    end

    # Each progress value has unique log text — don't drop any
    Teek::BackgroundWork.drop_intermediate = false

    @background_task = Teek::BackgroundWork.new(@app, work_data, mode: mode) do |task, data|
      algo_class = Digest.const_get(data[:algo_name])
      total = data[:files].size
      pending = []

      data[:files].each_with_index do |path, index|
        if data[:allow_pause] && pending.empty?
          task.check_pause
        end

        begin
          hash = algo_class.file(path).hexdigest
          short_path = path.sub(%r{^/app/}, '').sub(data[:base_dir] + '/', '')
          pending << "#{short_path}: #{hash}\n"
        rescue StandardError => e
          short_path = path.sub(%r{^/app/}, '').sub(data[:base_dir] + '/', '')
          pending << "#{short_path}: ERROR - #{e.message}\n"
        end

        is_last = index == total - 1
        if pending.size >= data[:chunk_size] || is_last
          task.yield({
            index: index,
            total: total,
            updates: pending.join
          })
          pending = []
        end
      end
    end

    @background_task.on_progress do |msg|
      ui_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @app.command('.log.f.text', 'insert', 'end', msg[:updates])
      @app.command('.log.f.text', 'see', 'end')
      pct = ((msg[:index] + 1).to_f / msg[:total] * 100).round
      set_var('::progress', pct)
      @app.command('.status.progress.status', 'configure',
        text: "Hashing... #{msg[:index] + 1}/#{msg[:total]}")

      @metrics[:ui_update_count] += 1
      @metrics[:ui_update_total_ms] += (Process.clock_gettime(Process::CLOCK_MONOTONIC) - ui_start) * 1000
      @metrics[:files_done] = msg[:index] + 1

      @app.update if ui_mode == 'None+update'
    end.on_done do
      @background_task = nil
      finish_hashing
    end
  end

  def run
    @app.mainloop
  end
end

demo = ThreadingDemo.new

# Automated demo support (testing and recording)
require_relative '../lib/teek/demo_support'
TeekDemo.app = demo.app

if TeekDemo.testing?
  TeekDemo.after_idle {
    # Set batch high and max-files low for fast test
    demo.app.command(:set, '::chunk_size', 100)

    # Click Start — need Allow Pause checked first
    demo.app.command(:set, '::allow_pause', 1)
    demo.app.command('.ctrl.start', 'invoke')

    # Wait for completion, then finish
    check_done = proc do
      if demo.instance_variable_get(:@running)
        demo.app.after(200, &check_done)
      else
        demo.app.after(200) { TeekDemo.finish }
      end
    end
    demo.app.after(500, &check_done)
  }
end

demo.run
