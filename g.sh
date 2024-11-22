#!/usr/bin/env sh
#while getopts ab:c:D: opt
#do
#   case $opt in
#       a) echo "Option a";;
#       b) echo "Option b";;
#       c) echo "Option c : ($OPTARG)";;
#       D) echo "Option D : ($OPTARG)";;
#   esac
#done

set -e
#var="hans"
a=${var-default}
echo $a #liefert als Output: default
var="hans"
a=${var-default}
echo $a #liefert als Output: hans


#git clone ${upstream_git_url:-https://github.com/moodle/moodle.git} "$upstream_path"
