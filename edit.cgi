#! /usr/bin/perl -w
# Copyright 1994-2000, Cunningham & Cunningham, Inc.
# Open Source for personal use only.
# ... and then only
# with the understanding that the owner(s) cannot be
# responsible for any behavior of the program or
# any damages that it may cause. See LICENSE.TXT

# use strict;
$|++;
print "Content-type: text/html\n\n";

my $link = "[A-Z][a-z0-9]+([A-Z][a-z0-9]+)+";
my $mark = "\263";

my $page = $ENV{QUERY_STRING} =~ /^$link$/
	? $&
	: "WelcomeVisitors";

if ($ENV{SERVER_SOFTWARE} =~ /quicki/i) {
 read(NS, $_, $ENV{CONTENT_LENGTH});  # needed for Quicki
 } else {
 read(STDIN, $_, $ENV{CONTENT_LENGTH});  # works in Apache
 }

my $mode = (/append/) ;

my $text = "";

if ( -e "pages/$page" ) {
	open(F, "pages/$page") or die "$page: $!";
	undef $/;
	$_ = <F>;
	close(F);
	if ( /$mark/ ) {
	 my %bla = split /$mark/, $_ ;
	 $_ = $bla{text};  # convert hidden-field page to plain
	 }
	s/&/&amp;/g;
	s/</&lt;/g;
	s/>/&gt;/g;
	$text = $_;
	$/ = "\n";
}


my %par;
if ( $mode ) {
 $par{title} = "Add comment to $page";
 $text = "";
 $mode = "append"
 } else {
 $par{title} = "Edit $page";
 $mode = "edit";
 }
$par{page} = $page;
$par{body} = << "";
	<form method=post action="save.cgi?$page">
	<textarea name=Text rows=16 cols=60 wrap=virtual>$text</textarea>
	<p><input type="submit" value=" Save ">
      <input type="hidden" name="mode" value="$mode">
	</form>

open(T, 'template.html') or die "template.html: $!";
undef $/;
$_ = <T>;
close(T);
s/\$(\w+)/defined($par{$1}) ? $par{$1} : ''/geo;
print;
$/ = "\n";

