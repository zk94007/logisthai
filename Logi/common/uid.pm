#!/usr/bin/perl

BEGIN { 
	use Env qw(QR_ROOT QR_CGIROOT);
	push @INC, "$QR_CGIROOT";

}

package Logi::common::uid;

# UID verwaltung
#
# uid wird geprueft bei Kassa, ER/AR
# gesucht wird zuerst nach UID, dann nach Kundenname bzw. url
# --> zuerst in klient_uid's	
#	--> found: valid, falls konto vorhanden: nehmen
# 	--> not found: in mandanten uid's (alle) --> validate
#		--> found: falls konto vorhanden: nehmen
# 		--> not found: search invalid
#			--> found: invalid
#			--> not found online search
#				--> found: add record to all uid's
# 				--> not found: invalid --> store in invalid (online search reduce)
#
# abgleich:
# 	--> file pro kunde kommt daily 
#		--> 
use strict;

use Exporter qw(import);
our @EXPORT = qw( uid_write_files uid_initialize uid_get_konten uid_get_from_link uid_check_with_online uid_read_system_wide_file uid_update_system_wide_invalid_file,
	uid_get_steuer_in_land, 
	uid_check_steuer_correction, 
	uid_get_steuer_percentage);

#	uid_add_checked_uid 
#	update_system_wide_uid_file 
#	uid_read_learned_data 
#	uid_generate_kunden_uid 
#	uid_write_klient 
#	uid_check_online 
#	uid_check_online_suchefirma 
#	uid_check_url 
#	uid_check_uid 
#	uid_read_invalid 

use Logi::common::Utils;
use Logi::rpc::rpc;
use Env qw(QR_ROOT QR_CGIROOT REMOTE_USER);
use locale;
use File::Basename;
use Math::Round;
use Getopt::Long;
use Fcntl qw ( LOCK_EX SEEK_SET );
use DateTime;
use DateTime::Format::Strptime;
use HTML::LinkExtractor;
#use LWP qw( get ); #     
use LWP::Simple; # qw( get );

$QR_CGIROOT="." if !$QR_CGIROOT;
$QR_ROOT=".." if !$QR_ROOT;

my $QR_MANDANT=substr($REMOTE_USER, 0, 4);


my $CONFIGDIR="$QR_ROOT/config";

use constant  SYSTEMWIDE_UID_FILE => "$QR_ROOT/config/master_uid.csv";
use constant  SYSTEMWIDE_INVALID_UID_FILE => "$QR_ROOT/config/invalid_uid.csv";	# take mandant wide;
use constant BUCH_TYPE_ER => 1;
use constant BUCH_TYPE_AR => 2;
use constant BUCH_TYPE_KA => 3;

my $KLIENTEN_UID_DIR = "$QR_ROOT/$QR_MANDANT/uid";


my %kunden_uids=();
my %kunden_namen=();

my %all_valid_uids = ();
#my %all_valid_urls = ();
my %all_invalid_uids = ();
#my %all_valid_uid_konto = ();
#my %all_valid_uid_gkonto = ();
#my %all_valid_email_uid = ();
my %all_valid_url_uid = ();

my %all_valid_uid_konten = ();
my %all_valid_url_konten = ();
my %all_valid_email_konten = ();

my @new_uids=();
my @new_invalid_uids=();
my $FH_DBG;

use constant TYPE_KLIENT => 1;
use constant TYPE_MANDANT => 2;
use constant TYPE_READONLY => 1;
use constant TYPE_WRITE_EXCL => 2;

use constant TYPE_NEW => 1;		# new uid record
use constant TYPE_EXISTS => 2;		# existing uid record
use constant TYPE_INVALID => 4;		# existing uid record

use constant TYPE_KLIENT => 1;		# existing uid record
use constant TYPE_MANDANT => 2;		# existing uid record

use constant TYPE_LIEFERANT => 1;		
use constant TYPE_KUNDE => 2;		

my @valid_uids=();
my %valid_urls=();


# 4 Filetypen:
# 	Lieferantenstamm	<kdnr>_
# 	Kundenstamm
# 	UIDs auf Kundenbasis
#	UIDs for all
#
# Satzaufbau:
# <kunden-/lieferantennr/konto>;<langbezeichnung>;<kurzbezeichnung>;<uid>;<weburl>;<email>

sub debug {
	my @parm = ($FH_DBG);
	push @parm, @_;
	Logi::common::Utils::debug (@parm);
}
sub my_die {
	die "@_";
}
sub uniq {
	my %seen;
        grep !$seen{$_}++, @_;
}

################################################################################

sub store {
	my $type = $1;
	my $line = $2;

	my ($kdnr_or_konto, $name_lang, $name_kurz, $uid) = split /;/;

	my @kdnr_name_uid = ($type, $kdnr_or_konto, $name_lang, $name_kurz, $uid, TYPE_EXISTS);
	debug 3, "$type, $kdnr_or_konto, $name_lang, $name_kurz, uid: $uid";
	$kunden_uids{$uid} = \@kdnr_name_uid if $uid;
	$kunden_namen{$name_lang} = \@kdnr_name_uid if $name_lang;

}

################################################################################
################################################################################

sub uid_read_system_wide_file {

	debug 2, "uid_read_system_wide_file";

	open ( my $FH_M_UID, '<', SYSTEMWIDE_UID_FILE );
	return if !$FH_M_UID;	# kein file gefunden, darf sein, sollte aber nicht

	while (<$FH_M_UID>) {
		chop;
		my ($uid, $name_lang, $name_kurz, $url) = split /;/;
		$uid = uc ($uid);
		my @uid_rec = ($uid, $name_lang, $name_kurz, $url);
		$all_valid_uids{$uid} = \@uid_rec;
		# $all_valid_urls{$url} = $uid if $url;
		$all_valid_url_uid {$url} = $uid if $url;
	}
	close $FH_M_UID;
}

################################################################################
# neue entries hinten anhaengen

sub uid_update_system_wide_invalid_file {


	debug 3, "write_system_wide_invalid_uid_file";

	open ( my $FH_M_UID, '>>', SYSTEMWIDE_INVALID_UID_FILE ) or my_die "cannot create system wide uid file ", SYSTEMWIDE_INVALID_UID_FILE;

	flock $FH_M_UID, LOCK_EX;

	my @uniq_uids = uniq (@new_invalid_uids);

	foreach my $uid (@uniq_uids) {
		debug 3, "update invalid uid file: $uid";
		print  $FH_M_UID "$uid\n";
	}
	close $FH_M_UID;
}

################################################################################

sub uid_update_system_wide_file {


	debug 3, "write_system_wide_uid_file";

	open ( my $FH_M_UID, '>>', SYSTEMWIDE_UID_FILE ) or my_die "cannot create system wide uid file ", SYSTEMWIDE_UID_FILE;

	flock $FH_M_UID, LOCK_EX;

	my @uniq_uids = uniq (@new_uids);

	foreach my $uid (@uniq_uids) {
		my ($uid, $name_lang, $name_kurz, $url) = @{$all_valid_uids{$uid}};
		print  $FH_M_UID "$uid;$name_lang;$name_kurz;$url\n";
		debug 3, "update uid file: $uid $name_lang";
	}
	close $FH_M_UID;
}

################################################################################

sub uid_add_checked_uid {
	my ($in_uid, $in_name_lang, $in_url) = @_;

	debug 3, "uid_add_checked_uid: <$in_uid> <$in_name_lang> <$in_url>";

	my $uid;
	my $name_lang;
	my $name_kurz;
	my $url;

	if (exists $all_valid_uids{$in_uid}) {
		# fetch old values
		($uid, $name_lang, $name_kurz, $url) = @{$all_valid_uids{$in_uid}};
		debug 3, "uid_add_checked_uid: old values: <$uid> <$name_lang> <$name_kurz> <$url>";
	} 

	$name_lang = $in_name_lang if $in_name_lang ne "";
	# $name_kurz = $in_name_kurz if !$in_name_kurz;
	$url = $in_url if $in_url ne "";
	$uid = $in_uid;


	my @uid_rec = ($uid, $name_lang, $name_kurz,  $url);
	debug 3, "uid_add_checked_uid: new values: <$uid> <$name_lang> <$name_kurz> <$url>";
	$all_valid_uids{$uid} = \@uid_rec;
	# $all_valid_urls{$url} = $uid if $url;
	$all_valid_url_uid {$url} = $uid if $url;
	push @new_uids, $uid;
}



################################################################################
################################################################################
# Funktionen für die Archive Lieferanten/Kunden
# diese sind nur read-only
# 


################################################################################
sub uid_read_learned_data {
	my $mandant_id = shift;
	my $buchsymbol = shift;
	my $kundennr = shift;
	my $rpc_server = shift;

	my @learned_arr = ();	# to store and put in file for transfer

	if ($rpc_server) {
		debug 1, "RPC: READ_LEARNED";
		my $learned_aref = rpc_get_learned ($FH_DBG, $mandant_id, $kundennr, $rpc_server);
		foreach my $entry (@$learned_aref) {
			my ($kundennr,$bs,$sc,$proz,$konto,$gkonto,$uid,$url,$email,$anz,$source) = @$entry;
			next if $buchsymbol ne $bs;
			push @learned_arr, (["$kundennr;$bs;$sc;$proz;$konto;$gkonto;$uid;$url;$email;$anz;$source", 1]);

			debug 2, "RPC_uid_read_learned_data: <$bs> <$sc> <$proz> <$konto> <$gkonto> <$uid> <$url> source: <$source>" if $konto && ($uid || $url || $email);

			$all_valid_uid_konten {$uid}{$sc}{$proz} = [$source, $konto, $gkonto] if $uid && $gkonto && $konto;
			$all_valid_url_konten {$url}{$sc}{$proz} = [$source, $konto, $gkonto] if $url && $gkonto && $konto;
			$all_valid_email_konten {$email}{$sc}{$proz} = [$source, $konto, $gkonto] if $email && $gkonto && $konto;

		}

		return \@learned_arr if @learned_arr;		# nur wenn ergebnisse da
		debug 1, "ERROR: uid_read_learned_data: no result from RPC!";
	}

	my $file_name = "$CONFIGDIR/learned" . "_$mandant_id.csv";	
	debug 2, "uid_read_learned_data $file_name $buchsymbol $kundennr";

	return if !open ( my $FH, '<', "$file_name" );

	while (<$FH>) {
		chop;
		# AR 2018-10-06 source: 0: stammdaten, 1: journal/learned
		my ($companycc, $bs, $sc, $proz, $konto, $gkonto, $uid, $url, $email, $anz, $source) = split /;/;
		next if $companycc ne $kundennr;
		next if $buchsymbol ne $bs;
		push @learned_arr, ([$_, 2]);

		debug 2, "uid_read_learned_data: <$bs> <$sc> <$proz> <$konto> <$gkonto> <$uid> <$url> source: <$source>" if $konto && ($uid || $url || $email);

		my @konten = [ $konto, $gkonto ];

		$all_valid_uid_konten {$uid}{$sc}{$proz} = [$source, $konto, $gkonto] if $uid && $gkonto && $konto;
		$all_valid_url_konten {$url}{$sc}{$proz} = [$source, $konto, $gkonto] if $url && $gkonto && $konto;
		$all_valid_email_konten {$email}{$sc}{$proz} = [$source, $konto, $gkonto] if $email && $gkonto && $konto;



	}
	close $FH;
	return \@learned_arr;
}
################################################################################

my $MASTER_CREDITOR_KUNDEN="$QR_ROOT/$QR_MANDANT/BMD/Master_Creditor_Kunden.csv";

sub uid_generate_kunden_uid {
	my $file_name = $MASTER_CREDITOR_KUNDEN;
	# my $file_name = $MASTER_CREDITOR_LIEFERANTEN;

	return if !open ( my $FH_KDN, '<', "$file_name" );

	while (<$FH_KDN>) {
		chop;
		#my $input = convert_special_chars ($_);
		my @arr = split /;/;
		my $name = $arr[0];
		my $vorname = $arr[1];
		my $uid = $arr[8];
		my $companycc = $arr[9];	# wenn hier die kundennr drinnen --> dann seine kunden (klient)
		my $creditorid = $arr[17];	# wenn hier unsere kundennr drinnen und companycc == 1--> dann ist das unsere ATU
		my $konto = $arr[21];
		my $url = $arr[19];
		my $email = $arr[20];
		$url =~ s/^.*?https?:\/\///g;

		$uid =~ s/ //g;
		$uid = uc ($uid);

		$name = "$vorname $name" if $vorname;
		if ($companycc == 1) {
			print "$creditorid;$name;$uid;\n";
		}
	}

	close $FH_KDN;

}
################################################################################

sub uid_get_konten {
	my ($steuercode, $proz, $uid, $url, $email) = @_;

	debug 2, "uid_get_konten: <$uid> <$url> <$email> sc:<$steuercode> p:<$proz>";

	my @search_proz = ($proz, 20, 10, 13, 0);

	my @search_sc = uniq (keys %{$all_valid_uid_konten{$uid}},keys %{$all_valid_url_konten{$uid}},keys %{$all_valid_email_konten{$uid}});

	debug 3, "uid_get_konten: search_sc: <@search_sc> $#search_sc";

	foreach my $sc (@search_sc) {
		foreach my $p (@search_proz) {
			debug 3, "--> uid_get_konten: search sc:<$sc> p <$p>";
		
			if ($uid && exists $all_valid_uid_konten {$uid}{$sc}{$p}) {
				$proz = $p;	# if $p;		# falls kein steuersatz --> dann nicht change
				debug 3, "uid_get_konten uid: ret proz: <$proz> sc: <$sc>";

				return ($sc, $p, @{$all_valid_uid_konten {$uid}{$sc}{$p}});
			}
			if ($url && exists $all_valid_url_konten {$url}{$sc}{$p}) {
				$proz = $p; # if $p;
				debug 3, "uid_get_konten url: ret proz: <$proz> sc: <$sc>";
				return ($sc, $p, @{$all_valid_url_konten {$url}{$sc}{$p}}) 
			}
			if ($email && exists $all_valid_email_konten {$email}{$sc}{$p}) {
				$proz = $p; #  if $p;
				debug 3, "uid_get_konten email: ret proz: <$proz> sc: <$sc>";
				return ($sc, $p, @{$all_valid_email_konten {$email}{$sc}{$p}}) 
			}
		}
	}
	return ("", "", @{$all_valid_uid_konten {$uid}{""}{""}}) if $uid && exists $all_valid_uid_konten {$uid}{""}{""};
	return ("", "", @{$all_valid_url_konten {$url}{""}{""}}) if $url && exists $all_valid_url_konten {$url}{""}{""};
	return ("", "", @{$all_valid_email_konten {$email}{""}{""}}) if $email && exists $all_valid_email_konten {$email}{""}{""};

	return;
}

=begin comment

=cut

################################################################################

sub uid_read_invalid {

	debug 2, "uid_read_invalid";

	open ( my $FH_UID, '<', SYSTEMWIDE_INVALID_UID_FILE ) or die "system wide invalid uid file not found";;

	while (<$FH_UID>) {
		chop;
		my $uid = uc ($_);
		$all_invalid_uids{$uid} = $uid;
	}
	close $FH_UID;
}

################################################################################

sub uid_write_klient {
	my $kundennr = shift;

	my $FH_KDN;

	debug 3, "uid_write_klient <$kundennr>";

	my $file_name = $KLIENTEN_UID_DIR."/$kundennr.csv";	

	debug 3, "open $file_name";

	if (!open ( $FH_KDN, '+<', "$file_name" )) {
		open ( $FH_KDN, '>', "$file_name" ) or my_die "cannot open config $file_name";
	}
	flock $FH_KDN, LOCK_EX;
	seek $FH_KDN, 0, SEEK_SET;
	truncate $FH_KDN, 0;

	for my $loop_uid (keys %kunden_uids) {
		my ($type, $konto, $name_lang, $name_kurz, $uid) = @{$kunden_uids{$loop_uid}};
		print  $FH_KDN "$konto;$name_lang;$name_kurz;$uid\n";
		#print $FH_KDN "
	}
	close $FH_KDN;
}

################################################################################
################################################################################

################################################################################


sub uid_check_online {
	my $uid = shift;
	my $uid_p1 = substr ($uid, 0, 2);
	my $uid_p2 = substr ($uid, 2);

	# print "**** uid_check_online $uid\n";

	
	my $tmpfile="uid.$$";	# TODO --> to working dir

	my $soap_request_url = 'http://ec.europa.eu/taxation_customs/vies/services/checkVatService';
	# --post-data 
	my $soap_request = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:urn="urn:ec.europa.eu:taxud:vies:services:checkVat:types"><soapenv:Header/><soapenv:Body><urn:checkVat><urn:countryCode>%s</urn:countryCode><urn:vatNumber>%s</urn:vatNumber></urn:checkVat></soapenv:Body></soapenv:Envelope>';

	my $request = sprintf ($soap_request, $uid_p1, $uid_p2);

	# print "soap: <$uid_p1> <$uid_p2> <$request>\n";


	my @cmd=("wget", "-q", "-O", "$tmpfile", $soap_request_url, "--post-data", $request);
	0 == system (@cmd) or die "ERROR on wget";

	open (my $FH_UID, '<', "$tmpfile") or die "cannot open $tmpfile";
	my $result="";

	while (<$FH_UID>) {
		$result .= $_;
	}
	close ($FH_UID);
	unlink $tmpfile;
		
	
	if ($result =~ m#<valid>true</valid>#x) {
		my $firma = "";
		if ($result =~ m#<name>(.*?)</name>#x) {
			$firma = $1;
			$firma =~ s/&amp;/&/g;
			$firma =~ s/&quot;/\"/g;

		}
		debug 1, "uid_check_online: $uid VALID: $firma\n";
		return ($uid, $firma);
	} elsif ($result =~ m#<valid>false</valid>#x) {
		debug 1,  "uid_check_online: $uid INVALID";
		return ("INVALID", "INVALID");
	} else {
		debug 1,  "uid_check_online: $uid NO RESULT";
		return ("NO RESULT", "NO RESULT");		# timeout, etc
	}
}

sub uid_check_online_suchefirma {
	my $uid = shift;

	
	my $tmpfile="uid.$$";

	return ($uid, "");


	my @cmd=("wget", "-q", "-O", "$tmpfile", "https://www.suchefirma.at/check.php?vat=%22+$uid,");
	0 == system (@cmd) or return "INVALID";

	open (my $FH_UID, '<', "$tmpfile") or return "INVALID";
	my $result="";

	while (<$FH_UID>) {
		$result .= $_;
	}
	close ($FH_UID);
	unlink $tmpfile;
		

	debug 3,  "res: $result";

	$result =~ s/<.?strong>/;/g;
	$result =~ s/<br>/;/g;
	$result =~ s/&amp;/&/g;
	$result =~ s/&quot;/\"/g;
	$result =~ s/\n/;/gm;

	my ($f1,$uid, $valid, $f4, $firma, $f6, $f7, $adresse, $ort) = split /;/, $result;

	if ($valid =~ /G.*LTIG/i) {

		debug 4,  "\tuid:\t$uid\n\tfirma:\t$firma\n\tAdresse:\t$adresse\n\tOrt:\t$ort";
		debug 3,  ";$firma;;$uid";
		return ($uid, $firma);
	} elsif ($result =~ /UNG.*LTIG/i) {
		debug 3,  ";INVALID;;$uid";
		return ("INVALID", "");
	} else {
		debug 3, "error: unexpected result: $result";
		return ("ERROR", "");
	}

# res:  UID Nummer ;ATU14398702; ist GÜLTIG ;Firmenname: ;EDUSCHO (Austria) GmbH; ;Firmenadresse: ;Gadnergasse 71;AT-1110 Wien; ;


}

################################################################################

sub uid_check_url {
	my $url = shift;
	if ($valid_urls{$url}) {
		debug "--> url found!: $valid_urls{$url}";
	}
}
		

################################################################################

sub uid_check_uid {
	my $uid = shift;
	my $uid = uc ($uid);
	if (exists $all_valid_uids{$uid}) {
		debug 2, "check_uid: $uid: found";
		return 1;
	} elsif (exists $all_invalid_uids{$uid}) {
		debug 2, "check_uid: $uid: INVALID found";
	} else {
		debug 2, "check_uid: $uid: NOT found";
	}

	return 0;
		
}

################################################################################

sub uid_check_with_online {
	my $uid = shift;
	my $url = shift;

	my $uid = uc ($uid);
	if (exists $all_valid_uids{$uid}) {
		my ($uid, $name_lang, $name_kurz, $url) = @{$all_valid_uids{$uid}};
		debug 2, "uid_cech_with_online: $uid: found <$name_lang>";
		# uid_add_checked_uid ($uid, "",  $url) if $url;
		return ($uid, $name_lang);
	} elsif (exists $all_invalid_uids{$uid}) {
		debug 2, "uid_check_with_online: $uid: INVALID found";
	} else {
		debug 2, "uid_check_with_online: $uid: NOT found --> do online check";
		my ($res_uid, $res_name) = uid_check_online ($uid);

		if (uc ($res_uid) eq $uid) {
			debug 1, "uid_check_with_online: $uid: found online: $res_name";
			# print ";$res_name;;$res_uid\n";

			uid_add_checked_uid ($res_uid, $res_name, $url);
			
			return ($uid, $res_name);
		} elsif ($res_uid eq "INVALID") {
			debug 1, "uid_check_with_online: $uid: invalid";
			$all_invalid_uids{$uid}=$uid;
			push @new_invalid_uids, $uid;
		} else {
			debug 1, "uid_check_with_online: $uid: other error";
		}
	}

	return;
		
}

################################################################################

	# eigene UID regex nur mit blanks dazwischen

	my $REGEX_UID_STRICT = qr/(?|
			(AT\h*U)\h*(\d{8})\b|
			(DE)\h*(\d{9})\b|
			(BE)\h*(\d{10})\b|
			(BG)\h*(\d{9,10})\b|
			(HR)\h*(\d{11})\b|
			(CZ)\h*(\d{8,10})\b|
			(DK)\h*(\d{8})\b|
			(EE)\h*(\d{9})\b|
			(FI)\h*(\d{8})\b|
			(HU)\h*(\d{8})\b|
			(LU)\h*(\d{8})\b|
			(IT)\h*(\d{11})\b|
			(SE)\h*(\d{12})\b|
			(NL)\h*(\d{9}.\d{2})\b)/ixm;
	

sub uid_get_from_link {
	my $in_url = shift;

	my $html = "";
	my $link = "";

	# xxx.spar.at www.xxx.spar.at spar.at www.spar.at

	push my @tries, ($in_url, "www.$in_url");
	
	my $url = $in_url;
	$url =~ s/(^[^\.]+\.)([^\.]+\..*?$)/$2/;	# remove first word

	push @tries, ($url, "www.$url") if $url ne $in_url;


	my $got_one=0;
	foreach $url (@tries) {

		return $all_valid_url_uid {$url} if exists $all_valid_url_uid {$url};	# schon in db?

		$link = "http://$url/";

		# print "try: $link\n";

		if ($html = get($link)) {
			$got_one = 1;
			last;
		};
	}
	return if !$got_one;

	debug 3, "uid_get_from_link: could retrieve base info from: $url";

	my $LX = new HTML::LinkExtractor();
	 
	$LX->parse(\$html);
	#$LX->parse($file_name);

	my %found_uids = ();
	my @ret_uids = ();
	my %gather = ();

	for my $Link( @{ $LX->links } ) {

		# print "loop: $$Link{_TEXT}\n";
		if ( $$Link{_TEXT}=~ /(impressum|kontakt)/igm ) {

			my $found = $&;
			# $gather {$$Link{href}} = 1 if $$Link{href} =~ /^\//;
			$gather {$$Link{href}} = 1  if $$Link{href} =~ /^(\/|http)/i;	# AR 2018-10-06
			debug 3, "uid_get_from_link: link: <$$Link{href}>" if $$Link{href} =~ /^(\/|http)/i;
		}
	}

	foreach my $l (keys %gather) {

		my $index_url  = "$l";
		$index_url  = "$link/$l" if $l !~ /http/i;	# AR 2018-10-06
		debug 3, "uid_get_from_link: gather: $index_url";

		my $html = get($index_url) or return;

		while ($html =~ /$REGEX_UID_STRICT/ixg) {
			my $uid = uc ("$1$2");
			$uid =~ s/ //g;

			debug 2, "uid_get_from_link: --> uid found $uid";

			if (uid_check_with_online ($uid, $url)) {
				debug 2, "--> valid";
				$found_uids{$uid}=$uid;
			}
			
		}
	}

	#return %found_uids;
	my $ret_uid= (keys %found_uids)[0] if %found_uids;
	debug 2, "uid_get_from_link: return <$ret_uid>";
	uid_add_checked_uid ($ret_uid, $in_url, $in_url) if %found_uids;
	# print "*** uid_get_from_link $ret_uid $in_url\n";
	return $ret_uid;
}

################################################################################

sub uid_initialize {
	my $FH = shift;		# debug filehandle
	my $CONFIGDIR_in = shift;
	my $mandant_id = shift;
	my $kundennr = shift;
	my $buchtype = shift;
	my $buchsymbol = shift;
	my $rpc_server = shift;

	$FH_DBG=$FH;

	$CONFIGDIR = $CONFIGDIR_in;

	debug 1, "uid_initialize <$mandant_id> <$kundennr> <$buchtype>";

	$buchsymbol = "KA" if $buchtype != BUCH_TYPE_AR && $buchtype != BUCH_TYPE_ER;

	my $learned_aref = uid_read_learned_data ($mandant_id, $buchsymbol, $kundennr, $rpc_server);
	uid_read_system_wide_file ();

	uid_read_invalid ();

	return $learned_aref;

}

################################################################################

sub uid_write_files {
	uid_update_system_wide_file ();
	uid_update_system_wide_invalid_file ();
}

my %STEUER_IN_LAND =( 


	"AT", [20, 13, 10, 0],				#Österreich
	"DE", [19, 7, 0],				#Deutschland
	"BE", [21, 12, 6, 0],				#Belgien
	"DK", [25, 0],					#Dänemark
	"FI", [24, 14, 10, 0],				#Finnland
	"HU", [27, 18, 5, 0],				#Ungarn
	"CZ", [21, 15, 10, 0],				#Tschechien
	"EE", [20, 9, 0],				#Estland
	"NL", [21, 6, 0],				#Niederlande
	"BG", [20, 9, 0],				#Bulgarien
	"HR", [25, 13, 5, 0],				#Kroatien
	"IT", [22, 10, 4, 0],				#Italien
	"SE", [25, 12, 6, 0],				#Schweden
	"FR", [20, 10, 5.5, 2.1, 0],			#Frankreich
	"EL", [24, 13, 6, 0],				#Griechenland oder auch GR
	"GR", [24, 13, 6, 0],				#Griechenland oder auch EL
	"IE", [23, 13.5, 9, 4.8, 0],			#Irland
	"LV", [21, 12, 5, 0],				#Lettland
	"LT", [21, 9, 5, 0],				#Litauen
	"LU", [17, 14, 8, 3, 0],			#Luxemburg
	"MT", [18, 7, 5, 0]	,			#Malta
	"PL", [23, 8, 5, 0],				#Polen
	"PT", [23, 22, 18, 13, 12, 9, 6, 5, 4, 0],	#Portugal [23, 13, 6, 0] 	#Azoren [18, 9, 4, 0] 	#Madeira [22, 12, 5, 0]
	"RO", [19, 9, 5, 0],				#Rumänien
	"SK", [20, 10, 0],				#Slowakei
	"SI", [22, 9.5, 0],				#Slowenien
	"ES", [21, 10, 4, 0],				#Spanien
	"GB", [20, 5, 0],				#England
	"CY", [19, 9, 5, 0],				#Zypern
	"XX", [20,10,13,0]		# fallback AT
	);



################################################################################


sub uid_get_steuer_in_land {
	return \%STEUER_IN_LAND;
}

sub uid_get_steuer_percentage {
	my $uid = shift;

	my $country = substr ($uid, 0, 2);		# get land
	$country = "XX" if !$country || !exists $STEUER_IN_LAND{$country};

	my @s = @{$STEUER_IN_LAND{$country}};
	#print "*$country  ";
	my $s_normal = $s[0];
	my $s_reduziert = $s[$#s-1];


	return ($s_normal, $s_reduziert);

}



sub uid_get_steuer_in_land {
	return \%STEUER_IN_LAND;
}



1;

