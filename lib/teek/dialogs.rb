# frozen_string_literal: true

module Teek
  class App
    # Show the native "choose file to open" dialog.
    #
    # @param filetypes [Array<Array>, nil] e.g.
    #   +[["PNG Images", ".png"], ["All Files", "*"]]+ - the second
    #   element of each pair can also be an array of extensions
    #   (+["Images", [".png", ".jpg"]]+)
    # @param initialdir [String, nil] directory the dialog starts in
    # @param initialfile [String, nil] filename pre-filled in the dialog
    # @param title [String, nil] dialog window title
    # @param multiple [Boolean] allow selecting more than one file
    # @param parent [String, nil] parent window (defaults to the root window)
    # @return [String, Array<String>, nil] the chosen path (an array of
    #   paths if +multiple:+), or +nil+ if the dialog was cancelled
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/getOpenFile.htm tk_getOpenFile
    def choose_open_file(filetypes: nil, initialdir: nil, initialfile: nil,
                          title: nil, multiple: false, parent: nil)
      args = ['tk_getOpenFile']
      args.push('-filetypes', build_filetypes(filetypes)) if filetypes
      args.push('-initialdir', initialdir) if initialdir
      args.push('-initialfile', initialfile) if initialfile
      args.push('-title', title) if title
      args.push('-parent', parent) if parent
      args.push('-multiple', bool_to_tcl(true)) if multiple

      result = tcl_invoke(*args)
      return nil if result.empty?

      multiple ? split_list(result) : result
    end

    # Show the native "choose file to save" dialog.
    #
    # @param filetypes [Array<Array>, nil] see {#choose_open_file}
    # @param initialdir [String, nil] directory the dialog starts in
    # @param initialfile [String, nil] filename pre-filled in the dialog
    # @param title [String, nil] dialog window title
    # @param defaultextension [String, nil] extension appended if the
    #   typed filename doesn't already have one
    # @param confirmoverwrite [Boolean] ask before overwriting an
    #   existing file (Tk's own default is true; pass false to skip the
    #   confirmation)
    # @param parent [String, nil] parent window (defaults to the root window)
    # @return [String, nil] the chosen path, or +nil+ if cancelled
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/getOpenFile.htm tk_getSaveFile
    def choose_save_file(filetypes: nil, initialdir: nil, initialfile: nil,
                          title: nil, defaultextension: nil, confirmoverwrite: true, parent: nil)
      args = ['tk_getSaveFile']
      args.push('-filetypes', build_filetypes(filetypes)) if filetypes
      args.push('-initialdir', initialdir) if initialdir
      args.push('-initialfile', initialfile) if initialfile
      args.push('-title', title) if title
      args.push('-defaultextension', defaultextension) if defaultextension
      args.push('-confirmoverwrite', bool_to_tcl(false)) unless confirmoverwrite
      args.push('-parent', parent) if parent

      result = tcl_invoke(*args)
      result.empty? ? nil : result
    end

    # Show a message box with one or more buttons.
    #
    # @param message [String] the main message text
    # @param title [String, nil] dialog window title
    # @param detail [String, nil] additional explanatory text, shown
    #   smaller below +message+
    # @param icon [:error, :info, :question, :warning] icon to display
    # @param type [:ok, :okcancel, :abortretryignore, :yesno, :yesnocancel, :retrycancel]
    #   which button(s) to show
    # @param default [Symbol, nil] which button is focused by default
    #   (e.g. +:cancel+); defaults to Tk's own choice if omitted
    # @param parent [String, nil] parent window (defaults to the root window)
    # @return [Symbol] the pressed button - +:ok+, +:cancel+, +:yes+,
    #   +:no+, +:abort+, +:retry+, or +:ignore+
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/messageBox.htm tk_messageBox
    def message_box(message:, title: nil, detail: nil, icon: :info, type: :ok,
                     default: nil, parent: nil)
      args = ['tk_messageBox', '-message', message.to_s]
      args.push('-title', title) if title
      args.push('-detail', detail) if detail
      args.push('-icon', icon.to_s) if icon
      args.push('-type', type.to_s) if type
      args.push('-default', default.to_s) if default
      args.push('-parent', parent) if parent

      tcl_invoke(*args).to_sym
    end

    # Show the native color picker dialog.
    #
    # @param initial [String, nil] initial color (e.g. +"#ff0000"+)
    # @param title [String, nil] dialog window title
    # @param parent [String, nil] parent window (defaults to the root window)
    # @return [String, nil] the chosen color as +"#rrggbb"+, or +nil+ if cancelled
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/chooseColor.htm tk_chooseColor
    def choose_color(initial: nil, title: nil, parent: nil)
      args = ['tk_chooseColor']
      args.push('-initialcolor', initial) if initial
      args.push('-title', title) if title
      args.push('-parent', parent) if parent

      result = tcl_invoke(*args)
      result.empty? ? nil : result
    end

    # Show the native "choose directory" dialog.
    #
    # @param initialdir [String, nil] directory the dialog starts in
    # @param mustexist [Boolean] restrict the choice to an already-existing
    #   directory (Tk's own default is false, allowing a not-yet-created one)
    # @param title [String, nil] dialog window title
    # @param parent [String, nil] parent window (defaults to the root window)
    # @return [String, nil] the chosen directory path, or +nil+ if cancelled
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/chooseDirectory.htm tk_chooseDirectory
    def choose_dir(initialdir: nil, mustexist: false, title: nil, parent: nil)
      args = ['tk_chooseDirectory']
      args.push('-initialdir', initialdir) if initialdir
      args.push('-mustexist', bool_to_tcl(true)) if mustexist
      args.push('-title', title) if title
      args.push('-parent', parent) if parent

      result = tcl_invoke(*args)
      result.empty? ? nil : result
    end

    # Pop up a menu at the given screen coordinates.
    #
    # @param menu [Widget, String] the menu to pop up
    # @param x [Integer] screen x coordinate
    # @param y [Integer] screen y coordinate
    # @param entry [Integer, String, nil] index or label of the entry to
    #   show as active
    # @return [void]
    # @see https://www.tcl-lang.org/man/tcl9.0/TkCmd/menu.htm#M42 tk_popup
    def popup_menu(menu, x:, y:, entry: nil)
      args = ['tk_popup', menu.to_s, x.to_s, y.to_s]
      args << entry.to_s if entry
      tcl_invoke(*args)
      nil
    end

    private

    # Builds the nested Tcl list -filetypes expects:
    # {{name extensionOrExtensionList} {name2 ...}}
    def build_filetypes(filetypes)
      entries = filetypes.map do |name, exts|
        ext_arg = exts.is_a?(Array) ? make_list(*exts) : exts.to_s
        make_list(name.to_s, ext_arg)
      end
      make_list(*entries)
    end
  end
end
