#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN HOME);
	push @INC, "$QR_ROOT";

}

use Logi::rpc::rpc qw(rpc_get_kunden_daten); 
use strict;
##################################################

	my $kundennr = 210152;	# hanisch
	my $mandant_id = 2;	# hanisch
	my $kundennr = 200193;
	my $kundennr = 200069;
	my $kundennr = 200788;
	my $mandant_id = 1;
	my $kundennr = 200506;
	my $kundennr = 200792;
	my $kundennr = 200038;
	my $kundennr = 288888;



	$kundennr = $ARGV[0] if $#ARGV > -1;

	#my $rpc_server = "bmd:8000/bmd_server.pl";
	my $rpc_server = "test:80/cgi-bin/test_server.pl";	# testsystem
	my $rpc_server = "188.172.237.150/cgi-bin/test_server.pl";	# testsystem
	my $rpc_server = "http://xionit-test0401.xion.at/cgi-bin/test_server.pl";	# testsystem
	my $rpc_server = "bmd:8000/bmd_new_server.pl";
	my $rpc_server = "bmd:8000/bmd_server.pl";
	my $rpc_server = "cloud09.xion.at:7000/cgi-bin/ocr_server.pl";
	my $FH_DBG = 0;	# opt filehandle for debugfile


	my $res = my ($client, $name, $uid, $no_ust, $e_a, $is_quartal, $fibunr) = rpc_get_kunden_daten ($FH_DBG, $mandant_id, $kundennr, $rpc_server); 

	return 1 if $res < 6;	# no data, other error

	print "\tkundennr:\t$client\n";
	print "\tname:\t\t$name\n";
	print "\tuid:\t\t$uid\n";
	print "\tno_ust:\t\t$no_ust\n";
	print "\te_a:\t\t$e_a\n";
	print "\tis_quartal:\t$is_quartal\n";
	print "\tfibunr:\t\t$fibunr\n";


