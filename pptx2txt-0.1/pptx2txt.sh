#!/usr/bin/env bash

# pptx2txt, a command-line utility to convert Pptx documents to text format.
# Copyright (C) 2009 - Sopan Shewale - sopan.shewale@gmail.com
#                      TWIKI.NET     - sales@twiki.net  
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

#
# A simple .pptx to .txt converter
#
# This script is a wrapper around core pptx2txt.pl and saves text output for
# (filename or) filename.pptx in filename.txt .
#
# ChangeLog :
#
#    28/05/2015 - Initial version (0.1) from a Sandeep Kumar 's work about xlsx2txt.sh
#


MYLOC=`dirname "$0"`	# invoked perl script xlsx2txt.pl is expected here.

function usage ()
{
    echo -e "\nUsage : $0 <file.pptx>\n"
    exit 1
}

[ $# != 1 ] && usage

if ! [ -f "$1" -o -r "$1" ]
then
    echo -e "\nCan't read input file <$1>!"
    exit 1
fi


TEXTFILE="$1.txt" 

#
# $1 : filename to check for existence
# $2 : message regarding file
#
function check_for_existence ()
{
    if [ -f "$1" ]
    then
        read -p "overwrite $2 <$1> [y/n] ? " yn
        if [ "$yn" != "y" ]
        then
            echo -e "\nPlease copy <$1> somewhere before running the script.\n"
            echeck=1
        fi
    fi
}

echeck=0
#check_for_existence "$TEXTFILE" "Output text file"
[ $echeck -ne 0 ] && exit 1

#
# Invoke perl script to do the actual text extraction
#

/usr/bin/env perl -X "$MYLOC/pptx2txt.pl" "$1" > "$TEXTFILE"
if [ $? == 0 ]
then
    echo "Text extracted from <$1> is available in <$TEXTFILE>."
else
    echo "Failed to extract text from <$1>!"
fi

