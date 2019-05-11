#!/usr/bin/perl 

package Logi::rpc::rpc;

use strict;

use POSIX qw(strtod setlocale LC_NUMERIC);
use Data::Dumper;
use Math::Round;
use File::Basename;
use locale;
use DateTime;
use DateTime::Format::Strptime;
use Fcntl qw ( LOCK_EX SEEK_SET );
use utf8;
use Encode qw(encode_utf8);
use MIME::Base64;


#use Image::Size;
use Cwd;

use Logi::common::Utils qw (debug);
use Logi::rpc::RemoteCall qw(call get);
use Exporter qw(import);
our @EXPORT = qw(rpc_get_kunden_daten rpc_write_transaction_log  rpc_get_learned rpc_get_journal rpc_process_rechnung rpc_writeResultFiles rpc_submit_queue_job rpc_list_queue rpc_list_queue_running
		rpc_change_queue_prio rpc_delete_queue_job rpc_logisthai);


use JSON;

use Logi::rpc::Data;

sub rpc_write_transaction_log {
	my $FH_DBG = shift;
	my $mandant = shift;
	my $rpc_server = shift;
	my $transaction_aref = shift;

	debug $FH_DBG, 1, "RPC TRANSACTIONS";

	my $req = Logi::rpc::Data->new;

	$req->set_function('write_transactions');
	$req->add_data("transactions", $transaction_aref);
	$req->add_data("mandant", $mandant);

	#### send request to remote server and store response (response is a json string)
	my $res = call($rpc_server, $req);

	my $data = decode_json($res);

	debug $FH_DBG, 1, "result of RPC: ", $data->{'data'}->{"res"};
}

sub rpc_get_kunden_daten {

	my $FH_DBG = shift;
	my $mandant_id = shift;
	my $kundennr = shift;
	my $rpc_server = shift;

	my $req = Logi::rpc::Data->new;

	$req->set_function('getKunde');
	$req->add_data("mandant", $mandant_id);
	$req->add_data("client", $kundennr);

	my $res = call($rpc_server, $req);

	my $data = decode_json($res);

	my $r = $data->{'data'}->{"res"};
	my $source = $data->{'data'}->{"source"};

	print "source: $source\n";

	return if !$r;

        $kundennr = $r->{"creditorid"};
        my  $name = $r->{"name"};
        my  $uid = $r->{"uid"};
        my  $no_ust = $r->{"no_ust"};
        my  $e_a = $r->{"e_a"};
        my  $is_quartal = $r->{"is_quartal"};
        my  $fibunr = $r->{"fibunr"};

	#print Dumper(\$data);
	#print "FIBUNR: $fibunr\n";

	return ($kundennr, $name, $uid, $no_ust, $e_a, $is_quartal, $fibunr);
}

sub rpc_list_queue_running {
	my $FH_DBG = shift;
	my $mandant_id = shift;
	my $kundennr = shift;
	my $queue_server = shift;

	my @q_list=();

	my $req = Logi::rpc::Data->new;

	my $res = get("$queue_server/queue2/$mandant_id/listWithRunning", $req);

	my $data = decode_json($res);
	#my $requestData = decode_json(encode_utf8($data->{'requestData'}));


	#my $rc = $data->{'data'}->{"result"};
	#print Dumper(\$data);
	#print Dumper(\$requestData);


	for my $ind (0 .. scalar @{$data}-1) {
		my $started = @{$data}[$ind]->{'start'};
		my $id = @{$data}[$ind]->{'id'};
		my $prio = @{$data}[$ind]->{'priority'};
		my $requestData = decode_json(encode_utf8(@{$data}[$ind]->{'requestData'}));
		my $email_parms = $requestData->{params}->{_email_parms};
		$email_parms->{timestamp} = $started;
		$email_parms->{id} = $id;
		$email_parms->{priority} = $prio;

		push @q_list, $email_parms;

	}

	return (\@q_list);
}

sub rpc_list_queue {
	my $FH_DBG = shift;
	my $mandant_id = shift;
	my $kundennr = shift;
	my $queue_server = shift;

	my @q_list=();

	my $req = Logi::rpc::Data->new;

	my $res = get("$queue_server/queue/BMD/list", $req);

	my $data = decode_json(encode_utf8($res));

	for my $ind (0 .. scalar @{$data}-1) {
		my $created = @{$data}[$ind]->{'created'};
		my $id = @{$data}[$ind]->{'id'};
		my $prio = @{$data}[$ind]->{'priority'};
		my $requestData = decode_json(encode_utf8(@{$data}[$ind]->{'requestData'}));
		my $email_parms = $requestData->{params}->{_email_parms};
		#print "created: $created kundennr $email_parms->{kundennr}\n";
		$email_parms->{timestamp} = $created;
		$email_parms->{id} = $id;
		$email_parms->{priority} = $prio;

		push @q_list, $email_parms;

		#print Dumper(\$requestData);
	}



	#my $rc = $data->{'data'}->{"result"};
	#print Dumper(\$data);


	return (\@q_list);
}

sub rpc_change_queue_prio {
	my $FH_DBG = shift;
	my $queue_server = shift;
	my $id = shift;
	my $prio = shift;
	my $mandant_id = shift;



	my $req = Logi::rpc::Data->new;

	my $res = get("$queue_server/queue2/$mandant_id/changePriority/$id/$prio", $req);


	my $data = decode_json(encode_utf8($res));

	my $rc = $data->{'data'}->{"result"};

	return ($rc);

}

sub rpc_delete_queue_job {
	my $FH_DBG = shift;
	my $queue_server = shift;
	my $id = shift;
	my $mandant_id = shift;


	my $req = Logi::rpc::Data->new;

	my $res = get("$queue_server/queue2/$mandant_id/cancel/$id", $req);


	#my $data = decode_json(encode_utf8($res));

	#my $rc = $data->{'data'}->{"result"};

	#return ($rc);

}

sub rpc_submit_queue_job {
	my $FH_DBG = shift;
	my $mandant_id = shift;
	my $kundennr = shift;
	my $fibunr = shift;
	my $csv_file = shift;
	my $queue_server = shift;
	my $prio = shift;
	my $email_parms_href = shift;

	my $req = Logi::rpc::Data->new;

	my $import_file = "Z:\\$kundennr\\$csv_file";

	$req->set_function('vorerfassung_import');
	$req->add_data("client", $mandant_id);
	$req->add_data("companyNr", $kundennr);
	$req->add_data("fibuNr", $fibunr);
	$req->add_data("importFile", $import_file);
	$req->add_data("priority", $prio);
	$req->add_data("callback", "http://cloud09.xion.at/cgi-bin/ocr_server.pl");
	$req->add_data("_email_parms", $email_parms_href);
	$req->add_data("_test_data", "test123");
	$req->add_data("user", "");

	#print Dumper(\$req);

	my $res = call("$queue_server/bmd", $req);

	my $data = decode_json($res);


	my $rc = $data->{'data'}->{"result"};
	#print "rpc_submit: res: $res\n";


	return ($rc);
}

sub rpc_get_learned {
	my $FH_DBG = shift;
	my $mandant_id = shift;
	my $kundennr = shift;
	my $rpc_server = shift;

	my $req = Logi::rpc::Data->new;

	$req->set_function('getLearned');
	$req->add_data("mandant", $mandant_id);
	$req->add_data("client", $kundennr);

	my $res = call($rpc_server, $req);

	my $data = decode_json($res);

	my $learned_aref = $data->{'data'}->{"res"};
	my $source = $data->{'data'}->{"source"};

	print "source: $source\n";

	return if !$learned_aref;

	return ($learned_aref);
}

##################################################


sub rpc_get_journal {
	my $userid = shift;
	my $kundennr = shift;
	my $from = shift;
	my $to = shift;
	my $rpc_server = shift;

	my $req = Logi::rpc::Data->new;

	$req->set_function('getJournal');
	$req->add_data("mandant", $userid);
	$req->add_data("client", $kundennr);
	$req->add_data("from", $from);
	$req->add_data("to", $to);

	my $res = call($rpc_server, $req);

	my $data = decode_json($res);

	my $r = $data->{'data'}->{"res"};

	return if !$r;

	return $r;

}

sub rpc_writeResultFiles {
	my $FH_DBG = shift;
	my $rpc_server = shift;
	my $mandant_id = shift;
	my $client = shift;
	my $files_aref = shift;

        my $req = Logi::rpc::Data->new;

	$req->set_function('writeResultFiles');
	$req->add_data("mandant", $mandant_id);
	$req->add_data("client", $client);


	#### add files to request


	foreach my $file (@{$files_aref}) {
		$req->add_file($file);
	}

	#### add data to request
	$req->add_data("files", $files_aref);

	#### send request to remote server and store response (response is a json string)
	my $res = call($rpc_server, $req);

	my $data = decode_json($res);

	debug $FH_DBG, 1, "result of RPC: ", $data->{'data'}->{"res"};



	return ($data->{'data'}->{"res"});
}

sub rpc_logisthai {
	my $FH_DBG = shift;
	my $parms_href = shift;
	my $single_invoices_aref = shift;
	my $process_empty_pages_aref = shift;
	my $files_aref = shift;
	my $ocr_server = shift;

	my $req = Logi::rpc::Data->new;
	$req->set_function('logisthai');

	foreach my $source_file (keys %{$parms_href->{remote_file_list}}) {
		my ($fname, $path, $suffix) = fileparse($source_file, '\.[^\.]*');

		my $new_fname= "$fname$suffix";

		print "adding $source_file $new_fname\n";
		$req->add_file($source_file);

                $parms_href->{remote_file_list}->{$new_fname} = $parms_href->{remote_file_list}->{$source_file};
                $parms_href->{remote_barcode_list}->{$new_fname} = $parms_href->{remote_barcode_list}->{$source_file};
                delete $parms_href->{remote_file_list}->{$source_file};
                delete $parms_href->{remote_barcode_list}->{$source_file} if exists $parms_href->{remote_barcode_list}->{$source_file};




	}
	$req->add_data("parms", $parms_href);
	$req->add_data("files", $files_aref);
	#$req->add_data("single_invoices", $single_invoices_aref);
	#$req->add_data("process_empty_pages", $process_empty_pages_aref);

	my $res = call($ocr_server, $req);

	#print "*** $res";

	my $data = decode_json($res);

        $files_aref = $data->{'files'};

        for my $index (0 .. scalar $#$files_aref) {

                my $source_file= $files_aref->[$index]->{"name"};
                my ($fname, $path, $suffix) = fileparse ($source_file,  '\.[^\.]*');

                my $new_fname = "$parms_href->{QR_ROOT}/zip/$fname$suffix";

                debug $FH_DBG, 1,  "adding $source_file -> $new_fname\n";


                open (my $FH, '>', "$new_fname") or die "Could not create file $fname";

                print $FH decode_base64($files_aref->[$index]->{"content"});
                close $FH;
        }

	print "logentry: ", $data->{'data'}->{"logentry"}, "\n";


	my $LOGFILE="$parms_href->{QR_ROOT}/logs/logisthai.log";
	open (LOG_FH, ">>$LOGFILE") or die "cannot open $LOGFILE";


	printf LOG_FH $data->{'data'}->{"logentry"};

	close LOG_FH;


	return ($data->{'data'}->{"res"});

}

sub rpc_process_rechnung {
	my $FH_DBG_IN = shift;
	my $bin_dir = shift;
	my $rg_nr = shift;
	my $pdf_file = shift; 
	my $date_min = shift;
	my $date_max = shift;
	my $my_uid_in = shift;
	my $add_missing_mwst = shift;
	my $barcode = shift;
	my $debug_level = shift;
	my $file_praefix = shift;
	my $tess_files_aref = shift;
	my $ocr_server = shift;

	my ($name, $path, $suffix) = fileparse($file_praefix, '\.[^\.]*');
	$file_praefix = $name;		# for remote call strip directory --> will be on another place there

	# print "> sender begin ";
	# print `date +"%T.%N"`;

	my %ocr_parms = (rg_nr => $rg_nr,
		pdf_file=>$pdf_file,
		date_min=>$date_min,
		date_max=>$date_max,
		myuid=>$my_uid_in,
		add_missing_mwst=>$add_missing_mwst,
		barcode=>$barcode,
		file_praefix=>$file_praefix
		);

	my $req = Logi::rpc::Data->new;
	$req->set_function('processFiles');

	#### add files to request

	$req->add_file($pdf_file) if $pdf_file;

	foreach my $file (@{$tess_files_aref}) {
		
		$req->add_file($file);
		print "add file $file\n";
	}

	#### add data to request
	$req->add_data("files", $tess_files_aref);
	$req->add_data("parms", \%ocr_parms);

	#### send request to remote server and store response (response is a json string)
	my $res = call("http://cloud09.xion.at/cgi-bin/server.pl", $req);		# TODO
	#my $res = call($ocr_server, $req);


	## DEBUG START ##
		# print "> sender got response ";
		# print `date +"%T.%N"`;
	## DEBUG END ##


#	print "*** $res";
#	print "\n";
	my $data = decode_json($res);

	my $r = $data->{'data'}->{"res"};

	my  $datum = $r->{"datum"};
	my  $belegnr = $r->{"belegnr"};
	my  $uid = $r>{"uid"};
	my  $url = $r->{"url"};
	my  $email = $r->{"email"};
	my  $skonto_proz = $r->{"skonto_proz"};
	my  $status = $r->{"status"};
	my  $coords = $r->{"coords"};
	my  $ocr_string = $r->{"ocr_string"};
	my  $supplier = $r->{"supplier"};
	my $result_values_aref = $r->{"result_values"};
	#my @results = $$result_values_aref;

	return ($datum, $belegnr, $uid, $url, $email, $skonto_proz, $status, $supplier, $coords, $ocr_string, $result_values_aref);
}


1;
