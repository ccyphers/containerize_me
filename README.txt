= containerize_me

http://cyberconnect.biz/opensource


== DESCRIPTION:

Containerize Me is intended to provide a cross distro linux means for easily defining charactieristics of a chroot jail in yaml format.  While there are other Linux tools out there aiming at delivering similar solutions often times they differ between distros.  With containerize_me it's easy to get hosting setup in chroot jail's in a matter of minutes from any Linux distro.

== FEATURES:

*  :copy_items Required YAML hash pointing to an array of files to copy over to the chroot environment.
*  :depends_on Optional YAML configuration key referencing one or more dependancies.  Dependancies may be may be nesed as many levels deep as long as there are no ciclic conditions.
* :mkdir: Optional YAML configuration key referencing an array of hashes where the has defines keys(:item, :user, :group, :mode) 


== USAGE:

      containerize_me --config <chroot yaml configuration file> --jail <full path to jail eg: /hosting/some_jail>

      where <chroot yaml configuration file> defines the charicteristics of
      the chroot environment being created.  Items, such as which files are copied
      over, and dependent yaml configuration files as well.  See the templates directory
      for examples.



== REQUIREMENTS:

* Linux
* jailkit 

== INSTALL:

* Install jailkit: http://olivier.sessink.nl/jailkit/index.html#download
* gem install containerize_me 


== LICENSE:

GPLv3: http://www.gnu.org/licenses/gpl.html
