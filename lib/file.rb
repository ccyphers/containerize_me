# Authod: Cliff Cyphers
# Published as part of the cyberconnect's platform mainly used
# in hosting rails applications.  
# Licesnse: GPLv3: http://www.gnu.org/licenses/gpl.html


require 'fileutils'
require 'find'

module FileUtils
  def self.clone_perms(src, dest)
    if File.directory?(src) && File.directory?(dest)
      Find.find(src) { |entry|
        next if entry =~ /^\/proc/ 
        begin
          stat = File.stat(entry)
          FileUtils.chmod(stat.mode, "#{dest}#{entry}")
          FileUtils.chown(stat.uid, stat.gid, "#{dest}#{entry}")
        rescue => e
        end
      }    
    end
  end
end
