require 'timeout'

require_relative 'gitlab_config'
require_relative 'gitlab_logger'

class GitlabKeys
  attr_accessor :auth_file, :key

  def initialize
    @command = ARGV.shift
    @key_id = ARGV.shift
    @key = ARGV.shift
    @auth_file = GitlabConfig.new.auth_file
  end

  def exec
    case @command
    when 'add-key'; add_key
    when 'batch-add-keys'; batch_add_keys
    when 'rm-key';  rm_key
    when 'list-keys'; puts list_keys
    when 'clear';  clear
    else
      $logger.warn "Attempt to execute invalid gitlab-keys command #{@command.inspect}."
      puts 'not allowed'
      false
    end
  end

  protected

  def add_key
    lock do
      $logger.info "Adding key #{@key_id} => #{@key.inspect}"
      auth_line = key_line(@key_id, @key)
      open(auth_file, 'a') { |file| file.puts(auth_line) }
    end
    true
  end

  def list_keys
    $logger.info 'Listing all keys'
    keys = ''
    File.readlines(auth_file).each do |line|
      # key_id & public_key
      # command=".../bin/gitlab-shell key-741" ... ssh-rsa AAAAB3NzaDAxx2E\n
      #                               ^^^^^^^              ^^^^^^^^^^^^^^^
      matches = /^command=\".+?\s+(.+?)\".+?(?:ssh|ecdsa)-.*?\s(.+)\s*.*\n*$/.match(line)
      keys << "#{matches[1]} #{matches[2]}\n" unless matches.nil?
    end
    keys
  end

  def batch_add_keys
    lock(300) do # Allow 300 seconds (5 minutes) for batch_add_keys
      open(auth_file, 'a') do |file|
        stdin.each_line do |input|
          tokens = input.strip.split("\t")
          abort("#{$0}: invalid input #{input.inspect}") unless tokens.count == 2
          key_id, public_key = tokens
          $logger.info "Adding key #{key_id} => #{public_key.inspect}"
          file.puts(key_line(key_id, public_key))
        end
      end
    end
    true
  end

  def stdin
    $stdin
  end

  def key_command(key_id)
    "#{ROOT_PATH}/bin/gitlab-shell #{key_id}"
  end

  def key_line(key_id, public_key)
    auth_line = "command=\"#{key_command(key_id)}\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty #{public_key}"
  end

  def rm_key
    lock do
      $logger.info "Removing key #{@key_id}"
      open(auth_file, 'r+') do |f|
        while line = f.gets do
          next unless line.start_with?("command=\"#{key_command(@key_id)}\"")
          f.seek(-line.length, IO::SEEK_CUR)
          # Overwrite the line with #'s. Because the 'line' variable contains
          # a terminating '\n', we write line.length - 1 '#' characters.
          f.write('#' * (line.length - 1))
        end
      end
    end
    true
  end

  def clear
    open(auth_file, 'w') { |file| file.puts '# Managed by gitlab-shell' }
    true
  end


  def lock(timeout = 10)
    File.open(lock_file, "w+") do |f|
      begin
        f.flock File::LOCK_EX
        Timeout::timeout(timeout) { yield }
      ensure
        f.flock File::LOCK_UN
      end
    end
  end

  def lock_file
    @lock_file ||= auth_file + '.lock'
  end
end
