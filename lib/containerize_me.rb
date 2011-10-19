# Authod: Cliff Cyphers
# Published as part of the cyberconnect's platform mainly used
# in hosting rails applications.  
# Licesnse: GPLv3: http://www.gnu.org/licenses/gpl.html


base = File.expand_path(File.dirname(__FILE__))
require base + '/file'
require base + '/cp_dep_libs'

ENV['PATH'] += "/opt/cyberconnect/bin:/opt/cyberconnect/usr/bin:/opt/cyberconnect/sbin:/opt/cyberconnect/usr/sbin"

class ContainerizeMe
  VERSION = '0.1.3'
end
class JailKitNotFoundError < StandardError ; end
class JailNotWritable < StandardError ; end
class NoJailDirectory < StandardError ; end


module Jail
  class Config
    attr_reader :jail, :dep_order, :cfg
    def initialize(params={})
      @cfg = params[:cfg]
      @cfg[:system_binaries] ||= []
      @cfg[:other_binaries] ||= []
      @cfg[:copy_items] ||= []

      @jail = params[:jail]
      @templates = params[:templates]
      @system_binaries = @cfg[:system_binaries]
      @other_files = @cfg[:other_files]
      @dep_order = []
      order(@cfg)
    end

    def order(file)
      if File.exists?("#{@templates}/#{file}")
        cfg = YAML::load_file("#{@templates}/#{file}")
      else
        cfg = file
      end
      @dep_order << cfg unless @dep_order.include?(cfg)
      if cfg.has_key?(:depends_on)
        if cfg[:depends_on].kind_of?(Array)
          cfg[:depends_on].each { |f| order(f) }
        end
      end 
    end
  end

  def exec(str)
    res = '' 
    std_in, std_out, std_err = Open3::popen3(str) 
    puts std_out.read
    err = std_err.read
    err.each_line { |line|
      next if "#{line}" =~ /empty, not checked/
      res += line
    }
    res 
  end
  def has_jailkit?
    out=`which jk_init`
    out.length > 0 ? true : false
  end
  def create
    FileUtils.mkdir_p @config.jail unless File.directory?(@config.jail)
    raise JailKitNotFoundError, Constants::Errors::MISSING_JK unless has_jailkit?
    raise JailNotWritable, Constants::Errors::JAIL_NOT_WRITABLE unless File.writable?(@config.jail)

    err = Jail.exec("jk_init -j #{@config.jail} jk_lsh")
    if err.length != 0
      raise StandardError, "#{Constants::Errors::JK_INIT_ERROR} #{err}"
    end
    true
  end
 
  # TODO: update to use following:
  # jk_cp takes too long when copying large directory structures.  Use
  # FileUtils.cp_r first followed by cp_dep_libs to use jk_cp to copy over
  # deps for executable and shared object items
  def cp(item)
#=begin
    if File.directory?(item)
      dir = File.dirname(item)
      begin
        FileUtils.mkdir_p("#{@config.jail}#{dir}") unless File.directory?("#{@config.jail}#{dir}")
        FileUtils.cp_r(item, "#{@config.jail}#{dir}", {:remove_destination => true})#, :preserve => true})
      rescue => e
      end
      Jail.cp_dep_libs(item, @config.jail)
      err = ''
    else
#=end
      err = Jail.exec("jk_cp -o -j #{@config.jail} #{item}") 
    end
    FileUtils.clone_perms(item, @config.jail)
    if err.length != 0
      raise StandardError, "#{Constants::Errors::JK_INIT_ERROR} #{err}"
    end
    true
  end

  def add_common_items
    files = []
    common = %w(libnss libcurl)
    common.each { |lib|
      Find.find('/lib').each { |i| files << i if i =~ /#{lib}/ }
    }
    files
  end

  def user_in_jail?(user)
    File.read(@config.jail + '/etc/passwd').grep(/^#{user}/).first != nil ? true : false
  end

  def group_in_jail?(gid)
    File.read(@config.jail + '/etc/group').grep(/#{gid}:$/).first != nil ? true : false
  end


  # In order to preserve the system's /etc/passwd jailkit's jk_addjailuser is avoided.  
  # We only require that the user exists in the jail for all actions needed to host 
  # apps.  Also, all other services(sshd, mysql, beanstalkd, etc) work fine 
  # using chroot with the --userspec. It's assumed system user's are not 
  # chrooted to a jail.  A separate sshd process runs in the jail on a custom port
  # and when a required jail user logs into that ssh instance they are confined to the jail. 
  # For this separation user's are added to the jail by grabbing the user info 
  # from /etc/passwd and appending to @config.jail/etc/passwd.  
  def add_user(user)
    unless Jail.user_in_jail?(user) 
      system_users = File.read('/etc/passwd').split(/\n/).grep(/^#{user}/)
      raise StandardError unless system_users.length == 1
      user_info = system_users.first.split(':')
      #Jail.cp(user_info[5])
     
      fd = File.open(@config.jail + '/etc/passwd', 'a')
      fd.puts system_users.first
      fd.close

      unless Jail.group_in_jail?(user_info[3])
        group = File.read('/etc/group').grep(/:#{user_info[3]}:/).first
        fd = File.open(@config.jail + '/etc/group', 'a')
        fd.puts group
        fd.close
      end
    end
    true
  end

  def max_uid(passwd_file)
    max = 0
    raise ArgumentError unless File.exists?(passwd_file)
    File.readlines(passwd_file).each { |l|
      pass_entry = l.split(':')
      next if pass_entry[2].to_i >= 65534
      max = pass_entry[2].to_i if pass_entry[2].to_i > max
    }
    max
  end

  # add a user to the jail that's not in the root system's /etc/passwd
  # assumes uid == gid
  def add_user_not_in_root_system(user, uid=nil)
    unless Jail.user_in_jail?(user) 
      uid ||= max_uid("#{@config.jail}/etc/passwd")+1
      fd = File.open("#{@config.jail}/etc/passwd", 'a')
      fd.puts "#{user}:x:#{uid}:#{uid}::/home/#{user}:/bin/bash"
      fd.close
      fd = File.open("#{@config.jail}/etc/group", 'a')
      fd.puts "#{user}:x:#{uid}:"
      fd.close
    end
  end

  def process(cfg)
    if cfg.kind_of?(Jail::Config)
      cfg = @config.cfg
    end
    files = []
    files += cfg[:system_binaries] if cfg[:system_binaries].kind_of?(Array)
    files +=  cfg[:other_files] if cfg[:other_files].kind_of?(Array)
    files +=  cfg[:copy_items] if cfg[:copy_items].kind_of?(Array)
    files += Jail.add_common_items
    files.each { |file| Jail.cp(file) } 
    if cfg.has_key?(:users)
      cfg[:users].each { |user| Jail.add_user(user) } if cfg[:users].kind_of?(Array)
    end

    if cfg.has_key?(:add_non_system_users)
      if cfg[:add_non_system_users].kind_of?(Array)
        cfg[:add_non_system_users].each { |user|
          add_user_not_in_root_system(user)
          user_home = "#{@config.jail}/home/#{user}"
          FileUtils.mkdir_p(user_home) unless File.directory?(user_home)
          `chroot #{@config.jail} chown #{user} #{user_home}`
        }
      end
    end

    if cfg.has_key?(:mkdir)
      if cfg[:mkdir].kind_of?(Array)
        cfg[:mkdir].each { |dir|
          d = "#{@config.jail}#{dir[:item]}"
          FileUtils.mkdir_p d unless File.directory?(d)
          if dir[:user].length > 0 && dir[:group].length > 0
            # in case the user exists in the jail but not system
            #`chroot #{@config.jail} chown #{dir[:user]}:#{dir[:group]} #{dir[:item]}`
            FileUtils.chown(dir[:user], dir[:group], d)
            FileUtils.chmod(dir[:mode], d) if dir.has_key?(:mode)
          end
        }
      
      end
    end

    if cfg.has_key?(:symlinks)
      if cfg[:symlinks].kind_of?(Array)
        cfg[:symlinks].each { |i|
          begin
            i[:force] ||= nil
            unless i.has_key?(:source) && i.has_key?(:destination)
              raise StandardError, ":source and :destination must be provided when creating a symlink" 
            end
            unless File.exists?i[:source]
              raise StandardError, ":source file/directory not found"
            end
            if i[:force]
              FileUtils.ln_sf(i[:source], "#{@config.jail}/#{i[:destination]}")
            else
              FileUtils.ln_s(i[:source], "#{@config.jail}/#{i[:destination]}")
            end
          rescue => e
            p "issue creating symlink: #{e.inspect}"
          end 
        }
      end
    end
  
    if cfg.has_key?(:chown)
      if cfg[:chown].kind_of?(Array)
        cfg[:chown].each { |i|
          begin
            FileUtils.chown_R(i[:user], i[:group], "#{@config.jail}#{i[:item]}") if File.exists?("#{@config.jail}#{i[:item]}")
          rescue => e
            p "issue chown: #{e.inspect}"
          end 
        }
      end 
    end 

    if cfg.has_key?(:chmod)
      if cfg[:chmod].kind_of?(Array)
        cfg[:chmod].each { |i|
          begin
            FileUtils.chmod(i[:mode], "#{@config.jail}#{i[:item]}") if File.exists?("#{@config.jail}#{i[:item]}")
          rescue => e
            p "issue chown: #{e.inspect}"
          end 
        }
      end 
    end 
=begin
    if cfg.has_key?(:sudo)
      if cfg[:sudo].kind_of?(Array)
        FileUtils.chmod(0600, '/etc/sudoers')
        fd = File.open("#{@config.jail}/etc/sudoers', 'w+')
        cfg[:sudo].each { |i|
          begin
            if Jail.user_in_jail?(i[:user])
              if i[:commands].kind_of?(Array)
               fd.puts "#{i[:user]} ALL=NOPASSWD:  #{i[:commands].join(',')}"
              end
            end
          rescue => e
            p "issue chown: #{e.inspect}"
          ensure
            fd.close
            FileUtils.chmod(0400, '/etc/sudoers')
          end 
        }
      end 
    end 
=end


  end

  def perform
    if Jail.create
      @config.dep_order.reverse.each { |i| process(i) }
      process(@config)
    end
  end

  module_function :create, :has_jailkit?, :cp, :exec, :add_user, :process, :perform
  module_function :user_in_jail?, :add_common_items, :group_in_jail?, :max_uid, :add_user_not_in_root_system
end

