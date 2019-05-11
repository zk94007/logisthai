#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN HOME);
	push @INC, "$QR_ROOT";
	push @INC, "/home/andi";
}

use Logi::rpc::RemoteCall qw(call);
use Logi::rpc::Data;
use Logi::rpc::rpc;


use JSON;
use Data::Dumper;






use strict;

use POSIX qw(strtod setlocale LC_NUMERIC);
use locale;
use File::Basename;
use Math::Round;
use Getopt::Long;
use Fcntl qw ( LOCK_EX SEEK_SET );
use DateTime;
use DateTime::Format::Strptime;
use File::Copy qw(copy);
use Image::Size;
use YAML qw(LoadFile Load);

use Env qw(QR_ROOT QR_CGIROOT REMOTE_USER);

$QR_CGIROOT="." if !$QR_CGIROOT;
$QR_ROOT=".." if !$QR_ROOT;

my $QR_MANDANT=substr($REMOTE_USER, 0, 4);


my $FH_DBG;
my $buchdatum;
my $date_max;
my $date_min;
my $date_min_e_a;			# E/A Rechner
my $buchdatum_first_day;
my $myuid;

setlocale LC_NUMERIC, "de_DE.utf8";

$ENV{'LC_ALL'} = "de_DE.utf8";


my $debug_level=2;

##################################################

sub debug {
	my $level = shift;
	return if $level>$debug_level;
	print $FH_DBG "($level) " if ($debug_level > 1); 
	foreach my $v (@_) {
		print $FH_DBG "$v";
	}
	print $FH_DBG "\n";
}

##################################################

sub form {
	my $val=$_[0];
	# debug 3, "form: ret: ", sprintf ("%.02f", round ($val*100)/100);
	return sprintf ("%.02f", round ($val*100)/100);
}

##################################################

sub set_dates {
	my $buchdatum = shift;
	my $periode_in = shift;
	my $jahr = shift;
	my $is_quartal = shift;


	my $strp = DateTime::Format::Strptime->new(
			pattern   => '%d.%m.%Y',
			);

	my $d;
	my $date_max;


	# datum als parm oder akt. datum
	my $periode = 0;

	if ($periode_in && $jahr) {
		if ($periode_in =~/^q(\d)/i) {
			$periode = $1*3;
			$is_quartal = $1 ;
		} else {
			$periode = $periode_in;
		}
		$d = DateTime ->last_day_of_month(year=>($jahr), month=>($periode));
	} elsif ($buchdatum) {
		$d = $strp->parse_datetime($buchdatum) or die "wrong buchdatum $buchdatum";
		$periode = $d->month;
	} else {
		$d = DateTime->today;
		$periode = $d->month;
	}


	$date_max = DateTime ->last_day_of_month(year=>($d->year), month=>($d->month));


	my $date_min_e_a = $date_max->clone;
	$date_min_e_a->subtract(days=>$date_max->day-1);



	my $date_min = $date_max->clone;
	$date_min->subtract(days => 365);

	$buchdatum = sprintf ("%02d.%02d.%04d", 
			$date_max->day, 
			$date_max->month, 
			$date_max->year);

	my $date_min_e_a_string = sprintf ("%02d.%02d.%04d", 
			$date_min_e_a->day, 
			$date_min_e_a->month, 
			$date_min_e_a->year);
	my $date_min_string = sprintf ("%02d.%02d.%04d", 
			$date_min->day, 
			$date_min->month, 
			$date_min->year);

	my $buchdatum_first_day = sprintf ("%02d.%02d.%04d", 
			$date_min_e_a->day, 
			$date_min_e_a->month, 
			$date_min_e_a->year);



	my ($day,$mon, $year) = split (/\./, $buchdatum);


	return ($periode, $is_quartal, $buchdatum, $buchdatum_first_day, $date_min_string, $date_min_e_a_string);
}

##################################################

my $pdf_file="";
my $my_uid="";
my $e_a=0;
my $verbose;
my $buchtype;	# 1 ER; 2 AR; 3 KA
my $kundennr;
my $buchsymbol;

my $result = GetOptions (
		"debug_level=i"   => \$debug_level,      # numeric
		"uid=s"   => \$myuid,      # string
		"buchdatum=s"   => \$buchdatum,      # string
		"buchsymbol=s"   => \$buchsymbol,      # string
		"buchtype=i"   => \$buchtype,      # string
		"buchdatum=s"   => \$buchdatum,      # string

		"pdf_file"   => \$pdf_file,      # flag
		"e_a"   => \$e_a,      # flag
		"verbose"  => \$verbose);  # flag

	if ($#ARGV <  0) {
		print "usage: ocr.pl <sourcefiles>\n";
		exit;
	}
	my $start_time_sec = time();




my @input_files = @ARGV;		# ohne page sep
my $source_files = join (' ', @_);	# array of inputfiles

my $debug_file = "ocr_client.dbg";
open ($FH_DBG, '>>', $debug_file) or die "Could not create debug file $debug_file";
debug 1, "********************************************************************************";

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
my $current_date=sprintf ("%04d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min, $sec);

debug 1, "debug opened $current_date debug_level: $debug_level";

	# $myuid = uid::initialize ($FH_DBG, $kundennr, $buchtype, $buchsymbol);

	my $pid=$$;
	my $add_missing_mwst=0;
	my $barcode="";
	my @tess_files = @ARGV;
	my $rg_nr = 1111;
	my $all_file_path=".";
	my $file_praefix = sprintf ("$all_file_path/rg_%04d_%d", $rg_nr, $pid);

	$buchtype=3 if !$buchtype;
	$buchsymbol="KA" if !$buchsymbol;
	$kundennr = "288888" if !$kundennr;
	$myuid="ATU12345678" if !$myuid;

	my ($periode, $is_quartal, $date_max, $buchdatum_first_day, $date_min, $date_min_e_a_string) =  set_dates ($buchdatum, 9, 2018, 0);

	my $last_date = $buchdatum_first_day;

	my ($datum, $belegnr, $uid, $url, $email, $skonto_proz, $status, $supplier, $coords, $ocr_string, $result_values_aref) = 
		rpc_process_rechnung ($FH_DBG, "", 1, "", $date_min, $date_max, $myuid, 1, "", 2, "1234", \@ARGV, "http://cloud09.xion.at/cgi-bin/server.pl");

	for my $index (0 .. scalar $#$result_values_aref) {

		my ($proz, $netto, $mwst, $brutto, $metro_konto) = @{$result_values_aref->[$index]};
		print "working on <$proz> <$netto> <$mwst> <$brutto>\n";
	}



debug 1, "debug closed $current_date";
