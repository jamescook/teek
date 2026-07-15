# frozen_string_literal: true

# The Goldberg demo's canvas/physics engine, ported from sample/goldberg.rb's
# TkGoldberg_Demo onto the teek-ui DSL - see sample/goldberg_ui.rb for the
# widget tree this is wired into.
#
# Canvas item creation (line/polygon/oval/arc/rectangle/text/bitmap) calls
# straight into Handle's own DSL methods. Everything that operates on an
# EXISTING item by tag (move/coords/delete/bbox/scale/itemconfigure/
# itemcget/raise/lower/find/item-click) goes through a small set of
# same-named private helpers below, each a one-line wrapper over
# CanvasItem (Handle#tagged(tag).move/coords/etc) - keeping every draw/move
# method's own body a direct, checkable translation of the original rather
# than a fresh rewrite of a thousand lines of dense coordinate data.
class GoldbergEngine
  MODE_LABELS = {
    MSTART: 'Ready', MGO: 'Running', MPAUSE: 'Paused', MSSTEP: 'Stepped',
    MBSTEP: 'Big stepped', MDONE: 'Done', MDEBUG: 'Debug',
  }.freeze

  #         0,  1,  2,  3,  4,  5,   6,   7,   8,   9,  10
  SPEED = [1, 10, 20, 50, 80, 100, 150, 200, 300, 400, 500].freeze

  # @param session [Teek::UI::Session]
  # @param canvas [Teek::UI::Handle] the realized :board canvas handle
  # @param vars [Hash{Symbol => Teek::UI::Var, Hash}] :status/:pause/
  #   :details/:message/:speed/:cnt reactive vars, plus :step_vars (a
  #   Hash{Integer => Var} keyed by step index, one per moveN method)
  def initialize(session, canvas, vars)
    @session = session
    @cv = canvas
    @status_var = vars[:status]
    @pause_var = vars[:pause]
    @details_var = vars[:details]
    @message_var = vars[:message]
    @speed_var = vars[:speed]
    @cnt_var = vars[:cnt]
    @step_vars = vars[:step_vars]

    # Animation state
    @mode = :MSTART
    @active = [0]
    @cnt = 0
    @step = {}
    @XY = {}
    @timer_running = false

    # Colors
    @C = {}
    @C['fg'] = 'black'
    @C['bg'] = 'cornflowerblue'

    @C['0'] = 'white';         @C['1a'] = 'darkgreen';   @C['1b'] = 'yellow'
    @C['2'] = 'red';           @C['3a'] = 'green';       @C['3b'] = 'darkblue'
    @C['4'] = @C['fg'];        @C['5a'] = 'brown';       @C['5b'] = 'white'
    @C['6'] = 'magenta';       @C['7'] = 'green';        @C['8'] = @C['fg']
    @C['9'] = 'blue4';         @C['10a'] = 'white';      @C['10b'] = 'cyan'
    @C['11a'] = 'yellow';      @C['11b'] = 'mediumblue'; @C['12'] = 'tan2'
    @C['13a'] = 'yellow';      @C['13b'] = 'red';        @C['14'] = 'white'
    @C['15a'] = 'green';       @C['15b'] = 'yellow';     @C['16'] = 'gray65'
    @C['17'] = '#A65353';      @C['18'] = @C['fg'];      @C['19'] = 'gray50'
    @C['20'] = 'cyan';         @C['21'] = 'gray65';      @C['22'] = @C['20']
    @C['23a'] = 'blue';        @C['23b'] = 'red';        @C['23c'] = 'yellow'
    @C['24a'] = 'red';         @C['24b'] = 'white';

    @XY6 = {
      '-1'=>[366, 207], '-2'=>[349, 204], '-3'=>[359, 193], '-4'=>[375, 192],
      '-5'=>[340, 190], '-6'=>[349, 177], '-7'=>[366, 177], '-8'=>[380, 176],
      '-9'=>[332, 172], '-10'=>[342, 161], '-11'=>[357, 164],
      '-12'=>[372, 163], '-13'=>[381, 149], '-14'=>[364, 151],
      '-15'=>[349, 146], '-16'=>[333, 148], '0'=>[357, 219],
      '1'=>[359, 261], '2'=>[359, 291], '3'=>[359, 318], '4'=>[361, 324],
      '5'=>[365, 329], '6'=>[367, 334], '7'=>[367, 340], '8'=>[366, 346],
      '9'=>[364, 350], '10'=>[361, 355], '11'=>[359, 370], '12'=>[359, 391],
      '13,0'=>[360, 456], '13,1'=>[376, 456], '13,2'=>[346, 456],
      '13,3'=>[330, 456], '13,4'=>[353, 444], '13,5'=>[368, 443],
      '13,6'=>[339, 442], '13,7'=>[359, 431], '13,8'=>[380, 437],
      '13,9'=>[345, 428], '13,10'=>[328, 434], '13,11'=>[373, 424],
      '13,12'=>[331, 420], '13,13'=>[360, 417], '13,14'=>[345, 412],
      '13,15'=>[376, 410], '13,16'=>[360, 403]
    }

    reset
    @timer_running = true
    schedule_timer
  end

  # ----------------------------------------------------------------
  # Timer (Teek::App#after, self-rescheduling)
  # ----------------------------------------------------------------

  def schedule_timer
    return unless @timer_running
    delay = SPEED[@speed_var.value]
    @session.after(delay) { timer_tick }
  end

  def timer_tick
    return unless @timer_running
    new_delay = go
    @session.after(new_delay) { timer_tick }
  end

  def stop_timer
    @timer_running = false
  end

  # ----------------------------------------------------------------
  # State management
  # ----------------------------------------------------------------

  def set_mode(m)
    @mode = m
    active_GUI
  end

  def toggle_pause
    if @pause_var.value
      set_mode(:MPAUSE)
    else
      set_mode(:MGO)
    end
  end

  def draw_all
    reset_step
    cdel(:all)
    idx = 0
    loop {
      m = "draw#{idx}"
      break unless respond_to?(m)
      send(m)
      idx += 1
    }
  end

  def active_GUI
    m = @mode
    @pause_var.value = (m == :MPAUSE)
    set_enabled(@session[:start], m != :MGO)
    set_enabled(@session[:pause], m != :MSTART && m != :MDONE)
    set_enabled(@session[:step], m != :MGO && m != :MDONE)
    set_enabled(@session[:bstep], m != :MGO && m != :MDONE)
    set_enabled(@session[:reset], m != :MSTART)

    if @details_var.value
      @session.app.command(:pack, @session[:detail_grid].path, fill: :x)
    else
      @session.app.command(:pack, :forget, @session[:detail_grid].path)
    end

    @status_var.value = MODE_LABELS.fetch(m)
  end

  def set_enabled(handle, enabled)
    enabled ? handle.enable : handle.disable
  end

  def start
    set_mode(:MGO)
  end

  def do_button(what)
    case what
    when 0  # Start
      reset if @mode == :MDONE
      set_mode(:MGO)
    when 1  # Pause
      set_mode(@pause_var.value ? :MPAUSE : :MGO)
    when 2  # Step
      set_mode(:MSSTEP)
    when 3  # Reset
      reset
    when 4  # Big step
      set_mode(:MBSTEP)
    end
  end

  def go(who = nil)
    now = clock_ms
    if who  # Start here for debugging
      @active = [who]
      set_mode(:MGO)
    end
    return if @mode == :MDEBUG
    n = next_step if @mode != :MPAUSE
    set_mode(:MPAUSE) if @mode == :MSSTEP
    set_mode(:MSSTEP) if @mode == :MBSTEP && n
    elapsed = clock_ms - now
    delay = SPEED[@speed_var.value] - elapsed
    delay = 1 if delay <= 0
    delay
  end

  def next_step
    retval = false

    if @mode != :MSTART && @mode != :MDONE
      @cnt += 1
      @cnt_var.value = @cnt
    end

    alive = []
    @active.each { |who|
      who = who.to_i
      n = send("move#{who}")
      if (n & 1).nonzero?          # This guy still alive
        alive << who
      end
      if (n & 2).nonzero?          # Next guy is active
        alive << (who + 1)
        retval = true
      end
      if (n & 4).nonzero?          # End of puzzle flag
        set_mode(:MDONE)
        @active = []
        TeekDemo.finish if defined?(TeekDemo) && TeekDemo.recording?
        return true
      end
    }
    @active = alive
    retval
  end

  def about
    msg = "Teek Version ::\n"
    msg += "Ported to the teek-ui DSL, from a prior Ruby/Tk port by Hidetoshi NAGAI\n\n"
    msg += "Original Version ::\n"
    msg += "Tk Goldberg\nby Keith Vetter, March 2003\n"
    msg += "(Reproduced by kind permission of the author)\n\n"
    msg += "Man will always find a difficult means to perform a simple task"
    msg += "\nRube Goldberg"
    @session.app.message_box(message: msg, title: 'About')
  end

  ################################################################
  #
  # All the drawing and moving routines
  #

  # START HERE! banner
  def draw0
    color = @C['0']
    @cv.text([579, 119], text: 'START HERE!',
             fill: color, anchor: :w,
             tags: 'I0', font: ['Times Roman', 12, :italic, :bold])
    @cv.line([719, 119, 763, 119], tags: 'I0', fill: color,
             width: 5, arrow: :last, arrowshape: [18, 18, 5])
    cbind_item('I0') { start }
  end

  def move0(step = nil)
    step = get_step(0, step)

    if @mode != :MSTART
      move_abs('I0', [-100, -100])
      return 2
    end

    pos = [
      [673, 119], [678, 119], [683, 119], [688, 119],
      [693, 119], [688, 119], [683, 119], [678, 119]
    ]
    step = step % pos.length
    move_abs('I0', pos[step])
    return 1
  end

  # Dropping ball
  def draw1
    color = @C['1a']
    color2 = @C['1b']
    @cv.polygon([ 844, 133, 800, 133, 800, 346, 820, 346,
                  820, 168, 844, 168, 844, 133 ],
                width: 3, fill: color, outline: '')
    @cv.polygon([ 771, 133, 685, 133, 685, 168, 751, 168,
                  751, 346, 771, 346, 771, 133 ],
                width: 3, fill: color, outline: '')
    @cv.oval(box(812, 122, 9),
             tags: 'I1', fill: color2, outline: '')

    cbind_item('I1') { start }
  end

  def move1(step = nil)
    step = get_step(1, step)
    pos = [
      [807, 122], [802, 122], [797, 123], [793, 124], [789, 129], [785, 153],
      [785, 203], [785, 278, :x], [785, 367], [810, 392], [816, 438],
      [821, 503], [824, 585, :y], [838, 587], [848, 593], [857, 601],
      [-100, -100]
    ]
    return 0 if step >= pos.length
    where = pos[step]
    move_abs('I1', where)
    move15a if where[2] == :y
    return 3 if where[2] == :x
    return 1
  end

  # Lighting the match
  def draw2
    color = @C['2']

    # Fulcrum
    @cv.polygon([750, 369, 740, 392, 760, 392],
                fill: @C['fg'], outline: @C['fg'])

    # Strike box
    @cv.rectangle([628, 335, 660, 383],
                  fill: '', outline: @C['fg'])
    (0..2).each { |y|
      yy = 335 + y * 16
      @cv.bitmap([628, yy], bitmap: 'gray25',
                 anchor: :nw, foreground: @C['fg'])
      @cv.bitmap([644, yy], bitmap: 'gray25',
                 anchor: :nw, foreground: @C['fg'])
    }

    # Lever
    @cv.line([702, 366, 798, 366],
             fill: @C['fg'], width: 6, tags: 'I2_0')
    # R strap
    @cv.line([712, 363, 712, 355],
             fill: @C['fg'], width: 3, tags: 'I2_1')
    # L strap
    @cv.line([705, 363, 705, 355],
             fill: @C['fg'], width: 3, tags: 'I2_2')
    # Match stick
    @cv.line([679, 356, 679, 360, 717, 360, 717, 356, 679, 356],
             fill: @C['fg'], width: 3, tags: 'I2_3')
    # Match head
    @cv.polygon([ 671, 352, 677.4, 353.9, 680, 358.5, 677.4, 363.1,
                  671, 365, 664.6, 363.1, 662, 358.5, 664.6, 353.9 ],
                fill: color, outline: color, tags: 'I2_4')
  end

  def move2(step = nil)
    step = get_step(2, step)

    stages = [0, 0, 1, 2, 0, 2, 1, 0, 1, 2, 0, 2, 1]
    xy = []
    xy[0] = [
      686, 333, 692, 323, 682, 316, 674, 309, 671, 295, 668, 307,
      662, 318, 662, 328, 671, 336
    ]
    xy[1] = [
      687, 331, 698, 322, 703, 295, 680, 320, 668, 297, 663, 311,
      661, 327, 671, 335
    ]
    xy[2] = [
      686, 331, 704, 322, 688, 300, 678, 283, 678, 283, 674, 298,
      666, 309, 660, 324, 672, 336
    ]

    if step >= stages.length
      cdel('I2')
      return 0
    end

    if step == 0  # Rotate the match
      beta = 20
      ox, oy = anchor('I2_0', :s)
      i = 0
      until cfind("I2_#{i}").empty?
        rotate_item("I2_#{i}", ox, oy, beta)
        i += 1
      end
      # For the flame
      @cv.polygon([], tags: 'I2', smooth: true, fill: @C['2'])
      return 1
    end
    ccoords('I2', xy[stages[step]])
    return((step == 7) ? 3 : 1)
  end

  # Weight and pulleys
  def draw3
    color = @C['3a']
    color2 = @C['3b']

    xy = [ [602, 296], [577, 174], [518, 174] ]
    xy.each { |x, y|
      @cv.oval(box(x, y, 13),
               fill: color, outline: @C['fg'], width: 3)
      @cv.oval(box(x, y, 2), fill: @C['fg'], outline: @C['fg'])
    }

    # Wall to flame
    @cv.line([750, 309, 670, 309], tags: 'I3_s',
             width: 3, fill: @C['fg'], smooth: true)
    # Flame to pulley 1
    @cv.line([670, 309, 650, 309], tags: 'I3_0',
             width: 3, fill: @C['fg'], smooth: true)
    @cv.line([650, 309, 600, 309], tags: 'I3_1',
             width: 3, fill: @C['fg'], smooth: true)
    # Pulley 1 half way to 2
    @cv.line([589, 296, 589, 235], tags: 'I3_2',
             width: 3, fill: @C['fg'])
    # Pulley 1 other half to 2
    @cv.line([589, 235, 589, 174], width: 3, fill: @C['fg'])
    # Across the top
    @cv.line([577, 161, 518, 161], width: 3, fill: @C['fg'])
    # Down to weight
    @cv.line([505, 174, 505, 205], tags: 'I3_w',
             width: 3, fill: @C['fg'])

    # Draw the weight
    x1, y1, x2, y2 = [515, 207, 495, 207]
    @cv.oval(box(x1, y1, 6),
             tags: 'I3_', fill: color2, outline: color2)
    @cv.oval(box(x2, y2, 6),
             tags: 'I3_', fill: color2, outline: color2)
    @cv.rectangle(x1, y1 - 6, x2, y2 + 6,
                  tags: 'I3_', fill: color2, outline: color2)
    @cv.polygon(round_rect([492, 220, 518, 263], 15),
                smooth: true, tags: 'I3_', fill: color2, outline: color2)
    @cv.line([500, 217, 511, 217],
             tags: 'I3_', fill: color2, width: 10)

    # Bottom weight target
    @cv.line([502, 393, 522, 393, 522, 465],
             tags: 'I3__', fill: @C['fg'], joinstyle: :miter, width: 10)
  end

  def move3(step = nil)
    step = get_step(3, step)

    pos = [ [505, 247], [505, 297], [505, 386.5], [505, 386.5] ]
    rope = []
    rope[0] = [750, 309, 729, 301, 711, 324, 690, 300]
    rope[1] = [750, 309, 737, 292, 736, 335, 717, 315, 712, 320]
    rope[2] = [750, 309, 737, 309, 740, 343, 736, 351, 725, 340]
    rope[3] = [750, 309, 738, 321, 746, 345, 742, 356]

    return 0 if step >= pos.length

    cdel("I3_#{step}")
    move_abs('I3_', pos[step])
    ccoords('I3_s', rope[step])
    ccoords('I3_w', [505, 174].concat(pos[step]))
    if step == 2
      cmove('I3__', 0, 30)
      return 2
    end
    return 1
  end

  # Cage and door
  def draw4
    color = @C['4']
    x0, y0, x1, y1 = [527, 356, 611, 464]

    y0.step(y1, 12) { |y| @cv.line([x0, y, x1, y], fill: color, width: 1) }
    x0.step(x1, 12) { |x| @cv.line([x, y0, x, y1], fill: color, width: 1) }

    # Swing gate
    @cv.line([518, 464, 518, 428], tags: 'I4', fill: color, width: 1)
  end

  def move4(step = nil)
    step = get_step(4, step)
    angles = [-10, -20, -30, -30]
    return 0 if step >= angles.length
    rotate_item('I4', 518, 464, angles[step])
    craise('I4')
    return((step == 3) ? 3 : 1)
  end

  # Mouse
  def draw5
    color  = @C['5a']
    color2 = @C['5b']

    xy = [377, 248, 410, 248, 410, 465, 518, 465]
    xy.concat [518, 428, 451, 428, 451, 212, 377, 212]
    @cv.polygon(xy, fill: color2, outline: @C['fg'], width: 3)

    xy = [
      534.5, 445.5, 541, 440, 552, 436, 560, 436, 569, 440, 574, 446,
      575, 452, 574, 454, 566, 456, 554, 456, 545, 456, 537, 454, 530, 452
    ]
    @cv.polygon(xy, tags: ['I5', 'I5_0'], fill: color)

    @cv.line([573, 452, 592, 458, 601, 460, 613, 456],
             tags: ['I5', 'I5_1'], fill: color, smooth: true, width: 3)

    xy = [540, 444, 541, 445, 541, 447, 540, 448, 538, 447, 538, 445]
    @cv.polygon(xy, tags: ['I5', 'I5_2'], fill: @C['bg'],
                outline: '', smooth: true)

    @cv.line([538, 454, 535, 461],
             tags: ['I5', 'I5_3'], fill: color, width: 2)
    @cv.line([566, 455, 569, 462],
             tags: ['I5', 'I5_4'], fill: color, width: 2)
    @cv.line([544, 455, 545, 460],
             tags: ['I5', 'I5_5'], fill: color, width: 2)
    @cv.line([560, 455, 558, 460],
             tags: ['I5', 'I5_6'], fill: color, width: 2)
  end

  def move5(step = nil)
    step = get_step(5, step)

    pos = [
      [553, 452], [533, 452], [513, 452], [493, 452], [473, 452],
      [463, 442, 30], [445.5, 441.5, 30], [425.5, 434.5, 30], [422, 414],
      [422, 394], [422, 374], [422, 354], [422, 334], [422, 314], [422, 294],
      [422, 274, -30], [422, 260.5, -30, :x], [422.5, 248.5, -28], [425, 237]
    ]

    return 0 if step >= pos.length

    x, y, beta, nxt = pos[step]
    move_abs('I5', [x, y])
    if beta
      ox, oy = centroid('I5_0')
      (0..6).each { |id| rotate_item("I5_#{id}", ox, oy, beta) }
    end
    return 3 if nxt == :x
    return 1
  end

  # Dropping gumballs
  def draw6
    color = @C['6']
    xy = [324, 130, 391, 204]
    xy = round_rect(xy, 10)
    @cv.polygon(xy, smooth: true,
                outline: @C['fg'], width: 3, fill: color)
    @cv.rectangle([339, 204, 376, 253], outline: @C['fg'], width: 3,
                  fill: color, tags: 'I6c')
    xy = box(346, 339, 28)
    @cv.oval(xy, fill: color, outline: '')
    @cv.arc(xy, outline: @C['fg'], width: 2, style: :arc,
            start: 80, extent: 205)
    @cv.arc(xy, outline: @C['fg'], width: 2, style: :arc,
            start: -41, extent: 85)

    xy = box(346, 339, 15)
    @cv.oval(xy, outline: @C['fg'], fill: @C['fg'], tags: 'I6m')
    xy = [352, 312, 352, 254, 368, 254, 368, 322]
    @cv.polygon(xy, fill: color, outline: '')
    @cv.line(xy, fill: @C['fg'], width: 2)

    @cv.rectangle([353, 240, 367, 300], fill: color, outline: '')
    @cv.rectangle([341, 190, 375, 210], fill: color, outline: '')

    xy = [
      368, 356, 368, 403, 389, 403, 389, 464, 320, 464, 320, 403,
      352, 403, 352, 366
    ]
    @cv.polygon(xy, fill: color, outline: '', width: 2)
    @cv.line(xy, fill: @C['fg'], width: 2)
    @cv.oval(box(275, 342, 7), outline: @C['fg'], fill: @C['fg'])
    @cv.line([276, 334, 342, 325], fill: @C['fg'], width: 3)
    @cv.line([276, 349, 342, 353], fill: @C['fg'], width: 3)

    @cv.line([337, 212, 337, 247], fill: @C['fg'], width: 3, tags: 'I6_')
    @cv.line([392, 212, 392, 247], fill: @C['fg'], width: 3, tags: 'I6_')
    @cv.line([337, 230, 392, 230], fill: @C['fg'], width: 7, tags: 'I6_')

    colors = %w(red cyan orange green blue darkblue) * 3
    (0..16).each { |i|
      loc = -i
      color = colors[i]
      x, y = @XY6["#{loc}"]
      @cv.oval(box(x, y, 5), fill: color, outline: color, tags: "I6_b#{i}")
    }
    draw6a(12)
  end

  def draw6a(beta)
    cdel('I6_0')
    ox, oy = [346, 339]
    (0..3).each { |i|
      b = beta + i * 45
      x, y = rotate_c(28, 0, 0, 0, b)
      xy = [ox + x, oy + y, ox - x, oy - y]
      @cv.line(xy, tags: 'I6_0', fill: @C['fg'], width: 2)
    }
  end

  def move6(step = nil)
    step = get_step(6, step)

    return 0 if step > 62

    if step < 2
      cmove('I6_', -7, 0)
      if step == 1
        @cv.rectangle([348, 226, 365, 240], fill: citemcget('I6c', :fill),
                      outline: '')
      end
      return 1
    end

    s = step - 1
    (0..(((s - 1) / 3).to_i)).each { |i|
      tag = "I6_b#{i}"
      break if cfind(tag).empty?
      loc = s - 3 * i

      if @XY6["#{loc},#{i}"]
        move_abs(tag, @XY6["#{loc},#{i}"])
      elsif @XY6["#{loc}"]
        move_abs(tag, @XY6["#{loc}"])
      end
    }
    if s % 3 == 1
      first = (s + 2) / 3
      i = first
      loop {
        tag = "I6_b#{i}"
        break if cfind(tag).empty?
        loc = first - i
        move_abs(tag, @XY6["#{loc}"])
        i += 1
      }
    end
    draw6a(12 + s * 15) if s >= 3
    return((s == 3) ? 3 : 1)
  end

  # On/off switch
  def draw7
    color = @C['7']
    @cv.rectangle([198, 306, 277, 374], outline: @C['fg'], width: 2,
                  fill: color, tags: 'I7z')
    clower('I7z')
    @cv.line([275, 343, 230, 349], tags: 'I7', fill: @C['fg'], arrow: :last,
             arrowshape: [23, 23, 8], width: 6)
    x, y = [225, 324]
    @cv.oval(box(x, y, 3), fill: @C['fg'], outline: @C['fg'])
    font = ['Times Roman', 8]
    @cv.text([218, 323], text: 'on', anchor: :e,
             fill: @C['fg'], font: font)
    x, y = [225, 350]
    @cv.oval(box(x, y, 3), fill: @C['fg'], outline: @C['fg'])
    @cv.text([218, 349], text: 'off', anchor: :e,
             fill: @C['fg'], font: font)
  end

  def move7(step = nil)
    step = get_step(7, step)
    numsteps = 30
    return 0 if step > numsteps
    beta = 30.0 / numsteps
    rotate_item('I7', 275, 343, beta)
    return((step == numsteps) ? 3 : 1)
  end

  # Electricity to the fan
  def draw8
    sine([271, 248, 271, 306], 5, 8, tags: 'I8_s', fill: @C['8'], width: 3)
  end

  def move8(step = nil)
    step = get_step(8, step)
    return 0 if step > 3
    if step == 0
      sparkle(anchor('I8_s', :s), 'I8')
      return 1
    elsif step == 1
      move_abs('I8', anchor('I8_s', :c))
    elsif step == 2
      move_abs('I8', anchor('I8_s', :n))
    else
      cdel('I8')
    end
    return((step == 2) ? 3 : 1)
  end

  # Fan
  def draw9
    color = @C['9']
    @cv.oval([266, 194, 310, 220], outline: color, fill: color)
    @cv.oval([280, 209, 296, 248], outline: color, fill: color)
    xy = [
      288, 249, 252, 249, 260, 240, 280, 234,
      296, 234, 316, 240, 324, 249, 288, 249
    ]
    @cv.polygon(xy, fill: color, smooth: true)
    @cv.polygon([248, 205, 265, 214, 264, 205, 265, 196], fill: color)

    @cv.oval([255, 206, 265, 234], fill: '', outline: @C['fg'],
             width: 3, tags: 'I9_0')
    @cv.oval([255, 176, 265, 204], fill: '', outline: @C['fg'],
             width: 3, tags: 'I9_0')
    @cv.oval([255, 206, 265, 220], fill: '', outline: @C['fg'],
             width: 1, tags: 'I9_1')
    @cv.oval([255, 190, 265, 204], fill: '', outline: @C['fg'],
             width: 1, tags: 'I9_1')
  end

  def move9(step = nil)
    step = get_step(9, step)
    if (step & 1).nonzero?
      citemconfig('I9_0', width: 4)
      citemconfig('I9_1', width: 1)
      clower('I9_1', 'I9_0')
    else
      citemconfig('I9_0', width: 1)
      citemconfig('I9_1', width: 4)
      clower('I9_0', 'I9_1')
    end
    return 3 if step == 0
    return 1
  end

  # Boat
  def draw10
    color  = @C['10a']
    color2 = @C['10b']
    @cv.polygon([191, 230, 233, 230, 233, 178, 191, 178],
                fill: color, width: 3, outline: @C['fg'], tags: 'I10')
    xy = box(209, 204, 31)
    @cv.arc(xy, outline: '', fill: color, style: :pie,
            start: 120, extent: 120, tags: 'I10')
    @cv.arc(xy, outline: @C['fg'], width: 3, style: :arc,
            start: 120, extent: 120, tags: 'I10')
    xy = box(249, 204, 31)
    @cv.arc(xy, outline: '', fill: @C['bg'], width: 3,
            style: :pie, start: 120, extent: 120, tags: 'I10')
    @cv.arc(xy, outline: @C['fg'], width: 3, style: :arc,
            start: 120, extent: 120, tags: 'I10')

    @cv.line([200, 171, 200, 249], fill: @C['fg'], width: 3, tags: 'I10')
    @cv.line([159, 234, 182, 234], fill: @C['fg'], width: 3, tags: 'I10')
    @cv.line([180, 234, 180, 251, 220, 251], fill: @C['fg'], width: 6, tags: 'I10')

    sine([92, 255, 221, 255], 2, 25, fill: color2, width: 1, tags: 'I10w')

    xy = ccoords('I10w')[4..-5]
    xy.concat([222, 266, 222, 277, 99, 277])
    @cv.polygon(xy, fill: color2, outline: color2)
    @cv.line([222, 266, 222, 277, 97, 277, 97, 266], fill: @C['fg'], width: 3)

    @cv.arc(box(239, 262, 17), outline: @C['fg'], width: 3, style: :arc,
            start: 95, extent: 103)
    @cv.arc(box(76, 266, 21), outline: @C['fg'], width: 3, style: :arc,
            extent: 190)
  end

  def move10(step = nil)
    step = get_step(10, step)

    pos = [
      [195, 212], [193, 212], [190, 212], [186, 212], [181, 212], [176, 212],
      [171, 212], [166, 212], [161, 212], [156, 212], [151, 212], [147, 212],
      [142, 212], [137, 212], [132, 212, :x], [127, 212], [121, 212],
      [116, 212], [111, 212]
    ]
    return 0 if step >= pos.length
    where = pos[step]
    move_abs('I10', where)
    return 3 if where[2] == :x
    return 1
  end

  # 2nd ball drop
  def draw11
    color  = @C['11a']
    color2 = @C['11b']
    @cv.rectangle([23, 264, 55, 591], fill: color, outline: '')
    @cv.oval(box(71, 460, 48), fill: color, outline: '')

    @cv.line([55, 264, 55, 458], fill: @C['fg'], width: 3)
    @cv.line([55, 504, 55, 591], fill: @C['fg'], width: 3)
    @cv.arc(box(71, 460, 48), outline: @C['fg'], width: 3, style: :arc,
            start: 110, extent: -290, tags: 'I11i')
    @cv.oval(box(71, 460, 16), outline: @C['fg'], fill: '',
             width: 3, tags: 'I11i')
    @cv.oval(box(71, 460, 16), outline: @C['fg'], fill: @C['bg'], width: 3)

    @cv.line([23, 264, 23, 591], fill: @C['fg'], width: 3)
    @cv.arc(box(1, 266, 23), outline: @C['fg'], width: 3,
            style: :arc, extent: 90)

    @cv.oval(box(75, 235, 9), fill: color2, outline: '',
             width: 3, tags: 'I11')
  end

  def move11(step = nil)
    step = get_step(11, step)

    pos = [
      [75, 235], [70, 235], [65, 237], [56, 240], [46, 247], [38, 266],
      [38, 296], [38, 333], [38, 399], [38, 475], [74, 496], [105, 472],
      [100, 437], [65, 423], [-100, -100], [38, 505], [38, 527, :x], [38, 591]
    ]
    return 0 if step >= pos.length
    where = pos[step]
    move_abs('I11', where)
    return 3 if where[2] == :x
    return 1
  end

  # Hand
  def draw12
    xy = [
      20, 637, 20, 617, 20, 610, 20, 590, 40, 590, 40, 590,
      60, 590, 60, 610, 60, 610
    ]
    xy.concat([60, 610, 65, 620, 60, 631])
    xy.concat([60, 631, 60, 637, 60, 662, 60, 669, 52, 669,
               56, 669, 50, 669, 50, 662, 50, 637])

    y0 = 637; y1 = 645
    50.step(21, -10) { |x|
      x1 = x - 5; x2 = x - 10
      xy << x << y0 << x1 << y1 << x2 << y0
    }
    @cv.polygon(xy, fill: @C['12'], outline: @C['fg'],
                smooth: true, tags: 'I12', width: 3)
  end

  def move12(step = nil)
    step = get_step(12, step)
    pos = [[42.5, 641, :x]]
    return 0 if step >= pos.length
    where = pos[step]
    move_abs('I12', where)
    return 3 if where[2] == :x
    return 1
  end

  # Fax
  def draw13
    color = @C['13a']
    xy = [86, 663, 149, 663, 149, 704, 50, 704, 50, 681, 64, 681, 86, 671]
    xy2 = [
      784, 663, 721, 663, 721, 704, 820, 704, 820, 681, 806, 681, 784, 671
    ]
    radii = [2, 9, 9, 8, 5, 5, 2]

    round_poly(xy, radii, width: 3, outline: @C['fg'], fill: color)
    round_poly(xy2, radii, width: 3, outline: @C['fg'], fill: color)

    x, y = [56, 677]
    @cv.rectangle(box(x, y, 4), fill: '', outline: @C['fg'],
                  width: 3, tags: 'I13')
    x, y = [809, 677]
    @cv.rectangle(box(x, y, 4), fill: '', outline: @C['fg'],
                  width: 3, tags: 'I13R')

    @cv.text([112, 687], text: 'FAX', fill: @C['fg'],
             font: ['Times Roman', 12, :bold])
    @cv.text([762, 687], text: 'FAX', fill: @C['fg'],
             font: ['Times Roman', 12, :bold])

    @cv.line([138, 663, 148, 636, 178, 636],
             smooth: true, fill: @C['fg'], width: 3)
    @cv.line([732, 663, 722, 636, 692, 636],
             smooth: true, fill: @C['fg'], width: 3)

    sine([149, 688, 720, 688], 5, 15,
         tags: 'I13_s', fill: @C['fg'], width: 3)
  end

  def move13(step = nil)
    step = get_step(13, step)
    numsteps = 7

    if step == numsteps + 2
      move_abs('I13_star', [-100, -100])
      citemconfig('I13R', fill: @C['13b'], width: 2)
      return 2
    end
    if step == 0
      cdel('I13')
      sparkle([-100, -100], 'I13_star')
      return 1
    end
    x0, y0 = anchor('I13_s', :w)
    x1, y1 = anchor('I13_s', :e)
    x = x0 + (x1 - x0) * (step - 1) / numsteps.to_f
    move_abs('I13_star', [x, y0])
    return 1
  end

  # Paper in fax
  def draw14
    color = @C['14']
    @cv.line([102, 661, 113, 632, 130, 618], smooth: true, fill: color,
             width: 3, tags: 'I14L_0')
    @cv.line([148, 629, 125, 640, 124, 662], smooth: true, fill: color,
             width: 3, tags: 'I14L_1')
    draw14a('L')

    @cv.line([768.0, 662.5, 767.991316225, 662.433786215, 767.926187912, 662.396880171],
             smooth: true, fill: color, width: 3, tags: 'I14R_0')
    clower('I14R_0')
    @cv.line([745.947897349, 662.428358855, 745.997829056, 662.452239237, 746.0, 662.5],
             smooth: true, fill: color, width: 3, tags: 'I14R_1')
    clower('I14R_1')
  end

  def draw14a(side)
    color = @C['14']
    xy = ccoords("I14#{side}_0")
    xy2 = ccoords("I14#{side}_1")
    x0, y0, x1, y1, x2, y2 = xy
    x3, y3, x4, y4, x5, y5 = xy2

    zz = [
      x0, y0, x0, y0, xy, x2, y2, x2, y2,
      x3, y3, x3, y3, xy2, x5, y5, x5, y5
    ].flatten
    cdel("I14#{side}")
    @cv.polygon(zz, tags: "I14#{side}", smooth: true,
                fill: color, outline: color, width: 3)
    clower("I14#{side}")
  end

  def move14(step = nil)
    step = get_step(14, step)

    sc = 0.9 - 0.05 * step
    if sc < 0.3
      cdel('I14L')
      return 0
    end

    ox, oy = ccoords('I14L_0')
    cscale('I14L_0', ox, oy, sc, sc)
    ox, oy = ccoords('I14L_1')[-2..-1]
    cscale('I14L_1', ox, oy, sc, sc)
    draw14a('L')

    sc = 0.35 + 0.05 * step
    sc = 1 / sc

    ox, oy = ccoords('I14R_0')
    cscale('I14R_0', ox, oy, sc, sc)
    ox, oy = ccoords('I14R_1')[-2..-1]
    cscale('I14R_1', ox, oy, sc, sc)
    draw14a('R')

    return((step == 10) ? 3 : 1)
  end

  # Light beam
  def draw15
    color = @C['15a']
    @cv.line([824, 599, 824, 585, 820, 585, 829, 585],
             fill: @C['fg'], width: 3, tags: 'I15a')
    @cv.rectangle([789, 599, 836, 643], fill: color, outline: @C['fg'], width: 3)
    @cv.rectangle([778, 610, 788, 632], fill: color, outline: @C['fg'], width: 3)
    @cv.rectangle([766, 617, 776, 625], fill: color, outline: @C['fg'], width: 3)

    @cv.rectangle([633, 600, 681, 640], fill: color, outline: @C['fg'], width: 3)
    @cv.rectangle([635, 567, 657, 599], fill: color, outline: @C['fg'], width: 2)
    @cv.rectangle([765, 557, 784, 583], fill: color, outline: @C['fg'], width: 2)

    sine([658, 580, 765, 580], 3, 15,
         tags: 'I15_s', fill: @C['fg'], width: 3)
  end

  def move15a
    color = @C['15b']
    cscale('I15a', 824, 599, 1, 0.3)
    @cv.line([765, 621, 681, 621], dash: '-', width: 3, fill: color, tags: 'I15')
  end

  def move15(step = nil)
    step = get_step(15, step)
    numsteps = 6

    if step == numsteps + 2
      move_abs('I15_star', [-100, -100])
      return 2
    end
    if step == 0
      sparkle([-100, -100], 'I15_star')
      ccoords('I15', [765, 621, 745, 621])
      return 1
    end
    x0, y0 = anchor('I15_s', :w)
    x1, y1 = anchor('I15_s', :e)
    x = x0 + (x1 - x0) * (step - 1) / numsteps.to_f
    move_abs('I15_star', [x, y0])
    return 1
  end

  # Bell
  def draw16
    color = @C['16']
    @cv.rectangle([722, 485, 791, 556], fill: '', outline: @C['fg'], width: 3)
    @cv.oval(box(752, 515, 25), fill: color, outline: 'black',
             tags: 'I16b', width: 2)
    @cv.oval(box(752, 515, 5), fill: 'black', outline: 'black', tags: 'I16b')

    @cv.line([784, 523, 764, 549], width: 3, tags: 'I16c', fill: @C['fg'])
    @cv.oval(box(784, 523, 4), fill: @C['fg'], outline: @C['fg'], tags: 'I16d')
  end

  def move16(step = nil)
    step = get_step(16, step)
    ox, oy = [760, 553]
    if (step & 1).nonzero?
      beta = 12
      cmove('I16b', 3, 0)
    else
      beta = -12
      cmove('I16b', -3, 0)
    end
    rotate_item('I16c', ox, oy, beta)
    rotate_item('I16d', ox, oy, beta)
    return((step == 1) ? 3 : 1)
  end

  # Cat
  def draw17
    color = @C['17']

    @cv.line([584, 556, 722, 556], fill: @C['fg'], width: 3)
    @cv.line([584, 485, 722, 485], fill: @C['fg'], width: 3)

    @cv.arc([664, 523, 717, 549], outline: @C['fg'], fill: color, width: 3,
            style: :chord, start: 128, extent: 260, tags: 'I17')
    @cv.oval([709, 554, 690, 543], outline: @C['fg'], fill: color,
             width: 3, tags: 'I17')
    @cv.oval([657, 544, 676, 555], outline: @C['fg'], fill: color,
             width: 3, tags: 'I17')

    @cv.arc(box(660, 535, 15), outline: @C['fg'], width: 3, style: :arc,
            start: 150, extent: 240, tags: 'I17_')
    @cv.arc(box(660, 535, 15), outline: '', fill: color, width: 1,
            style: :chord, start: 150, extent: 240, tags: 'I17_')
    @cv.line([674, 529, 670, 513, 662, 521, 658, 521, 650, 513, 647, 529],
             fill: @C['fg'], width: 3, tags: 'I17_')
    @cv.polygon([674, 529, 670, 513, 662, 521, 658, 521, 650, 513, 647, 529],
                fill: color, outline: '', width: 1, tags: ['I17_', 'I17_c'])

    # Whiskers left
    @cv.line([652, 542, 628, 539], fill: @C['fg'], width: 3, tags: 'I17_')
    @cv.line([652, 543, 632, 545], fill: @C['fg'], width: 3, tags: 'I17_')
    @cv.line([652, 546, 632, 552], fill: @C['fg'], width: 3, tags: 'I17_')
    # Whiskers right
    @cv.line([668, 543, 687, 538], fill: @C['fg'], width: 3,
             tags: ['I17_', 'I17_w'])
    @cv.line([668, 544, 688, 546], fill: @C['fg'], width: 3,
             tags: ['I17_', 'I17_w'])
    @cv.line([668, 547, 688, 553], fill: @C['fg'], width: 3,
             tags: ['I17_', 'I17_w'])

    # Eyes
    @cv.line([649, 530, 654, 538, 659, 530], fill: @C['fg'], width: 2,
             smooth: true, tags: 'I17')
    @cv.line([671, 530, 666, 538, 661, 530], fill: @C['fg'], width: 2,
             smooth: true, tags: 'I17')
    # Mouth
    @cv.line([655, 543, 660, 551, 665, 543], fill: @C['fg'], width: 2,
             smooth: true, tags: 'I17')
  end

  def move17(step = nil)
    step = get_step(17, step)

    if step == 0
      cdel('I17')
      # Surprised mouth
      @cv.line([655, 543, 660, 535, 665, 543], fill: @C['fg'], width: 3,
               smooth: true, tags: 'I17_')
      # Surprised eyes
      @cv.oval(box(654, 530, 4), outline: @C['fg'], width: 3, fill: '',
               tags: 'I17_')
      @cv.oval(box(666, 530, 4), outline: @C['fg'], width: 3, fill: '',
               tags: 'I17_')

      cmove('I17_', 0, -20)
      @cv.line([652, 528, 652, 554], fill: @C['fg'], width: 3, tags: 'I17_')
      @cv.line([670, 528, 670, 554], fill: @C['fg'], width: 3, tags: 'I17_')

      xy = [
        675, 506, 694, 489, 715, 513, 715, 513, 715, 513, 716, 525,
        716, 525, 716, 525, 706, 530, 695, 530, 679, 535, 668, 527,
        668, 527, 668, 527, 675, 522, 676, 517, 677, 512
      ]
      @cv.polygon(xy, fill: citemcget('I17_c', :fill),
                  outline: @C['fg'], width: 3, smooth: true, tags: 'I17_')
      @cv.line([716, 514, 716, 554], fill: @C['fg'], width: 3, tags: 'I17_')
      @cv.line([694, 532, 694, 554], fill: @C['fg'], width: 3, tags: 'I17_')
      @cv.line([715, 514, 718, 506, 719, 495, 716, 488], fill: @C['fg'],
               width: 3, smooth: true, tags: 'I17_')

      craise('I17w')
      cmove('I17_', -5, 0)
      return 2
    end
    return 0
  end

  # Sling shot
  def draw18
    @cv.line([721, 506, 627, 506], width: 4, fill: @C['fg'], tags: 'I18')
    @cv.oval([607, 500, 628, 513], fill: @C['18'], outline: '', tags: 'I18a')
    @cv.line([526, 513, 606, 507, 494, 502], fill: @C['fg'], width: 4, tags: 'I18b')
    @cv.line([485, 490, 510, 540, 510, 575, 510, 540, 535, 491],
             fill: @C['fg'], width: 6)
  end

  def move18(step = nil)
    step = get_step(18, step)

    pos = [
      [587, 506], [537, 506], [466, 506], [376, 506], [266, 506, :x],
      [136, 506], [16, 506], [-100, -100]
    ]
    b = []
    b[0] = [490, 502, 719, 507, 524, 512]
    b[1] = [
      491, 503, 524, 557, 563, 505, 559, 496, 546, 506, 551, 525,
      553, 536, 538, 534, 532, 519, 529, 499
    ]
    b[2] = [
      491, 503, 508, 563, 542, 533, 551, 526, 561, 539, 549, 550, 530, 500
    ]
    b[3] = [
      491, 503, 508, 563, 530, 554, 541, 562, 525, 568, 519, 544, 530, 501
    ]

    return 0 if step >= pos.length

    if step == 0
      cdel('I18')
      citemconfig('I18b', smooth: true)
    end
    ccoords('I18b', b[step]) if b[step]

    where = pos[step]
    move_abs('I18a', where)
    return 3 if where[2] == :x
    return 1
  end

  # Water pipe
  def draw19
    color = @C['19']
    xx = [[249, 181], [155, 118], [86, 55], [22, 0]]
    xx.each { |x1, x2|
      @cv.rectangle(x1, 453, x2, 467, fill: color, outline: '', tags: 'I19')
      @cv.line([x1, 453, x2, 453], fill: @C['fg'], width: 1)
      @cv.line([x1, 467, x2, 467], fill: @C['fg'], width: 1)
    }
    craise('I11i')

    @cv.oval(box(168, 460, 16), fill: color, outline: '')
    @cv.arc(box(168, 460, 16), outline: @C['fg'], width: 1, style: :arc,
            start: 21, extent: 136)
    @cv.arc(box(168, 460, 16), outline: @C['fg'], width: 1, style: :arc,
            start: -21, extent: -130)

    @cv.rectangle([249, 447, 255, 473], fill: color, outline: @C['fg'], width: 1)

    # Bends
    xy = box(257, 433, 34)
    @cv.arc(xy, outline: '', fill: color, width: 1, style: :pie, start: 0, extent: -91)
    @cv.arc(xy, outline: @C['fg'], width: 1, style: :arc, start: 0, extent: -90)
    xy = box(257, 433, 20)
    @cv.arc(xy, outline: '', fill: @C['bg'], width: 1, style: :pie, start: 0, extent: -92)
    @cv.arc(xy, outline: @C['fg'], width: 1, style: :arc, start: 0, extent: -90)
    xy = box(257, 421, 34)
    @cv.arc(xy, outline: '', fill: color, width: 1, style: :pie, start: 0, extent: 91)
    @cv.arc(xy, outline: @C['fg'], width: 1, style: :arc, start: 0, extent: 90)
    xy = box(257, 421, 20)
    @cv.arc(xy, outline: '', fill: @C['bg'], width: 1, style: :pie, start: 0, extent: 90)
    @cv.arc(xy, outline: @C['fg'], width: 1, style: :arc, start: 0, extent: 90)
    xy = box(243, 421, 34)
    @cv.arc(xy, outline: '', fill: color, width: 1, style: :pie, start: 90, extent: 90)
    @cv.arc(xy, outline: @C['fg'], width: 1, style: :arc, start: 90, extent: 90)
    xy = box(243, 421, 20)
    @cv.arc(xy, outline: '', fill: @C['bg'], width: 1, style: :pie, start: 90, extent: 90)
    @cv.arc(xy, outline: @C['fg'], width: 1, style: :arc, start: 90, extent: 90)

    # Joints
    @cv.rectangle([270, 427, 296, 433], fill: color, outline: @C['fg'], width: 1)
    @cv.rectangle([270, 421, 296, 427], fill: color, outline: @C['fg'], width: 1)
    @cv.rectangle([249, 382, 255, 408], fill: color, outline: @C['fg'], width: 1)
    @cv.rectangle([243, 382, 249, 408], fill: color, outline: @C['fg'], width: 1)
    @cv.rectangle([203, 420, 229, 426], fill: color, outline: @C['fg'], width: 1)

    @cv.oval(box(168, 460, 6), fill: @C['fg'], outline: '', tags: 'I19a')
    @cv.line([168, 460, 168, 512], fill: @C['fg'], width: 5, tags: 'I19b')
  end

  def move19(step = nil)
    step = get_step(19, step)
    angles = [30, 30, 30]
    return 2 if step == angles.length
    ox, oy = centroid('I19a')
    rotate_item('I19b', ox, oy, angles[step])
    return 1
  end

  # Water pouring
  def draw20; end

  def move20(step = nil)
    step = get_step(20, step)
    pos = [
      [451, 20], [462, 40], [473, 40], [484, 40], [496, 40],
      [504, 40], [513, 40], [523, 40], [532, 40, :x]
    ]
    return 0 if step >= pos.length

    cdel('I20')
    where = pos[step]
    y, f = where
    h20(y, f)
    return 3 if where[2] == :x
    return 1
  end

  def h20(y, f)
    cdel('I20')
    color = @C['20']

    sine([208, 428, 208, y], 4, f, tags: ['I20', 'I20s'],
         width: 3, fill: color, smooth: true)
    @cv.line(ccoords('I20s'), width: 3, fill: color, smooth: true,
             tags: ['I20', 'I20a'])
    @cv.line(ccoords('I20s'), width: 3, fill: color, smooth: true,
             tags: ['I20', 'I20b'])
    cmove('I20a', 8, 0)
    cmove('I20b', 16, 0)
  end

  # Bucket
  def draw21
    color = @C['21']
    @cv.line([217, 451, 244, 490], fill: @C['fg'], width: 2, tags: 'I21_a')
    @cv.line([201, 467, 182, 490], fill: @C['fg'], width: 2, tags: 'I21_a')

    xy  = [245, 490, 237, 535]
    xy2 = [189, 535, 181, 490]
    @cv.polygon(xy + xy2, fill: color, outline: '', tags: ['I21', 'I21f'])
    @cv.line(xy, fill: @C['fg'], width: 2, tags: 'I21')
    @cv.line(xy2, fill: @C['fg'], width: 2, tags: 'I21')

    @cv.oval([182, 486, 244, 498], fill: color, outline: '', width: 2,
             tags: ['I21', 'I21f'])
    @cv.oval([182, 486, 244, 498], fill: '', outline: @C['fg'], width: 2,
             tags: ['I21', 'I21t'])
    @cv.oval([189, 532, 237, 540], fill: color, outline: @C['fg'], width: 2,
             tags: ['I21', 'I21b'])
  end

  def move21(step = nil)
    step = get_step(21, step)
    numsteps = 30
    return 0 if step >= numsteps

    x1, y1, x2, y2 = cbbox('I21b')
    lx1, ly1, lx2, ly2 = [183, 492, 243, 504]

    f = step / numsteps.to_f
    y2 = y2 - 3
    xx1 = x1 + (lx1 - x1) * f
    yy1 = y1 + (ly1 - y1) * f
    xx2 = x2 + (lx2 - x2) * f
    yy2 = y2 + (ly2 - y2) * f

    citemconfig('I21b', fill: @C['20'])
    cdel('I21w')
    @cv.polygon(x2, y2, x1, y1, xx1, yy1, xx2, yy1,
                tags: ['I21', 'I21w'], outline: '', fill: @C['20'])
    clower('I21w', 'I21')
    craise('I21b')
    clower('I21f')

    return((step == numsteps - 1) ? 3 : 1)
  end

  # Bucket drop
  def draw22; end

  def move22(step = nil)
    step = get_step(22, step)
    pos = [[213, 513], [213, 523], [213, 543, :x], [213, 583], [213, 593]]

    citemconfig('I21f', fill: @C['22']) if step == 0
    return 0 if step >= pos.length
    where = pos[step]
    move_abs('I21', where)
    h20(where[1], 40)
    cdel('I21_a')
    return 3 if where[2] == :x
    return 1
  end

  # Blow dart
  def draw23
    color  = @C['23a']
    color2 = @C['23b']
    color3 = @C['23c']

    @cv.rectangle([185, 623, 253, 650], fill: 'black', outline: @C['fg'],
                  width: 2, tags: 'I23a')
    @cv.oval([187, 592, 241, 623], outline: '', fill: color, tags: 'I23b')
    @cv.arc([187, 592, 241, 623], outline: @C['fg'], width: 3, tags: 'I23b',
            style: :arc, start: 12, extent: 336)
    @cv.polygon([239, 604, 258, 589, 258, 625, 239, 610],
                outline: '', fill: color, tags: 'I23b')
    @cv.line([239, 604, 258, 589, 258, 625, 239, 610],
             fill: @C['fg'], width: 3, tags: 'I23b')

    @cv.oval([285, 611, 250, 603], fill: color2, outline: @C['fg'],
             width: 3, tags: 'I23d')
    @cv.polygon([249, 596, 249, 618, 264, 607, 249, 596],
                fill: color3, outline: @C['fg'], width: 3, tags: 'I23d')
    @cv.line([249, 607, 268, 607], fill: @C['fg'], width: 3, tags: 'I23d')
    @cv.line([285, 607, 305, 607], fill: @C['fg'], width: 3, tags: 'I23d')
  end

  def move23(step = nil)
    step = get_step(23, step)

    pos = [
      [277, 607], [287, 607], [307, 607, :x], [347, 607], [407, 607],
      [487, 607], [587, 607], [687, 607], [787, 607], [-100, -100]
    ]
    return 0 if step >= pos.length
    if step <= 1
      ox, oy = anchor('I23a', :n)
      cscale('I23b', ox, oy, 0.9, 0.5)
    end
    where = pos[step]
    move_abs('I23d', where)
    return 3 if where[2] == :x
    return 1
  end

  # Balloon
  def draw24
    color = @C['24a']
    @cv.oval([366, 518, 462, 665], fill: color, outline: @C['fg'],
             width: 3, tags: 'I24')
    @cv.line([414, 666, 414, 729], fill: @C['fg'], width: 3, tags: 'I24')
    @cv.polygon([410, 666, 404, 673, 422, 673, 418, 666],
                fill: color, outline: @C['fg'], width: 3, tags: 'I24')

    # Reflections
    @cv.line([387, 567, 390, 549, 404, 542], fill: @C['fg'], smooth: true,
             width: 2, tags: 'I24')
    @cv.line([395, 568, 399, 554, 413, 547], fill: @C['fg'], smooth: true,
             width: 2, tags: 'I24')
    @cv.line([403, 570, 396, 555, 381, 553], fill: @C['fg'], smooth: true,
             width: 2, tags: 'I24')
    @cv.line([408, 564, 402, 547, 386, 545], fill: @C['fg'], smooth: true,
             width: 2, tags: 'I24')
  end

  def move24(step = nil)
    step = get_step(24, step)
    return 0 if step > 4
    return 2 if step == 4

    if step == 0
      cdel('I24')
      xy = [
        347, 465, 361, 557, 271, 503, 272, 503, 342, 574, 259, 594,
        259, 593, 362, 626, 320, 737, 320, 740, 398, 691, 436, 738,
        436, 739, 476, 679, 528, 701, 527, 702, 494, 627, 548, 613,
        548, 613, 480, 574, 577, 473, 577, 473, 474, 538, 445, 508,
        431, 441, 431, 440, 400, 502, 347, 465, 347, 465
      ]
      @cv.polygon(xy, tags: 'I24', fill: @C['24b'],
                  outline: @C['24a'], width: 10, smooth: true)
      msg = @message_var.value.gsub("\\n", "\n")
      @cv.text(centroid('I24'), text: msg, tags: ['I24', 'I24t'],
               justify: :center, font: ['Times Roman', 18, :bold],
               fill: @C['fg'])
      return 1
    end

    citemconfig('I24t', font: ['Times Roman', 18 + 6 * step, :bold])
    cmove('I24', 0, -60)
    ox, oy = centroid('I24')
    cscale('I24', ox, oy, 1.25, 1.25)
    return 1
  end

  # Displaying the message
  def move25(step = nil)
    step = get_step(25, step)

    if step == 0
      @XY['25'] = clock_ms
      return 1
    end
    elapsed = clock_ms - @XY['25']
    return 1 if elapsed < 5000
    return 2
  end

  # Collapsing balloon
  def move26(step = nil)
    step = get_step(26, step)

    if step >= 3
      cdel('I24', 'I26')
      @cv.text(430, 740, anchor: :s, tags: 'I26',
               text: 'click to continue',
               font: ['Times Roman', 24, :bold],
               fill: @C['fg'])
      canvas_bind('Button-1') { reset }
      return 4
    end

    ox, oy = centroid('I24')
    cscale('I24', ox, oy, 0.8, 0.8)
    cmove('I24', 0, 60)
    citemconfig('I24t', font: ['Times Roman', 30 - 6 * step, :bold])
    return 1
  end

  ################################################################
  #
  # Helper functions
  #
  def box(x, y, r)
    [x - r, y - r, x + r, y + r]
  end

  def move_abs(item, xy)
    x, y = xy
    ox, oy = centroid(item)
    dx = x - ox
    dy = y - oy
    cmove(item, dx, dy)
  end

  def rotate_item(item, ox, oy, beta)
    xy = ccoords(item)
    xy2 = []
    0.step(xy.length - 1, 2) { |idx|
      x, y = xy[idx, 2]
      xy2.concat(rotate_c(x, y, ox, oy, beta))
    }
    ccoords(item, xy2)
  end

  def rotate_c(x, y, ox, oy, beta)
    x -= ox
    y -= oy
    beta = beta * Math.atan(1) * 4 / 180.0
    xx = x * Math.cos(beta) - y * Math.sin(beta)
    yy = x * Math.sin(beta) + y * Math.cos(beta)
    xx += ox
    yy += oy
    [xx, yy]
  end

  def reset
    draw_all
    canvas_bind_remove('Button-1')
    set_mode(:MSTART)
    @active = [0]
  end

  def get_step(who, step)
    if step
      @step[who] = step
    else
      if !@step.key?(who) || @step[who] == ''
        @step[who] = 0
      else
        @step[who] += 1
      end
    end
    v = @step_vars[who]
    v.value = @step[who] if v
    @step[who]
  end

  def reset_step
    @cnt = 0
    @cnt_var.value = 0
    @step.keys.each { |k|
      @step[k] = ''
      v = @step_vars[k]
      v.value = '' if v
    }
  end

  def sine(xy0, amp, freq, **opts)
    x0, y0, x1, y1 = xy0
    step = 2
    xy = []
    if y0 == y1
      x0.step(x1, step) { |x|
        beta = (x - x0) * 2 * Math::PI / freq
        y = y0 + amp * Math.sin(beta)
        xy << x << y
      }
    else
      y0.step(y1, step) { |y|
        beta = (y - y0) * 2 * Math::PI / freq
        x = x0 + amp * Math.sin(beta)
        xy << x << y
      }
    end
    @cv.line(xy, **opts)
  end

  def round_rect(xy, radius)
    x0, y0, x3, y3 = xy
    r = winfo_pixels(radius)
    d = 2 * r

    maxr = 0.75
    d = maxr * (x3 - x0) if d > maxr * (x3 - x0)
    d = maxr * (y3 - y0) if d > maxr * (y3 - y0)

    x1 = x0 + d; x2 = x3 - d
    y1 = y0 + d; y2 = y3 - d

    xy = [x0, y0, x1, y0, x2, y0, x3, y0, x3, y1, x3, y2]
    xy.concat([x3, y3, x2, y3, x1, y3, x0, y3, x0, y2, x0, y1])
    xy
  end

  def round_poly(xy, radii, **opts)
    lenXY = xy.length
    lenR = radii.length
    raise "wrong number of vertices and radii" if lenXY != 2 * lenR

    knots = []
    x0 = xy[-2]; y0 = xy[-1]
    x1 = xy[0];  y1 = xy[1]
    xy = xy + [xy[0], xy[1]]

    0.step(lenXY - 1, 2) { |i|
      radius = radii[i / 2]
      r = winfo_pixels(radius)
      x2 = xy[i + 2]; y2 = xy[i + 3]
      z = _round_poly2(x0, y0, x1, y1, x2, y2, r)
      knots.concat(z)
      x0 = x1; y0 = y1
      x1 = x2; y1 = y2
    }
    @cv.polygon(knots, smooth: true, **opts)
  end

  def _round_poly2(x0, y0, x1, y1, x2, y2, radius)
    d = 2 * radius
    maxr = 0.75

    v1x = x0 - x1; v1y = y0 - y1
    v2x = x2 - x1; v2y = y2 - y1

    vlen1 = Math.sqrt(v1x * v1x + v1y * v1y)
    vlen2 = Math.sqrt(v2x * v2x + v2y * v2y)

    d = maxr * vlen1 if d > maxr * vlen1
    d = maxr * vlen2 if d > maxr * vlen2

    xy = []
    xy << (x1 + d * v1x / vlen1) << (y1 + d * v1y / vlen1)
    xy << x1 << y1
    xy << (x1 + d * v2x / vlen2) << (y1 + d * v2y / vlen2)
    xy
  end

  def sparkle(oxy, tag)
    xy = [
      [299, 283], [298, 302], [295, 314], [271, 331],
      [239, 310], [242, 292], [256, 274], [281, 273]
    ]
    xy.each { |x, y|
      @cv.line([271, 304, x, y], fill: 'white', width: 3, tags: tag)
    }
    move_abs(tag, oxy)
  end

  def centroid(item)
    anchor(item, :c)
  end

  def anchor(item, where)
    x1, y1, x2, y2 = cbbox(item)
    case where
    when :n then y = y1
    when :s then y = y2
    else         y = (y1 + y2) / 2.0
    end
    case where
    when :w then x = x1
    when :e then x = x2
    else         x = (x1 + x2) / 2.0
    end
    [x, y]
  end

  private

  # -- Canvas item helpers, matching goldberg.rb's own GoldbergHelpers
  # vocabulary but reimplemented over CanvasItem (Handle#tagged(tag)
  # addresses a tag/id group uniformly) instead of raw tcl_eval - see the
  # class comment for why these keep the original names.

  def cmove(tag, dx, dy)
    @cv.tagged(tag).move(dx, dy)
  end

  def ccoords(tag, new_coords = nil)
    item = @cv.tagged(tag)
    new_coords ? (item.coords = new_coords) : item.coords
  end

  def cdel(*tags)
    tags.each { |t| @cv.tagged(t).delete }
  end

  def cbbox(tag)
    @cv.tagged(tag).bounds
  end

  def cscale(tag, ox, oy, sx, sy)
    @cv.tagged(tag).scale(ox, oy, sx, sy)
  end

  def citemconfig(tag, **opts)
    @cv.tagged(tag).configure(**opts)
  end

  def citemcget(tag, opt)
    @cv.tagged(tag)[opt]
  end

  # The original returns every matching item id; every call site here
  # only ever checks emptiness, so a real/fake single-element array is
  # enough to keep those call sites (`cfind(tag).empty?`) unchanged.
  def cfind(tag)
    @cv.tagged(tag).exists? ? [tag] : []
  end

  def craise(tag, above = nil)
    @cv.tagged(tag).bring_to_front(above)
  end

  def clower(tag, below = nil)
    @cv.tagged(tag).send_to_back(below)
  end

  # Only ever bound to a plain left click in this demo (the START HERE
  # banner and the dropped ball, both start the animation on click).
  def cbind_item(tag, &block)
    @cv.tagged(tag).on_click(&block)
  end

  # Canvas-widget-level bind (as opposed to an item bind, see
  # #cbind_item) - only ever Button-3 (right-click, toggles pause) or
  # Button-1 (click to restart once the puzzle finishes) in this demo.
  def canvas_bind(event, &block)
    case event
    when 'Button-3' then @cv.on_right_click(&block)
    when 'Button-1' then @cv.on_click(&block)
    end
  end

  def canvas_bind_remove(event)
    @cv.app.unbind(@cv.path, "<#{event}>")
  end

  def winfo_pixels(val)
    @cv.app.tcl_eval("winfo pixels #{@cv.path} #{val}").to_i
  end

  def clock_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
  end
end
