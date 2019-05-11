
package Logi::rpc::RemoteCall;

use strict;
use warnings;

use REST::Client;
use Exporter qw(import);
use MIME::Base64 'encode_base64';
use File::Slurper 'read_binary';
use JSON;

our @EXPORT_OK = qw(call get_json get);

sub get {
	my ( $server, $data ) = @_;
	
	my $req = get_json($data);

	#The basic use case
	my $client = REST::Client->new();

	$client->addHeader( 'Content-Type', 'application/json' );
	$client->addHeader( 'Accept',       'application/json' );
	$client->addHeader( 'charset',      'UTF-8' );

	$client->GET( $server);

	return $client->responseContent();
}

sub call {
	my ( $server, $data ) = @_;
	
	my $req = get_json($data);

	#The basic use case
	my $client = REST::Client->new();

	$client->addHeader( 'Content-Type', 'application/json' );
	$client->addHeader( 'Accept',       'application/json' );
	$client->addHeader( 'charset',      'UTF-8' );

	$client->addHeader( 'X-AUTH-TOKEN', ' c694fe20-c2b5-9999-b8bd-ece8a4e47579' );



	$client->POST( $server, $req );

	return $client->responseContent();
}

sub prepare {
	my ($files) = @_;

	my @prepFiles = ();

	foreach my $e ( @{$files} ) {
		my $fe = {};
		my @paths = split '/', $e;

		$fe->{'name'} = $paths[-1];
		
		my $filesize = -s $e;
		# print ">> file size: ".$filesize."\n";

		my $base64 = encode_base64( read_binary($e) );

		$fe->{'content'} = $base64;

		push @prepFiles, $fe;
	}

	return \@prepFiles;
}

sub get_json {
	my ($data) = @_;
	
	# call sub to prepare file handling (base64 encoding)
	my $files = prepare( $data->get_files );
	
	## DEBUG START ##
#		print "> sender data prepared ";
#		print `date +"%T.%N"`;
	## DEBUG END ##

	# replace files with new structure
	$data->set_files($files);

	my $JSON = JSON->new->utf8;
	$JSON->convert_blessed(1);
	return $JSON->encode($data);
}

1;
