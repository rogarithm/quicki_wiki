#! /usr/bin/perl -w
# Copyright 1994-2000, Cunningham & Cunningham, Inc.
# in collaboration with Dave W. Smith
# Open Source for personal use only.
# ... and then only
# with the understanding that the owner(s) cannot be
# responsible for any behavior of the program or
# any damages that it may cause. See LICENSE.TXT

# use strict;
$|++;
print "Content-type: text/html\n\n";

my $link = "[A-Z][a-z0-9]+([A-Z][a-z0-9]+)+";

my ($target) = $ENV{QUERY_STRING} =~ /search=([^\&]*)/;
$target =~ s/\+/ /g;
$target =~ s/\%(..)/pack('C', hex($1))/geo;

my $pat = $target;
$pat =~ s/[+?.*()[\]{}|\\]/\\$&/g;
$pat = "\\b\\w*($pat)\\w*\\b";

$target =~s/"/&quot;/g;
my $body = <<EOF;
 <form action=search.cgi>
  <input
   type="text"
   size="40"
   name="search"
   value="$target">
  <input type="submit" value="Search">
 </form>
EOF

opendir(DIR, 'pages') or die "pages: $!";
my @files = sort grep /^$link$/, readdir(DIR);
closedir(DIR);

my ($file, $hits);
foreach $file ( @files ) {
	open(SF, "pages/$file") or die "$file: $!";
	undef $/;
	my $contents = <SF>;
	close(SF);
	if ($file =~ /$pat/i || $contents =~ /$pat/i) {
		$hits++;
		$body .= "<a href=wiki.cgi?$file>$file<\/a> . . . . . .  $&<br>\n";
	}
}

my %par;
$par{summary} = ($hits || "No") . " pages found out of " . scalar @files . " pages searched.";
$par{title} = "Search Results";
$par{page} = "WelcomeVisitors";
$par{body} = $body;

open(T, "template.html") or die "template.html: $!";
undef $/;
$_ = <T>;
close(T);
s/\$(\w+)/defined($par{$1}) ? $par{$1} : ''/geo;
print;
$/ = "\n";
