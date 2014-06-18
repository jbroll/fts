#!/usr/bin/env perl
#

# pptx2txt, a command-line utility to extract the text from 
# Microsoft Office presentation files.
# Copyright (C) 2009 - Sopan Shewale - sopan.shewale@gmail.com
#                      TWIKI.NET     - sales@twiki.net  
#
# The development of this tools is completely based on other similar 
# tool called docx2txt - available at http://docx2txt.sourceforge.net/
# Big Thanks to Sandeep Kumar  (shimple0 -AT- Yahoo .DOT. COM)
# 
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
# This script extracts text from document.xml contained inside .docx file.
# Perl v5.8.2 was used for testing this script.
#
# Adjust the settings here.
#

my $unzip = "/usr/bin/unzip";
my $nl = "\n";		# Alternative is "\r\n".
my $lindent = "  ";	# Indent nested lists by "\t", " " etc.
my $lwidth = 80;	# Line width, used for short line justification.

# ToDo: Better list handling. Currently assumed 8 level nesting.
my @levchar = ('*', '+', 'o', '-', '**', '++', 'oo', '--');



my $usage = <<USAGE;

Usage:	$0 <presentation.pptx> [outfile.txt|-]

	Use '-' as the outfile name to dump the text on STDOUT.
	Output is saved in infile.txt if second argument is omitted.

USAGE

die $usage if (@ARGV == 0 || @ARGV > 2);

stat($ARGV[0]);
die "Not able to read .pptx  file <$ARGV[0]>!\n" if ! (-f _ && -r _);
die "<$ARGV[0]> The file may not be .pptx extension file!\n" if -T _;


#
# Extract needed data from argument docx file.
#

my $ic = "$unzip -p $ARGV[0]". ' "\[Content_Types\].xml"';
$_ = `$ic`;



my %slides;
while(/<Override PartName="(\/ppt\/slides\/.*?)" ContentType=".*?\/([^\/]*?slide\+xml)"?\/>/g)
{
    $slides{"$1"} = $2;
}

my $notes;
while(/<Override PartName="(\/ppt\/notesSlides\/.*?)" ContentType=".*?\/([^\/]*?notesSlide\+xml)"?\/>/g)
{
    $notes{"$1"} = $2;
}



my $command = "$unzip -p $ARGV[0] ";
foreach (keys %slides) {
        $_ =~ s/^\///;   #get ride of first backslash
        $command .= $_ . " ";
        if (/(\d+)/){ 
        my $noteskey = 'ppt/notesSlides/notesSlide'.$1 . '.xml';
        $command .=  $noteskey ." "  unless defined $notes{$noteskey};
      } 
}




my $content = `$command 2>/dev/null`;
die "Failed to extract required information from <$ARGV[0]>!\n" if ! $content;



#
# Be ready for outputting the extracted text contents.
#

if (@ARGV == 1) {
     $ARGV[1] = $ARGV[0];
     $ARGV[1] .= ".txt" if !($ARGV[1] =~ s/\.pptx$/\.txt/);
}

my $txtfile;
open($txtfile, "> $ARGV[1]") || die "Can't create <$ARGV[1]> for output!\n";


#
# Gather information about header, footer, hyperlinks, images, footnotes etc.
#

$_ = `$unzip -p '$ARGV[0]' ppt/_rels/presentation.xml.rels 2>/dev/null`;

while (/<Relationship Id="(.*?)" Type=".*?\/([^\/]*?)" Target="(.*?)"( .*?)?\/>/g)
{
    $docurels{"$2:$1"} = $3;
}


#
# Subroutines for center and right justification of text in a line.
#

sub cjustify {
    my $len = length $_[0];

    if ($len < ($lwidth - 1)) {
        my $lsp = ($lwidth - $len) / 2;
        return ' ' x $lsp . $_[0];
    } else {
        return $_[0];
    }
}

sub rjustify {
    my $len = length $_[0];

    if ($len < $lwidth) {
        return ' ' x ($lwidth - $len) . $_[0];
    } else {
        return $_[0];
    }
}

#
# Subroutines for dealing with embedded links and images
#

sub hyperlink {
    return "{$_[1]}[HYPERLINK: $docurels{\"hyperlink:$_[0]\"}]";
}


#
# Text extraction starts.
#

$content =~ s/<?xml .*?\?>(\r)?\n//;

$content =~ s{<w:p [^/>]+?/>|</w:p>}|$nl|og;
$content =~ s|<w:br/>|$nl|og;
$content =~ s|<w:tab/>|\t|og;

my $hr = '-' x 78 . $nl;
$content =~ s|<w:pBdr>.*?</w:pBdr>|$hr|og;

$content =~ s|<w:numPr><w:ilvl w:val="([0-9]+)"/>|$lindent x $1 . "$levchar[$1] "|oge;

#
# Uncomment either of below two lines and comment above line, if dealing
# with more than 8 level nested lists.
#

# $content =~ s|<w:numPr><w:ilvl w:val="([0-9]+)"/>|$lindent x $1 . '* '|oge;
# $content =~ s|<w:numPr><w:ilvl w:val="([0-9]+)"/>|'*' x ($1+1) . ' '|oge;

$content =~ s{<w:caps/>.*?(<w:t>|<w:t [^>]+>)(.*?)</w:t>}/uc $2/oge;

$content =~ s{<w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t>(.*?)</w:t></w:r>}/cjustify($1)/oge;

$content =~ s{<w:pPr><w:jc w:val="right"/></w:pPr><w:r><w:t>(.*?)</w:t></w:r>}/rjustify($1)/oge;

$content =~ s{<w:hyperlink r:id="(.*?)".*?>(.*?)</w:hyperlink>}/hyperlink($1,$2)/oge;

$content =~ s/<.*?>//g;


#
# Convert non-ASCII characters/character sequences to ASCII characters.
#

# $content =~ s/\xE2\x82\xAC/\xC8/og;	# euro symbol as saved by MSOffice
$content =~ s/\xE2\x82\xAC/E/og;	# euro symbol expressed as E

$content =~ s/\xE2\x80\xA6/.../og;
$content =~ s/\xE2\x80\xA2/::/og;	# four dot diamond symbol
$content =~ s/\xE2\x80\x9C/"/og;
$content =~ s/\xE2\x80\x99/'/og;
$content =~ s/\xE2\x80\x98/'/og;
$content =~ s/\xE2\x80\x93/-/og;

$content =~ s/\xC2\xA0//og;

$content =~ s/&amp;/&/ogi;
$content =~ s/&lt;/</ogi;
$content =~ s/&gt;/>/ogi;


#
# Write the extracted and converted text contents to output.
#

print $txtfile $content;
close $txtfile;

