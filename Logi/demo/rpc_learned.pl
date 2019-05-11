#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN HOME);
	push @INC, "$QR_ROOT";

}

use Logi::rpc::rpc qw(rpc_get_learned); 
use strict;

##################################################

	my $kundennr = 220616;	# hanisch
	my $kundennr = 250408;	# hanisch
	my $mandant_id = 2;	# hanisch
	my $kundennr = 288888;
	my $mandant_id = 1;

	$kundennr = $ARGV[0] if $#ARGV > -1;
	my $rpc_server = "bmd:8000/bmd_server.pl";

	my $rpc_server = "bmd:8000/bmd_new_server.pl";
	my $rpc_server = "bmd:8000/bmd_server.pl";


	my $learned_aref = rpc_get_learned (0, $mandant_id, $kundennr, $rpc_server);

	my $count = 0;
        foreach my $entry (@$learned_aref) {
		my ($kundennr,$buchsymbol,$sc,$proz,$konto,$gkonto,$uid,$url,$email,$anz,$from) = @$entry;
		print "$kundennr;$buchsymbol;$sc;$proz;$konto;$gkonto;$uid;$url;$email;$anz;$from\n";
		$count ++;
	}

	print "$count results\n";




