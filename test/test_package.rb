# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'tk_test_helper'

class TestPackage < Minitest::Test
  include TeekTestHelper

  def test_require_package_loads_and_returns_version
    assert_tk_app("require_package should load package and return version") do
      fixtures = File.join(Dir.pwd, 'test', 'fixtures')
      app.tcl_eval("lappend ::auto_path {#{fixtures}}")

      assert_equal '1.0', app.require_package('teektest')
      assert_equal 'Hello, World!', app.tcl_eval('::teektest::hello World')
    end
  end

  def test_require_package_with_version
    assert_tk_app("require_package with version should work") do
      fixtures = File.join(Dir.pwd, 'test', 'fixtures')
      app.tcl_eval("lappend ::auto_path {#{fixtures}}")

      assert_equal '1.0', app.require_package('teektest', '1.0')
    end
  end

  def test_require_package_missing_raises_tcl_error
    assert_tk_app("require_package should raise on missing package") do
      err = assert_raises(Teek::TclError) { app.require_package('nonexistent_package_xyz') }
      assert_includes err.message, 'nonexistent_package_xyz'
    end
  end

  def test_package_names
    assert_tk_app("package_names should return array of available packages") do
      names = app.package_names
      assert_kind_of Array, names
      assert_includes names, 'Tk'
    end
  end

  def test_package_present
    assert_tk_app("package_present? should detect loaded packages") do
      assert app.package_present?('Tk'), "Tk should be present"
      refute app.package_present?('nonexistent_xyz'), "nonexistent should not be present"
    end
  end

  def test_package_versions
    assert_tk_app("package_versions should return available versions") do
      fixtures = File.join(Dir.pwd, 'test', 'fixtures')
      app.add_package_path(fixtures)

      assert_equal ['1.0'], app.package_versions('teektest')
    end
  end

  def test_add_package_path_and_require
    assert_tk_app("add_package_path should make packages loadable") do
      fixtures = File.join(Dir.pwd, 'test', 'fixtures')
      app.add_package_path(fixtures)

      assert_equal '1.0', app.require_package('teektest')
    end
  end

  def test_add_package_path_appears_in_auto_path
    assert_tk_app("add_package_path should append to auto_path") do
      app.add_package_path('/tmp/fake_packages')
      paths = app.split_list(app.tcl_eval('set ::auto_path'))
      assert_includes paths, '/tmp/fake_packages'
    end
  end
end
