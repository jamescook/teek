# frozen_string_literal: true

require "minitest/autorun"
require "teek/mgba"
require "tmpdir"
require "zip"

class TestRomLoader < Minitest::Test
  TEST_ROM = File.expand_path("fixtures/test.gba", __dir__)

  def setup
    skip "Run: ruby teek-mgba/scripts/generate_test_rom.rb" unless File.exist?(TEST_ROM)
    @tmpdir = Dir.mktmpdir("rom_loader_test")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
    Teek::MGBA::RomLoader.cleanup_temp
  end

  # -- resolve passthrough --

  def test_resolve_gba_returns_path_unchanged
    assert_equal TEST_ROM, Teek::MGBA::RomLoader.resolve(TEST_ROM)
  end

  def test_resolve_gb_returns_path_unchanged
    path = "/some/game.gb"
    assert_equal path, Teek::MGBA::RomLoader.resolve(path)
  end

  def test_resolve_gbc_returns_path_unchanged
    path = "/some/game.gbc"
    assert_equal path, Teek::MGBA::RomLoader.resolve(path)
  end

  # -- resolve from zip --

  def test_resolve_zip_extracts_rom
    zip_path = create_zip("game.zip", "game.gba" => File.binread(TEST_ROM))
    result = Teek::MGBA::RomLoader.resolve(zip_path)

    assert File.exist?(result), "extracted ROM should exist"
    assert_equal ".gba", File.extname(result).downcase
    assert_equal File.binread(TEST_ROM), File.binread(result)
  end

  def test_resolve_zip_loads_in_core
    zip_path = create_zip("game.zip", "game.gba" => File.binread(TEST_ROM))
    rom_path = Teek::MGBA::RomLoader.resolve(zip_path)

    core = Teek::MGBA::Core.new(rom_path)
    assert_equal "TEEKTEST", core.title
  ensure
    core&.destroy
  end

  # -- error cases --

  def test_resolve_zip_no_rom_raises
    zip_path = create_zip("empty.zip", "readme.txt" => "hello")

    err = assert_raises(Teek::MGBA::RomLoader::NoRomInZip) do
      Teek::MGBA::RomLoader.resolve(zip_path)
    end
    assert_includes err.message, "empty.zip"
  end

  def test_resolve_zip_multiple_roms_raises
    rom_data = File.binread(TEST_ROM)
    zip_path = create_zip("multi.zip",
      "game1.gba" => rom_data,
      "game2.gba" => rom_data)

    err = assert_raises(Teek::MGBA::RomLoader::MultipleRomsInZip) do
      Teek::MGBA::RomLoader.resolve(zip_path)
    end
    assert_includes err.message, "multi.zip"
  end

  def test_resolve_unsupported_extension_raises
    assert_raises(Teek::MGBA::RomLoader::UnsupportedFormat) do
      Teek::MGBA::RomLoader.resolve("/some/file.rar")
    end
  end

  def test_resolve_corrupt_zip_raises
    corrupt = File.join(@tmpdir, "corrupt.zip")
    File.binwrite(corrupt, "this is not a zip file")

    assert_raises(Teek::MGBA::RomLoader::ZipReadError) do
      Teek::MGBA::RomLoader.resolve(corrupt)
    end
  end

  # -- zip with subdirectories (only root-level ROMs) --

  def test_resolve_zip_ignores_roms_in_subdirectories
    zip_path = File.join(@tmpdir, "nested.zip")
    Zip::OutputStream.open(zip_path) do |zos|
      zos.put_next_entry("subdir/game.gba")
      zos.write(File.binread(TEST_ROM))
    end

    assert_raises(Teek::MGBA::RomLoader::NoRomInZip) do
      Teek::MGBA::RomLoader.resolve(zip_path)
    end
  end

  # -- constants --

  def test_rom_extensions
    assert_includes Teek::MGBA::RomLoader::ROM_EXTENSIONS, ".gba"
    assert_includes Teek::MGBA::RomLoader::ROM_EXTENSIONS, ".gb"
    assert_includes Teek::MGBA::RomLoader::ROM_EXTENSIONS, ".gbc"
  end

  def test_supported_extensions_includes_zip
    assert_includes Teek::MGBA::RomLoader::SUPPORTED_EXTENSIONS, ".zip"
  end

  # -- cleanup --

  def test_cleanup_temp_removes_directory
    zip_path = create_zip("game.zip", "game.gba" => File.binread(TEST_ROM))
    Teek::MGBA::RomLoader.resolve(zip_path)
    assert File.directory?(Teek::MGBA::RomLoader.tmp_dir)

    Teek::MGBA::RomLoader.cleanup_temp
    refute File.directory?(Teek::MGBA::RomLoader.tmp_dir)
  end

  private

  # Build a ZIP file using rubyzip.
  # @param name [String] output filename
  # @param entries [Hash{String => String}] filename => content
  # @return [String] path to the created ZIP file
  def create_zip(name, entries)
    path = File.join(@tmpdir, name)
    Zip::OutputStream.open(path) do |zos|
      entries.each do |fname, content|
        zos.put_next_entry(fname)
        zos.write(content)
      end
    end
    path
  end
end
