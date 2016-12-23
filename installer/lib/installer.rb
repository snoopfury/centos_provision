require 'pathname'
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', Pathname.new(__FILE__).realpath)

require 'rubygems'
require 'bundler/setup'

require 'open3'
require 'tmpdir'
require 'active_support'

class Installer
  INSTALLER_ROOT = File.expand_path(File.dirname(__FILE__) + '/../')
  INSTALLER_CMD = 'install.sh'
  INVENTORY_FILE = 'hosts.txt'

  class Inventory
    attr_reader :values

    LINES_DIVIDER = "\n"
    VALUES_DIVIDER = '='

    def initialize(values: {})
      self.values = values
    end

    def read_from_file(file)
      content = IO.read(file)
      self.values = content
                      .split(LINES_DIVIDER)
                      .grep(/#{VALUES_DIVIDER}/)
                      .map { |line| line.split(VALUES_DIVIDER) }
                      .to_h
    end

    def self.write_to_file(file, values)
      strings = values
                  .map { |key, value| [key, value] }
                  .map { |array| array.join(VALUES_DIVIDER) }
                  .push('')
      IO.write(file, strings.join(LINES_DIVIDER))
    end

    def values=(values)
      @values = values.map { |k, v| [k.to_sym, v] }.to_h
    end
  end

  attr_accessor :env, :args, :prompts_with_values, :stored_values, :docker_image
  attr_reader :stdout, :stderr, :ret_value, :inventory

  def initialize(env: {}, args: '', prompts_with_values: {}, stored_values: {}, docker_image: nil)
    @env, @args, @prompts_with_values, @stored_values, @docker_image =
      env, args, prompts_with_values, stored_values, docker_image
    @inventory = Inventory.new
  end

  def call
    Dir.mktmpdir('', '/tmp') do |current_dir|
      Dir.chdir(current_dir) do
        write_to_inventory(stored_values)

        invoke_installer_cmd(current_dir)

        read_inventory
      end
    end
  end

  def self.docker_installed?
    system("sh -c 'command -v docker > /dev/null'")
  end

  private

  def write_to_inventory(stored_values)
    Inventory.write_to_file(INVENTORY_FILE, stored_values)
  end

  def invoke_installer_cmd(current_dir)
    FileUtils.copy("#{INSTALLER_ROOT}/#{INSTALLER_CMD}", current_dir)

    Open3.popen3(*installer_cmd(current_dir)) do |stdin, stdout, stderr, wait_thr|
      stdout.sync = true
      stdin.sync = true

      @stdout = emulate_interactive_io(stdin, stdout)
      @stderr = Thread.new { stderr.read }.value
      @ret_value = wait_thr.value
    end
  end

  def read_inventory
    inventory.read_from_file(INVENTORY_FILE) if ret_value.success?
  end

  def installer_cmd(current_dir)
    if docker_image
      "docker run #{docker_env} --name keitaro_installer_test -i --rm -v #{current_dir}:/data -w /data #{docker_image} ./#{INSTALLER_CMD} #{args}"
    else
      [stringified_env, "#{current_dir}/#{INSTALLER_CMD} #{args}"]
    end
  end

  def docker_env
    env.map { |key, value| "-e #{key}=#{value}" }.join(' ')
  end

  def stringified_env
    env.map { |key, value| [key.to_s, value.to_s] }.to_h
  end

  def emulate_interactive_io(stdin, stdout)
    out = ''
    reader_thread = Thread.new {
      begin
        stdout_chunk = read_stream(stdout)
        out << stdout_chunk

        break if stdout_chunk == ''

        prompt = stdout_chunk.split("\n").last

        if prompt =~ / > $/
          byebug if prompt =~ /Evaluating/
          key = prompt.match(/[[[:alnum:]]\s]+/)[0].strip
          if prompts_with_values.key?(key)
            stdin.puts(prompts_with_values[key])
          else
            stdin.puts('value')
            puts "Value for prompt #{prompt.inspect} not found, using fake value instead"
          end
        end
      end while true
    }
    reader_thread.value
    out
  end

  def read_stream(stdout)
    buffer = ''

    begin
      char = stdout.getc
      return buffer if char.nil?

      buffer << char
    end while char != '>'

    buffer << stdout.getc
    buffer
  end
end

begin
  unless Installer.docker_installed?
    puts 'You need to install the docker for running this specs'
  end
end

