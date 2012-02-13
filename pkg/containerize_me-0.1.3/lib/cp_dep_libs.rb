# Authod: Cliff Cyphers
# Published as part of the cyberconnect's platform mainly used
# in hosting rails applications.  
# Licesnse: GPLv3: http://www.gnu.org/licenses/gpl.html


require 'find'

module Jail
  def self.cp_dep_libs(src, jail_dir)
    if File.directory?(src) && File.directory?(jail_dir)
      Find.find(src) { |entry|
        next if File.directory?(entry)
        stat = File.stat(entry)
        if entry =~ /\.so/ || stat.executable?
          `jk_cp -f -j #{jail_dir} #{entry}`
        end
      }
   end
 end
end
