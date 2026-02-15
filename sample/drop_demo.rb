# frozen_string_literal: true

# Drop Demo - drag a file from Finder onto the window
#
# Demonstrates Teek's native file drop support.
# The label updates to show the filename and file size.

require_relative '../lib/teek'

app = Teek::App.new(title: "Drop Demo")
app.show
app.command(:wm, :geometry, '.', '400x200')

app.command(:label, '.info', text: "Drop a file here",
            font: "TkDefaultFont 16", anchor: :center)
app.command(:pack, '.info', expand: 1, fill: :both, padx: 20, pady: 20)

app.register_drop_target('.')

app.bind('.', '<<DropFile>>', :data) do |path|
  if File.exist?(path)
    size = File.size(path)
    human = if size >= 1_048_576
              "%.1f MB" % (size / 1_048_576.0)
            elsif size >= 1024
              "%.1f KB" % (size / 1024.0)
            else
              "#{size} bytes"
            end
    app.command('.info', :configure, text: "#{File.basename(path)}\n#{human}")
  else
    app.command('.info', :configure, text: "#{path}\n(file not found)")
  end
end

app.mainloop
