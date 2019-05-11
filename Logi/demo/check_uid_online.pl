#!/usr/bin/perl

use strict;


sub check_uid_online {
	my $uid = shift;
	my $uid_p1 = substr ($uid, 0, 2);
	my $uid_p2 = substr ($uid, 2);

	
	my $tmpfile="uid.$$";

	my $soap_request_url = 'http://ec.europa.eu/taxation_customs/vies/services/checkVatService';
	# --post-data 
	my $soap_request = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types"><soapenv:Header/><soapenv:Body><urn:checkVat><urn:countryCode>%s</urn:countryCode><urn:vatNumber>%s</urn:vatNumber></urn:checkVat></soapenv:Body></soapenv:Envelope>';

	my $request = sprintf ($soap_request, $uid_p1, $uid_p2);

	print "soap: <$uid_p1> <$uid_p2> <$request>\n";


	my @cmd=("wget", "-q", "-O", "$tmpfile", $soap_request_url, "--post-data", $request);
	0 == system (@cmd) or die "ERROR on wget";

	open (my $FH_UID, '<', "$tmpfile") or die "cannot open $tmpfile";
	my $result="";

	while (<$FH_UID>) {
		$result .= $_;
	}
	close ($FH_UID);
		
	
	if ($result =~ m#<valid>true</valid>#x) {
		print "UID $uid valid\n";
		if ($result =~ m#<name>(.*?)</name>#x) {
			my $firma = $1;
			$firma =~ s/&amp;/&/g;
			$firma =~ s/&quot;/\"/g;
			print "NAME $uid: <$firma>\n";
			return ($firma, $uid);

		}
	}
			
}

sub uniq {
	my %seen;
        grep !$seen{$_}++, @_;
}

my @all_uids;
sub check_all {

	while (<STDIN>) {
		chop;
		push @all_uids, $_;
	}

	my @all_uniqe_uids = uniq (@all_uids);

	my $count=0;
	foreach my $uid (@all_uniqe_uids) {
		# print "UID: <$uid>\n";
		check_uid_online ($uid);
		$count ++;
	}

	print "count: $count\n";
}


	my $uid="ATU14662505";
	my $uid="ATU1X662505";
	my $uid="ATU57089411";	# 1&1 invalid uid ???
	my $uid="ATU11574303";
	my ($res_uid, $res_firma) = check_uid_online ($uid);

	if ($res_uid) {
		print ";$res_firma;;$res_uid\n";
	}
	

#	check_all();


