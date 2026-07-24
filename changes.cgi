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
my @datedpages = sort {$a->[0] <=> $b->[0]}
                 map  { [-M "pages/$_", $_] }
                 grep /^$link$/,  readdir(DIR);
closedir(DIR);

my $max = $ENV{QUERY_STRING} =~ /\bmax=(\d+)/ ? $1 : 25;

my $body = "<dl>\n";
my $lastdate;
foreach ( @datedpages ) {
    my $time = $_->[0];
    my $file = $_->[1];
    my $date = &mdy($time);
	if ( $date ne $lastdate ) {
        $body .= "<dt>";
		$body .= defined($lastdate) ? "<br>" : "";
		$body .= $date;
        $lastdate = $date;
	}
    $body .= "<dd><a href=wiki.cgi?$file>$file</a>\n";
    last if --$max == 0;
}
$body .= "</dl>\n";

my %par;
$par{body} 	= $body;
$par{title}	= "Recent Changes";
$par{page} = "http:changes.cgi";

open(T, 'template.html') or die "template.html: $!";
undef $/;
$_ = <T>;
close(T);
s/\$(\w+)/defined($par{$1}) ? $par{$1} : ''/geo;
print;
$/ = "\n";

sub mdy {
 	my $time = shift @_;
 	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($^T - ($time * 24 * 60 * 60));
	my $month = ('January', 'February', 'March', 'April', 'May', 'June',
		'July', 'August', 'September', 'October', 'November', 'December')[$mon];
 	$year += 1900;
	return "$month $mday, $year";
}
