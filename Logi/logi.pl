#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN QR_HOME);
	push @INC, "$QR_CGIROOT";
	push @INC, "$QR_BIN";
	push @INC, "$QR_ROOT";

}

use Env qw(QR_ROOT QR_CGIROOT REMOTE_USER QR_BIN QR_HOME);

use strict;

$QR_CGIROOT="." if !$QR_CGIROOT;
$QR_ROOT=".." if !$QR_ROOT;

my $QR_MANDANT=substr($REMOTE_USER, 0, 4);

my $SCRIPTS="$QR_CGIROOT";


use POSIX qw(strtod setlocale LC_NUMERIC);
use Data::Dumper;
use Math::Round;
use File::Basename;
#use Logi::Logi::main_new;
use Getopt::Long;
use Logi::rpc::rpc qw(rpc_logisthai); 

setlocale LC_NUMERIC, "de_DE.utf8";

$ENV{'LC_ALL'} = "de_DE.utf8";

my $FH_DBG;
my $debug_level=2;

	my %parms = (
		buchcode => "",    
		steuercode => "",    
		belegnr => "",    
		gkonto => "",    
		kundennr => "",    
		pid => "",    
		buchsymbol   => "",      
		buchtype   => "",      
		buchdatum   => "",      
		comment   => "",      
		customer   => 0,      
		anz_rg_in   => "",      
		transaction_id   => "",      
		debug_level   => 2,      
		rerun_timestamp   => 0,      
		myuid   => "",      
		input_csv_file   => "",      
		periode_in   => "",      		# !!!
		email   => "",      
		jahr   => "",      
		denoise   => "",      
		with_ocr_file   => "",      
		no_sort   => 0,      
		no_tesseract   => 0,      
		do_skonto   => 0,      
		gvision   => 1,      
		no_ust   => 0,      
		e_a   => 0,      
		tessopt1   => "",      
		rpc   => 0,      
		QR_ROOT   => $QR_ROOT,
		QR_CGIROOT   => $QR_CGIROOT,
		REMOTE_USER   => $REMOTE_USER,
		QR_BIN   => $QR_BIN,
		QR_HOME   => $QR_HOME,
		verbose  => "");  


sub debug {
	my $level = shift;
	return if $level>$debug_level;

	print $FH_DBG "($level) " if ($debug_level > 1);
	foreach my $v (@_) {
		print $FH_DBG "$v";
	}
	print $FH_DBG "\n";
}

use constant STATUS_RPC => 0;
use constant STATUS_INIT => 1;
use constant STATUS_RUNNING => 2;
use constant STATUS_GENERATE_FILES => 3;
use constant STATUS_BUNDLE => 4;
use constant STATUS_FIN => 99;
use constant STATUS_DIE => 999;



sub write_status {

	my $status_file = $parms{rpc_status_file};

	open (my $FH_STATUS, '>>', $status_file) or return 0;


	my ($state, $current_fileno, $number_files, $text) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();

	my $status_entry = sprintf "%04d-%02d-%02d %02d:%02d:%02d;$$;$state;$current_fileno;$number_files;$text\n",
		$year+1900,$mon+1,$mday,$hour,$min, $sec;
	printf $FH_STATUS $status_entry;

	close ($FH_STATUS);

}



sub my_die {
	debug 1, "ERROR: ", @_;
	write_status (STATUS_DIE, 0, 0,  "ERROR: @_");

	exit;
}

sub read_input_csv_file {
	my $input_csv_file = shift;

	my %tmp_filelist = ();
	my %tmp_barcodes=();

	open (my $FH_INPUT_CSV, '<', $input_csv_file) or my_die "Could not open csv file $input_csv_file";

	my $last_rg_nr=1;
	my $input_line=1;
	while (<$FH_INPUT_CSV>) {

		chop;
		my ($rg_nr, $source_file, $page, $page_img, $flag, $qrcode) = split /;/;


		next if $flag ne "P";		# no page / deleted ...

		my_die "rechnungsnummern nicht fortlaufend: file $input_csv_file line $input_line rgnr: $rg_nr" if $rg_nr != $last_rg_nr && $rg_nr-1 != $last_rg_nr;

		my_die "Filename $source_file does not exists or not readable" if ! -f $source_file;
		my_die "Filename $source_file not tiff/pdf" if $source_file !~ /\.(pdf|tif+)$/i;

		$page = $rg_nr if !$page;		# sollte nicht passieren
		push @{$tmp_filelist{$source_file}{$rg_nr}}, $page;
		$tmp_barcodes{$rg_nr} .= $qrcode if $qrcode;

		#die "Filename $page_img not tiff" if $page_img !~ /\.tif+$/i;
		#my_die "Filename $page_img does not exists" if ! -f $page_img;

		$last_rg_nr = $rg_nr;
		$input_line++;

	}

	close $FH_INPUT_CSV;
	return (\%tmp_filelist, \%tmp_barcodes);
}









################################################################################
########################### MAIN
################################################################################



my $result = GetOptions (
		"buchcode=i" => \$parms{buchcode},    # numeric
		"steuercode=i" => \$parms{steuercode},    # numeric
		"belegnummer=i" => \$parms{belegnr},    # numeric
		"belegnr=i" => \$parms{belegnr},    # numeric
		"gkonto=i" => \$parms{gkonto},    # numeric
		"kundennr=i" => \$parms{kundennr},    # numeric
		"pid=i" => \$parms{pid},    # numeric
		"buchsymbol=s"   => \$parms{buchsymbol},      # string
		"buchtype=i"   => \$parms{buchtype},      # string
		"buchdatum=s"   => \$parms{buchdatum},      # string
		"kommentar=s"   => \$parms{comment},      # string
		"rechnungen=i"   => \$parms{anz_rg_in},      # numeric
		"transaction=i"   => \$parms{transaction_id},      # numeric
		"stat=i"   => \$parms{transaction_id},      # 2nd statusfile
		"debug_level=i"   => \$parms{debug_level},      # numeric
		"timestamp=i"   => \$parms{rerun_timestamp},      # numeric
		"customer=i"   => \$parms{customer},      # numeric
		"bereich=s"   => \$parms{bereich},      # string
		"uid=s"   => \$parms{myuid},      # string
		#"csv=s"   => \$parms{input_csv_file},      # string
		"csv=s"   => \$parms{remote_csv_file},      # string
		"remote_csv=s"   => \$parms{remote_csv_file},      # string
		"periode=s"   => \$parms{periode_in},      # string
		"email=s"   => \$parms{email},      # string
		"jahr=i"   => \$parms{jahr},      # string
		"denoise"   => \$parms{denoise},      # flag
		"with_ocr_file"   => \$parms{with_ocr_file},      # flag
		"no_sort=i"   => \$parms{no_sort},      # flag
		"no_tesseract"   => \$parms{no_tesseract},      # flag
		"skonto"   => \$parms{do_skonto},      # flag
		"ust=i"   => \$parms{no_ust},      # flag
		"ustermittlung=i"   => \$parms{no_ust},      # flag
		"e_a=i"   => \$parms{e_a},      # flag
		"gewinnermittlung=i"   => \$parms{e_a},      # flag
		"tessopt1"   => \$parms{tessopt1},      # flag
		"rpc"   => \$parms{rpc},      # flag
		"single_inv=i" => \@{$parms{single_invoices}},
		"empty_rec=i" => \@{$parms{process_empty_pages}},
		"verbose"  => \$parms{verbose});  # flag

	if ($#ARGV <  0 && !$parms{input_csv_file} && !$parms{remote_csv_file}) {
		print "usage: logi.pl <sourcefiles>\n";
		exit;
	}

	umask (0000);






	#print Dumper(\%parms);
	#
	$debug_level = $parms{debug_level} if $parms{debug_level};

	my $debug_file = "$QR_ROOT/logs/logi.dbg";
	open ($FH_DBG, '>>', $debug_file) or my_die ("Could not create debug file $debug_file");

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $current_date=sprintf ("%04d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min, $sec);

	debug 1, "debug opened $current_date debug_level: $parms{debug_level} $parms{kundennr}/$parms{buchsymbol} $parms{remote_csv_file}";
	debug 1, "start: ", Dumper(\%parms);

	my $STATUSDIR="$parms{QR_ROOT}/status";

	$parms{rpc_status_file} = sprintf "$STATUSDIR/%s_%d.stat", $parms{buchsymbol}, $parms{kundennr};

	if ($parms{transaction_id} || $parms{remote_csv_file}) {
		if ($parms{remote_csv_file}) {
			my ($fname, $path, $suffix) = fileparse($parms{remote_csv_file}, '\.[^\.]*');
			$parms{rpc_status_file} = "$STATUSDIR/$fname.stat";
		} else {
			$parms{rpc_status_file} = "$STATUSDIR/$parms{transaction_id}.stat";
		}
	}






	my $TRANSACTION_ID_FILE="XXX";
	my $WORKDIR=".";

	my ($tmp_filelist_ref, $tmp_barcode_ref) = read_input_csv_file ($parms{remote_csv_file});

	write_status (STATUS_INIT, 0, 99,  "$parms{customer}:$parms{kundennr}:$parms{buchsymbol}:Prepare Logisth.AI");

	chmod 0666, $parms{rpc_status_file};

	$parms{remote_file_list} = $tmp_filelist_ref;
	$parms{remote_barcode_list} = $tmp_barcode_ref;

	$parms{rpc_status_server} = "http://xionit-test0401.xion.at/ocr_server.pl";



	foreach my $source_file (keys %$tmp_filelist_ref) {
		my ($fname, $path, $suffix) = fileparse($source_file, '\.[^\.]*');

		my $new_fname = "$parms{QR_ROOT}/upload/remote/$fname$suffix";

		debug 1,  "$source_file: new fname: $new_fname";
	}

	my $rpc_server = "cloud09.xion.at/cgi-bin/ocr_server.pl";

	close $FH_DBG;
	$FH_DBG=undef;

	#main::logisthai (\%parms, \@{$parms{single_invoices}}, \@{$parms{process_empty_pages}}, \@ARGV, $parms{transaction_id}); 
	my $res = rpc_logisthai ($FH_DBG, \%parms, \@{$parms{single_invoices}}, \@{$parms{process_empty_pages}}, \@ARGV, $rpc_server); 
	#my $res = rpc_logisthai ($FH_DBG, \%parms, \@single_invoices, \@process_empty_pages, \@ARGV, $rpc_server);

	#print "res: $res\n";

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $current_date=sprintf ("%04d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min, $sec);

	open ($FH_DBG, '>>', $debug_file) or my_die ("Could not create debug file $debug_file");

	debug 1, "debug closed $current_date debug_level: $parms{debug_level} $parms{kundennr}/$parms{buchsymbol} result: $res";
	unlink $parms{rpc_status_file};

	close $FH_DBG;
