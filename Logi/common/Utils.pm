#!/usr/bin/perl -s

package Logi::common::Utils;

my $debug_level=2;

use strict;
use Math::Round;
use POSIX qw(strtod setlocale LC_NUMERIC);
use locale;
use List::Util qw(sum);
use Exporter qw(import);
our @EXPORT_OK = qw(debug init_debug close_debug mean form uniq convert_special_chars remove_t_sep);



#my $FH_DBG;	# debug file handle

################################################################################


sub debug {
	my $FH = shift;		# filehandle to use
	my $level = shift;

	return if $level>$debug_level;
	return if !$FH;


	print $FH "($level) " if ($debug_level > 1); 

	# my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	# printf ($FH, "%04d%02d%02d %02d:%02d:%02d ", $year+1900,$mon+1,$mday,$hour,$min, $sec);

	foreach my $v (@_) {
		print $FH "$v";
	}
	print $FH "\n";
	setlocale LC_NUMERIC, "de_DE";
}

sub close_debug {
	my $FH_DBG = shift;
	close $FH_DBG;
}

################################################################################
# remove tausender sep oder blanks zwischen zahlen

sub remove_t_sep {
        my $inp=shift;
        $inp =~ /(.*)[,\.\h-](\d+|-)$/;
	my $zahl=$1;
	my $nk=$2;
	$zahl =~ s/[;,\.\h]//g;
	$zahl = "$zahl.$nk";
	my $neu = sprintf "%.02f", $zahl;
	return $neu;
}
################################################################################

sub init_debug {
	my $debugfile = shift;
		
	my $lvl = shift;

	$debug_level = $lvl;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();


	open (my $FH_DBG, '>', $debugfile) or die "Could not open file '$debugfile' $!";
	debug $FH_DBG, 1, "********************************************************************************";
	debug $FH_DBG, 1, sprintf ("%04d-%02d-%02d %02d:%02d:%02d",
		$year+1900,$mon+1,$mday,$hour,$min, $sec), " Utils debug open: $debug_level";

	return $FH_DBG;


}

################################################################################

sub form {
	my $val=shift;

#	debug 3, "form: ret: ", sprintf ("%.02f", round ($val*100)/100), "val: <$val>/", $val+0;
	return sprintf ("%.02f", round ($val*100)/100);
}


################################################################################
sub uniq {
	my %seen;
        grep !$seen{$_}++, @_;
}

################################################################################

sub mean {
    return sum(@_)/@_;
}

sub convert_special_chars {
	my $text = shift;

	$text =~ s/\x30\x0a/E/gx;	# EURO nicht norm

	$text =~ s/\xe2\x80/,/gx;	# dezimalzeichen
	$text =~ s/\xc2\x80/E/gx;	# EURO
	$text =~ s/\x0a\x30/E/gx;	# EURO	aus tesseract? norm?
	$text =~ s/\xc3\x96/O/gx;	# umlaut O
	$text =~ s/\xc3\x9c/U/gx;	# umlaut U
	$text =~ s/\xc3\x84/A/gx;	# umlaut A
	$text =~ s/\xc3\xb6/o/gx;	# umlaut o
	$text =~ s/\xc3\xbc/u/gx;	# umlaut u
	$text =~ s/\xc3\xa4/a/gx;	# umlaut a
	$text =~ s/\xc3\x9f/s/gx;	# umlaut s

	$text =~ s/[\x00-\x19\x80-\xff]//g;	# Rest weg

	return $text;
}

1;
