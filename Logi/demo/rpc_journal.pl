#!/usr/bin/perl


#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN HOME);
	push @INC, "$QR_ROOT";

}

use Logi::rpc::rpc qw(rpc_get_journal); 
use strict;

##################################################



	my $rpc_server = "bmd:8000/bmd_server.pl";
	my $rpc_server = "bmd:8000/new_server.pl";

	my $journal_aref = rpc_get_journal (1, 1, '01.10.2018', '13.10.2018', $rpc_server);

        foreach my $entry (@$journal_aref) {
		my  ($b_datum, $kundennr, $buchsymbol, $timestamp, $file, $r_datum, $t_datum, $r_rgnr, $t_rgnr, $r_uid, $t_uid, 
			$r_brutto, $t_brutto, $anz, $pdf_file, $jnr, $r_steuer, $t_steuer, $t_status) = split /;/, $entry;
		print "$entry\n";
	}




