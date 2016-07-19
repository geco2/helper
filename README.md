helper
======

snap_zfs.sh
-----------
snap_zfs create and roll over zfs snapshots. Please provide one directory stored on a zfs volume.
* Has to run as "root"
* configure the amount of snapshots you want to have within the script (MAX_SNAPSHOTS=)
* Can be used "by hand" or with cron. Example: "0 * * * * /home/andi/github/helper/snap_zfs.sh /srv"
  
*Usage: snap_zfs.sh [option] <directory>*  
  
*Options:*  
        *-h              Print this [h]elp message.*  
        *-d              [D]ebug mode on.*  
        *-n              Enable Dryru[n] mode.*  
        *-f              [F]orce mode on.*  
        *-v              Print script [v]ersion.*  
        
pkg
-----------
pkg is a simple wrapper for linux/bsd package management tools like yum/rpm,apt/dpkg...
Currently supported:
* Ubuntu
* Debian
* Fedora
* ArchLinux
* CentOS
* FreeBSD
  
*Usage: pkg [option] <package name>*  
  
*Options:*  
        *install			| -i | i	install a package*  
        *search			| -s | s 	search a package*  
        *remove			| -r | r	remove a package*  
        *update  		| -u | u	update the system*  
        *local   		| -l | l	list/search a installed package*  
        *clean-unused	| -c | c	remove unused packages* 

archive.sh
-----------
Used to OCR scan all pictures in a directory and generate *.txt files with there written content where ever missing. Useless on its own but can be combined later on ;-)

pgp
-----------
Helper/Cheat for using gpg

*Usage:*
	*-s <FILE>	Sign a file*
	*-e <FILE>	Encrypt a file*
	*-d <FILE>	Decript a file*
	*-c <FILE>	Check a signed file*

*-s create a seperate signature file called <FILE>.asc*

dba.sh (Docker Binary assistant)
-----------
dba.sh is a helper for binary placement in Docker base images.

        -a | a        Automated, to be used from within other scripts
                      No user interaction at all 
        -h | h        This text

backblaze_backup.sh
-----------
Used to remote backup encrypted archives on backblaze B2.
 Usage:
        $0  [-d|-n] <b2 vault> <archive description> <path to be backuped>

        -d      Turn on debug output
        -n      Dryrun (local opertaions only)

Example usage:
        $0 -d archive 1388904647 /backup/Backup/1388904647/

b2 credentials have to be configured for your user using b2 "authorize_account"
