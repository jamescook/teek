namespace :screenshots do
  desc "Bless current unverified screenshots as the new baselines"
  task :bless do
    require_relative '../../test/screenshot_helper'
    src = ScreenshotHelper.unverified_dir
    dst = ScreenshotHelper.blessed_dir

    pngs = Dir.glob(File.join(src, '*.png'))
    if pngs.empty?
      puts "No unverified screenshots in #{src}"
      next
    end

    FileUtils.mkdir_p(dst)
    pngs.each do |f|
      FileUtils.cp(f, dst)
      puts "  Blessed: #{File.basename(f)}"
    end
    puts "#{pngs.size} screenshot(s) blessed to #{dst}"
  end

  desc "Remove unverified screenshots and diffs"
  task :clean do
    require_relative '../../test/screenshot_helper'
    [ScreenshotHelper.unverified_dir, ScreenshotHelper.diffs_dir].each do |dir|
      if Dir.exist?(dir)
        FileUtils.rm_rf(dir)
        puts "  Removed: #{dir}"
      end
    end
  end
end
