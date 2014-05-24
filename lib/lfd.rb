# -*- encoding:utf-8
require 'yaml'
require 'fileutils'
require 'open3'
require 'colored'
require 'shellwords'

class LFD

  CONFIG_FILE   = 'asproj.info'
  MXMLC         = ENV['MXMLC'] || 'mxmlc'
  FLASH_PLAYER  = ENV['FLASH_PLAYER'] || 'flashplayer'
  TRACE_LOG     = File.join ENV['HOME'], '/.macromedia/Flash_Player/Logs/flashlog.txt'
  CONFIG_SAMPLE = File.expand_path("../#{CONFIG_FILE}.sample", __FILE__)
  MM_CFG        = File.join ENV['HOME'], '/mm.cfg'

  # Public: Check the flash developing environment
  def env(opt={})
    check_flex_sdk
    check_flash_player
  end

  def check_flex_sdk
    print "Flex SDK:".ljust(15)
    check_path MXMLC
    print "\n"
  end

  def check_path cmd
    path = executable_path( cmd )
    if path
      print path.chomp.green
    else
      print "✗".red
    end
  end

  def check_flash_player
    print "Flash Player: ".ljust(15)
    check_path FLASH_PLAYER
    print "\n"
  end

  def executable_path cmd
    path = `which #{Shellwords.escape(cmd)}`
    path.empty? ? nil : path
  end

  def executable? cmd
    !!executable_path
  end

  ## end of check functions
  # TODO: move to a module

  # Setup subcommand

  def setup(opt={})
    install_flex_sdk
    install_flash_player
  end

  def init(opt={})
    FileUtils.cp CONFIG_SAMPLE, CONFIG_FILE
    FileUtils.mkdir_p %w(bin lib src tmp)
  end

  def build(opt={})
    if File.exist?(CONFIG_FILE)
      info = YAML.load_file(CONFIG_FILE)
      args = build_arg(info, opt)
      Open3.popen3 MXMLC, info["main"], *args do |i, o, e, t|
        t.value
      end
    else
      fail "#{CONFIG_FILE} not found, exiting"
      exit 
    end
  end

  def test
    build
    run
  end

  def release(opt=Hash.new)
    build :debug => false
  end

  def run(opt={})
    check_tracelog_config
    empty_tracelog
    info = YAML.load_file(CONFIG_FILE)
    swf = File.expand_path(info["output"]["file"], FileUtils.pwd) 
    player = fork { exec "#{FLASH_PLAYER} #{swf} 2> /dev/null"}
    tracer = fork { exec "tail", "-f", TRACE_LOG }
    Process.detach tracer
    Process.wait
    Process.kill "HUP", tracer
  end

  def clean(opt={})
    FileUtils.rm_f CONFIG_FILE
    FileUtils.rmdir %w(bin lib src tmp)
  end

  private
  def install_flex_sdk
  end

  def install_flash_player
  end

  public
  def check_tracelog_config
    if File.exist?(MM_CFG)
      File.open(MM_CFG, 'r+') do |file|
        cfg = {}
        file.each do |line|
          opt = line.split('=')
          cfg[opt[0]] = opt[1].chomp
        end
        cfg["ErrorReportingEnable"]="1"
        cfg["TraceOutputFileEnable"]="1"
        str = cfg.inject("") { |s,o| "#{s}#{o[0]}=#{o[1]}\n" }
        file.rewind
        file.write str
      end
    else
      File.open(MM_CFG, 'w') do |file|
        file.puts("ErrorReportingEnable=1\nTraceOutputFileEnable=1")
      end
    end
  end

  private
  def empty_tracelog
    system "echo '' > #{TRACE_LOG}"
  end

  def build_arg(info, opt={})
    ot = info["output"]
    args = [
      "--target-player=#{info["target"]}",
      "--output=#{ot["file"]}",
      "--source-path=#{array_opt_to_s info["source"]}",
      "--debug=#{opt[:debug] != false}",
      "-static-link-runtime-shared-libraries=true" 
      # TODO: 加上更多的编译选项
    ]
    info["library"].each { |lib| args << "--library-path+=#{lib}" }
    w, h = ot["width"], ot["height"]
    args << "--default-size=#{w},#{h}" if w and h
    args
  end

  def array_opt_to_s(src)
    if Array === src
      src.join(',')
    else
      src.to_s
    end
  end

end
