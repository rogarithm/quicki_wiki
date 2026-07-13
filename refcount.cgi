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
print "Content-type: text/html; charset=UTF-8\n\n";

my $link = "[A-Z][a-z0-9]+([A-Z][a-z0-9]+)+";

opendir(DIR, 'pages') or die "pages: $!";
my @files = grep /^$link$/, readdir(DIR);
closedir(DIR);

my %refs = ();

my $file;
foreach $file ( @files ) {
 open(F, "pages/$file") or die "$file: $!";
 undef $/;
 my $contents = <F>;
 close(F);

 my %targets = ();
 while ( $contents =~ /($link)/g ) {
  $targets{$1} = $file;
  }
 my $target;
 foreach $target ( keys %targets ) {
  push @{$refs{$target}}, $file;
  }
 }

my %refcnt = ();
foreach $file ( @files ) {
 $refcnt{$file} = defined $refs{$file} ? scalar @{$refs{$file}} : 0;
 }

@files = sort { $refcnt{$b} <=> $refcnt{$a} || $a cmp $b } @files;

my $body = "<table border=0 cellspacing=0 cellpadding=0>\n";
foreach $file ( @files ) {
 $body .= "<tr>";
 $body .= "<td valign=right>$refcnt{$file}</td>";
 $body .= "<td>&nbsp;&nbsp;<a href=wiki.cgi?$file>$file</a></td>";
 $body .= "</tr>\n";
 }
$body .= "</table>\n";

my %par;
$par{summary} = "";
$par{title} = "Page References";
$par{page} = "http:pagerefs.cgi";
$par{body} = $body;

open(T, "template.html") or die "template.html: $!";
undef $/;
$_ = <T>;
close(T);
s/\$(\w+)/defined($par{$1}) ? $par{$1} : ''/geo;
print;
$/ = "\n";
