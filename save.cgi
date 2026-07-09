#! /usr/bin/perl
# Copyright 1994-2000, Cunningham & Cunningham, Inc.
# in collaboration with Dave W. Smith
# Open Source for personal use only.
# ... and then only
# with the understanding that the owner(s) cannot be
# responsible for any behavior of the program or
# any damages that it may cause. See LICENSE.TXT

# use strict;
$|++;
# print "Content-type: text/html\n\n";  # only needed if we use thankyou page

my $mark = "\263";
my $link = "[A-Z][a-z0-9]+([A-Z][a-z0-9]+)+";

my $page = $ENV{QUERY_STRING} =~ /^$link$/
	? $&
	: die("BadSaveName\n");

if ($ENV{SERVER_SOFTWARE} =~ /quicki/i) {
 read(NS, $_, $ENV{CONTENT_LENGTH});  # needed for Quicki
 } else {
 read(STDIN, $_, $ENV{CONTENT_LENGTH});  # works in Apache
 }

my ($body, %body);
foreach $_ (split(/&/, $_)) {
	s/\+/ /g;
	s/\%(..)/pack('C', hex($1))/geo;
	($_, $body) = split (/=/, $_, 2);
	$body{$_} = $body;
}

$_ = $body{Text};
# -v- tab indentation depreciated, do not convert spaces or * to tab+*
# s/        /\t/g;
# s/^\*/\t\*/;
# s/\n\*/\n\t\*/g;

# s/\r\n/\n/g;  # replace DOS crlf with lf
# s/\r/\n/g;  # replace cr with lf
/\n/
 ? s/\r//g  # presume PC just strip cr
 : s/\r/\n/g;  # replace cr with lf

s/$mark//g;  # strip markers

# -v- autobacklink
if ( s/<<($link)\b/$1/g ) {
 open(P, ">>pages/$1") or die "$1: $!";
 print P "\n----\n$page";
 close(P);
 }

my $mode = ">pages/$page";
if ($body{mode} =~ /append/) {
 $mode = ">" . $mode;
 $_ = "\n----\n\n$_";
 }
open(F, $mode) or die "$page: $!";
print F;
close(F);

#my $RcsBin = "I:/WWW/LEUF_net/cgi-bin/bin"; # no / here
#my $path = "I:/WWW/LEUF_net/wiki5/pages" ;
#`$RcsBin/ci -l $path/$page 2>&1` ;

do "wiki.cgi" ;

#my %par;
#$par{title} = "Thank You";
#$par{page} = $page;
#$par{body} = << "";
#	The <a href=wiki.cgi?$page>$page</a> page has been saved.
#	You may <b>back</b> up to the edit form and make further changes.
#	Remember to <b>reload</b> old copies of this page and especially
#	old copies of the editor.</i>
#
#open(T, 'template.html') or die "template.html: $!";
#undef $/;
#$_ = <T>;
#close(T);
#s/\$(\w+)/defined($par{$1}) ? $par{$1} : ''/geo;
#print;
#$/ = "\n";
