#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN HOME);
	push @INC, "$QR_ROOT";

}

use Logi::rpc::rpc qw(rpc_write_transaction_log); 
use strict;



##################################################

	my $kundennr = 288888;

	$kundennr = $ARGV[0] if $#ARGV > -1;

	my $mandant_id = 1;
	# my $rpc_server = "bmd:8000/bmd_server.pl";
	my $mandant_id = 2;	# hanisch
	my $rpc_server = "bmd:8000/new_server.pl";
	my $FH_DBG = 0;	# opt filehandle for debugfile

	my @trans_arr = ();
	push @trans_arr, "transaction 1";
	push @trans_arr, "transaction 2";

	rpc_write_transaction_log (0, $mandant_id, $rpc_server, \@trans_arr);

