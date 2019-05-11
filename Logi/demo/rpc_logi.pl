#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN QR_HOME);
	push @INC, "$QR_CGIROOT";
	push @INC, "$QR_BIN";
	push @INC, "$QR_ROOT";

}

use strict;

use Env qw(QR_ROOT QR_CGIROOT REMOTE_USER QR_BIN QR_HOME);

$QR_CGIROOT="." if !$QR_CGIROOT;
$QR_ROOT=".." if !$QR_ROOT;

my $QR_MANDANT=substr($REMOTE_USER, 0, 4);

my $SCRIPTS="$QR_CGIROOT";


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

use Logi::rpc::rpc qw(rpc_logisthai); 


my $FH_DBG;


# setlocale(LC_CTYPE, "de_DE.utf8");
setlocale LC_NUMERIC, "de_DE.utf8";

$ENV{'LC_ALL'} = "de_DE.utf8";


my $debug_level=2;

my $periode="";
my $email="";
my $jahr="";
my $buchcode="";
my $steuercode="";
my $belegnr="";
my $start_belegnr;
my $buchsymbol="";
my $buchdatum="";
my $buchdatum_first_day="";
my $buchtype="";	# 1 ER; 2 AR; 3 KA
my $gkonto="";		# kann auch "" sein
my $kundennr="";
my $bereich;
my $satzart=0;
my $verbose="";
my $e_a= "";
my $transaction_id="";
my $do_skonto=0;
my $rerun_timestamp=0;
my $rerun_file="";
my $tessopt1;;
my $no_sort=0;
my $with_empty_pages=0;
my $with_ocr_file="";
my $no_tesseract=0;
my $no_ust=0;
my $denoise="";
my $pid="";
my $myuid="";
my $input_csv_file="";
my $comment="";
my $anz_rg_in=0;
my $customer=0;
my $gvision=1;


my @all_file_arr;
my @single_invoices=();
my @process_empty_pages=();





################################################################################
########################### MAIN
################################################################################

my $rpc;

my $result = GetOptions (
		"buchcode=i" => \$buchcode,    # numeric
		"steuercode=i" => \$steuercode,    # numeric
		"belegnr=i" => \$belegnr,    # numeric
		"gkonto=i" => \$gkonto,    # numeric
		"kundennr=i" => \$kundennr,    # numeric
		"pid=i" => \$pid,    # numeric
		"buchsymbol=s"   => \$buchsymbol,      # string
		"buchtype=i"   => \$buchtype,      # string
		"buchdatum=s"   => \$buchdatum,      # string
		"kommentar=s"   => \$comment,      # string
		"rechnungen=i"   => \$anz_rg_in,      # numeric
		"transaction=i"   => \$transaction_id,      # numeric
		"stat=i"   => \$transaction_id,      # 2nd statusfile
		"debug_level=i"   => \$debug_level,      # numeric
		"timestamp=i"   => \$rerun_timestamp,      # numeric
		"customer=i"   => \$customer,      # numeric
		"bereich=s"   => \$bereich,      # string
		"uid=s"   => \$myuid,      # string
		"csv=s"   => \$input_csv_file,      # string
		"periode=s"   => \$periode,      # string
		"email=s"   => \$email,      # string
		"jahr=i"   => \$jahr,      # string
		"denoise"   => \$denoise,      # flag
		"with_ocr_file"   => \$with_ocr_file,      # flag
		"no_sort"   => \$no_sort,      # flag
		"no_tesseract"   => \$no_tesseract,      # flag
		"skonto"   => \$do_skonto,      # flag
		"ust=i"   => \$no_ust,      # flag
		"ustermittlung=i"   => \$no_ust,      # flag
		"e_a=i"   => \$e_a,      # flag
		"gewinnermittlung=i"   => \$e_a,      # flag
		"tessopt1"   => \$tessopt1,      # flag
		"QR_ROOT"   => \$QR_ROOT,      # flag
		"QR_CGIROOT"   => \$QR_CGIROOT,      # flag
		"REMOTE_USER"   => \$REMOTE_USER,      # flag
		"rpc"   => \$rpc,      # flag
		"single_inv=i" => \@single_invoices,
		"empty_rec=i" => \@process_empty_pages,
		"verbose"  => \$verbose);  # flag

	if ($#ARGV <  0 && !$input_csv_file) {
		print "usage: ocr.pl <sourcefiles>\n";
		exit;
	}

	my %parms = (
		buchcode => $buchcode,    
		steuercode => $steuercode,    
		belegnr => $belegnr,    
		gkonto => $gkonto,    
		kundennr => $kundennr,    
		pid => $pid,    
		buchsymbol   => $buchsymbol,      
		buchtype   => $buchtype,      
		buchdatum   => $buchdatum,      
		comment   => $comment,      
		customer   => $customer,      
		anz_rg_in   => $anz_rg_in,      
		transaction_id   => $transaction_id,      
		debug_level   => $debug_level,      
		rerun_timestamp   => $rerun_timestamp,      
		myuid   => $myuid,      
		input_csv_file   => $input_csv_file,      
		periode_in   => $periode,      		# !!!
		email   => $email,      
		jahr   => $jahr,      
		denoise   => $denoise,      
		with_ocr_file   => $with_ocr_file,      
		no_sort   => $no_sort,      
		no_tesseract   => $no_tesseract,      
		do_skonto   => $do_skonto,      
		gvision   => $gvision,      
		no_ust   => $no_ust,      
		e_a   => $e_a,      
		tessopt1   => $tessopt1,      
		rpc   => $rpc,      
		single_inv => \@single_invoices,
		empty_rec => \@process_empty_pages,
		QR_ROOT   => $QR_ROOT,
		QR_CGIROOT   => $QR_CGIROOT,
		REMOTE_USER   => $REMOTE_USER,
		QR_BIN   => $QR_BIN,
		QR_HOME   => $QR_HOME,
		verbose  => $verbose);  


	my $rpc_server = "cloud09.xion.at/cgi-bin/ocr_server.pl";
	my $FH_DBG = 0;	# opt filehandle for debugfile

	my $res = rpc_logisthai ($FH_DBG, \%parms, \@single_invoices, \@process_empty_pages, \@ARGV, $rpc_server);
	#main::logisthai (\%parms, \@single_invoices, \@process_empty_pages, \@ARGV, $transaction_id);

	print "res: $res\n";
