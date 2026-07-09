#! /usr/bin/perl
# Copyright 1994-2000, Cunningham & Cunningham, Inc.
# in collaboration with Dave W. Smith
# Open Source for personal use only.
# ... and then only
# with the understanding that the owner(s) cannot be
# responsible for any behavior of the program or
# any damages that it may cause. See LICENSE.TXT

#use strict;

$|++;  # OUTPUT_AUTOFLUSH (if $| is non-zero)
print "Content-type: text/html\n\n";

my $mark = "\263";
my $link = "[A-Z][a-z0-9]+([A-Z][a-z0-9]+)+";

my $page = $ENV{QUERY_STRING} =~ /^($link)$/
 ? $1
 : "WelcomeVisitors";  # $& is the last match
 
my %par;
$par{page} = $page;
$par{title} = $page;
$par{title} =~ s/(.)([A-Z])/$1 $2/g;

my $body, $date;
if ( -e "pages/$page" ) {
 open(F, "pages/$page") or die "$page: $!";
 my $nl = $/; undef $/;
 $_ = <F>;  # redone from line-by-line read
 close(F);
 if ( /$mark/ ) {
  my %bla = split /$mark/, $_ ;
  $_ = $bla{text};  # convert hidden-field page to plain
  }  # if-part same as in edit
 $/ = $nl;

 $body = &FormatBody($_);
 $date = &mdy (-M "pages/$page");

 } else {
 $body = << "";
  "$page" does not yet exist. <BR>
  Use the <strong>Edit</strong> button to create it.

}

$par{summary} = " -- Last edited $date" if $date;
$par{body} = $body;
$par{action} = << "";
 <form method=post action="edit.cgi?$page">
 <input type=submit value=" Edit ">
 </form>

open (T, 'template.html') || die "template.html: $!";
undef $/;  # $nl still valid
$_ = <T>;
close (T);
s/\$(\w+)/defined($par{$1}) ? $par{$1} : ''/geo;
print;
$/ = $nl;

# ---

sub FormatBody {
 local $_ = shift @_;
 @code= ();
 my $body = '';
 s/&/&amp;/g;
 s/</&lt;/g;
 s/>/&gt;/g;

 my $hnum = 0;  # initialized for AsHiddenLink
 my $protocol = "(?:http|ftp|mailto|file|gopher|telnet|news)";
 foreach (split(/\n/, $_)) {  # -v- do each explicit souce row

  $InPlaceUrl=0;
  while (s/\b(javascript):\S.*/$mark$InPlaceUrl$mark/) {
   $InPlaceUrl[$InPlaceUrl++] = $&
   }
  while (s/\b$protocol:[^\s\<\>\[\]"'\(\)]*[^\s\<\>\[\]"'\(\)\,\.\?]/$mark$InPlaceUrl$mark/) {
   $InPlaceUrl[$InPlaceUrl++] = $&
   }

# -v- emitcode block-tag section
  $code = '';
  s/^\t+//;  # legacy pages with tab indented lists
  s/^\s*$/<p>/    && ($code = "...");
  /^\s/           && ($body .= &EmitCode('PRE', 1));

# - new list versions take left-edge multiple * or #
  s/^(\*+)/<li>/  && ($body .= &EmitCode('UL', length $1));
  s/^(\#+)/<li>/  && ($body .= &EmitCode('OL', length $1));
# - allow left-edge : version of definition list, non-tabbed, non-greedy
  s/^(:+)(.+?):( +)/<dt>$2<dd>/  && ($body .= &EmitCode(DL, length $1));
# - allow and transform literal "n." ordered lists, left-edge, one level
  s/^(\d+)\./<li>/  && ($body .= &EmitCode(OL, 1));

  s/^!!!!//       && ($body .= &EmitCode('H4', 1));
  s/^!!!//        && ($body .= &EmitCode('H3', 1));
  s/^!!//         && ($body .= &EmitCode('H2', 1));
  s/^\"\"//       && ($body .= &EmitCode('BLOCKQUOTE', 1));

  $code  || ($body .= &EmitCode('', 0));

# -v- inline tag section
  s/^-----*/<hr>/;

  s/'{3}(.*?)'{3}/<strong>$1<\/strong>/g;
  s/'{2}(.*?)'{2}/<em>$1<\/em>/g;

  s/\[Search\]/<form action=search.cgi><input type=text name=search size=40>
   <input type="submit" value="Search"><\/form>/g;

  s/\b$link\b/&AsAnchor($&)/geo;  # $& = entire matched string
  s/$mark(\d+)$mark/&InPlaceUrl($1)/geo;

  $body .= "$_\n";
  }  #-- end foreach

 $body .= &EmitCode("", 0);
 return $body;
 }

sub EmitCode {
 my $depth;
 ($code, $depth) = @_;
 my $tags = '';
 while (@code > $depth) {
  $tags .= "</" . (pop @code) . ">\n<p>";
  }
 while (@code < $depth) {
  push @code, $code;
  $tags .= "<$code>";
  }
 if ($code[$#code] ne $code) {
  $tags .= "</$code[$#code]>\n<$code>";  # split with \n
  $code[$#code] = $code;
  }
 return $tags;
 }

sub AsAnchor {
 my $title = shift @_;
 -e "pages/$title"
  ? "<a href=wiki.cgi?$title>$title<\/a>"
  : "<a href=edit.cgi?$title>?<\/a>$title";
 }

sub InPlaceUrl {
 my $num = shift @_;
 my $ref = $InPlaceUrl[$num];
 $ref =~ s/^(javascript.{30}).*/$1 .../;
 $ref =~ /\.(gif|jpeg|jpg|png)$/i
  ? "<img src=\"$ref\">"
  : "<a href=\"$InPlaceUrl[$num]\">$ref<\/a>";
 }

sub mdy {
 my $time = shift @_;
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($^T - ($time * 24 * 60 * 60));
 my $month = ('January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December')[$mon];
  $year += 1900 if $year < 1900;
 return "$month $mday, $year";
 }
