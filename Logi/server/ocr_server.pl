#!/usr/bin/perl
BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT QR_BIN HOME);
	push @INC, "$QR_BIN";
	push @INC, "/var/logisthai/test";

}
print "Content-type: text/plain\n\n";

use CGI;
use JSON;
#use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use MIME::Base64;
use DateTime::Format::Strptime;
use utf8;
use Encode qw(encode_utf8);
use strict;
use File::Basename;


use Logi::rpc::RemoteCall qw(call get get_json);
use Logi::rpc::Data;
use Data::Dumper;

use JSON;

my $FH_DBG;

my $debug_level=2;

################################################################################

sub debug {
	my $level = shift;
	return if $level>$debug_level;
	print $FH_DBG "($level) " if ($debug_level > 1); 
	foreach my $v (@_) {
		print $FH_DBG "$v";
	}
	print $FH_DBG "\n";
}

################################################################################

##################################################


##################################################


##################################################

sub writeStatus {
	my $FH_DBG = shift;
	my $data = shift;
	my $r = $data->{'data'}->{"parms"};


	my $status_file = $data->{'data'}->{"status_file"};
	my $status_entry = $data->{'data'}->{"status_entry"};
	my $status_state = $data->{'data'}->{"state"};

	debug 1,  "writeStatus: $status_file $status_entry $status_state";

	if ($status_state == 99) {
		unlink $status_file;
	} else {


		open my $FH_STATUS, ">>$status_file";

		print $FH_STATUS "$status_entry";

		close $FH_STATUS;
	}
	

	my $response = Logi::rpc::Data->new;
	$response->add_data('res', 1);

	print get_json($response);

}


##################################################

##################################################
# MAIN
##################################################
my %actions = ( writeStatus => \&writeStatus );


	my $debug_file = "/var/www/html/server.dbg";
	open ($FH_DBG, '>>', $debug_file) or die "Could not create debug file $debug_file";

	debug 1, "################################################################################";

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $current_date=sprintf ("%04d-%02d-%02d %02d:%02d:%02d", $year+1900,$mon+1,$mday,$hour,$min, $sec);

	debug 1, "debug opened $current_date debug_level: $debug_level";

	my $q = CGI->new;

	#### get request content
	my $jsonData = encode_utf8($q->param('POSTDATA'));
	#debug 2,  Dumper(\$jsonData);

	### decode request content from json to perl object

	my $data = decode_json($jsonData);

	my $r = $data->{'data'}->{"parms"};
	my $function = $data->{'function'};

	debug 1,  "function: $function";

	if (exists $actions{$function}) {
		$actions {$function}->($FH_DBG, $data);
	}


	debug 1, "debug closed $current_date debug_level: $debug_level";
	close $FH_DBG;
