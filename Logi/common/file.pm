#!/usr/bin/perl 

package Logi::common::file;

use strict;

use POSIX qw(strtod setlocale LC_NUMERIC);
use Data::Dumper;
use Math::Round;
use File::Basename;
use Logi::common::Utils;
use locale;
use DateTime;
use DateTime::Format::Strptime;
use Fcntl qw ( LOCK_EX SEEK_SET );
#use Image::Size;
use Cwd;
use Logi::rpc::rpc;
use Exporter qw(import);
our @EXPORT = qw(write_status init_status read_kunden_uid update_kundenBelege zbarimg generate_pdf_file create_files_for_high_and_pdf create_rg_files get_transaction_id write_transaction_log
	create_result_pdf_files create_rg_files_from_csv);

my $FH_DBG;
my $FH_STATUS;

use constant STATUS_INIT => 1;
use constant STATUS_RUNNING => 2;
use constant STATUS_GENERATE_FILES => 3;
use constant STATUS_BUNDLE => 4;
use constant STATUS_FIN => 99;
use constant STATUS_DIE => 999;

################################################################################

sub flush {
	my $h = select($_[0]); my $af=$|; $|=1; $|=$af; select($h);
}
################################################################################

sub write_status {
	return if (!$FH_STATUS);
		
	my ($state, $current_fileno, $number_files, $text) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();

	printf $FH_STATUS "%04d-%02d-%02d %02d:%02d:%02d;$$;$state;$current_fileno;$number_files;$text\n",
		$year+1900,$mon+1,$mday,$hour,$min, $sec;
	flush $FH_STATUS;

}

sub init_status {
	my $mandant_id = shift;
	my $kundennr = shift;
	my $buchsymbol = shift;
	my $status_file = shift;

	open ($FH_STATUS, '>', "$status_file") or return 0;
	write_status (STATUS_INIT, 0, 0,  "$mandant_id:$kundennr:$buchsymbol:Initialize");

	flush $FH_STATUS;

	return 1;
}

################################################################################

sub debug {
	Logi::common::Utils::debug $FH_DBG, @_;
}

sub read_kunden_uid {
	my $FH_DBG_in = shift;
	my $CONFIGDIR = shift;
	my $filename = shift;	# nur file ohne mandant ohne csv
	my $mandant = shift;
	my $kundennr = shift;
	my $rpc_server = shift;

	my $e_a=0;
	my $no_ust = 0;
	my $is_quartal = 0;

	$FH_DBG = $FH_DBG_in;

	if ($rpc_server) {
		my $res = my ($kundennr_in, $name, $uid, $e_a, $no_ust, $is_quartal, $fibunr) = rpc_get_kunden_daten ($FH_DBG, $mandant,  $kundennr, $rpc_server);
		if ($res == 7) {		# 7 now with kundennr
			debug 1, "read_kunden_uid: $name $uid $e_a $no_ust $is_quartal $fibunr";
			return ($uid, $e_a, $no_ust, $is_quartal, $name, $fibunr);
		} else {
			debug 1, "ERROR: read_kunden_uid: no RPC result ($res) --> go on file";
		}
	}


	my $fname = "$CONFIGDIR/$filename" ."_$mandant.csv";
	my $FH_KDN;
	if (!open ($FH_KDN, '<', $fname )) {
		debug 1, "cannot open kundenfile $fname";
		return ("", 0, 0, 0, "", "");
	}

	while (<$FH_KDN>) {

		chop;
		#my ($kdnr, $name, $uid, $res, $gewinn_ermittlung, $UstErmittlung, $uva) = split /;/;
		my ($kdnr, $name, $uid, $reserved, $e_a, $no_ust, $is_quartal, $fibunr) = split /;/;

		if ($kdnr eq $kundennr) {
			close $FH_KDN;
			return ($uid, $e_a, $no_ust, $is_quartal, $name, $fibunr);
		}
	}
	close $FH_KDN;

	return ("", 0, 0, 0, "", "");		# return non existing ATU

}

##################################################


sub update_kundenBelege {
	my ($FH_DBG_in, $filename, $mandant_id, $kundennr, $total_belege) = @_;

	$FH_DBG = $FH_DBG_in;

	debug 3, "update_kundenBelege <$mandant_id> <$kundennr> <$total_belege>";

	my %kunden_hash = ();

	open (my $FH_KDN, '+<', $filename ) or return 1;
	flock $FH_KDN, LOCK_EX;


	while ( <$FH_KDN>) {
		chomp;
		my ($f_mandant_id,  $f_kundennr, $f_belegnr) = split /;/;
		$kunden_hash {"$f_mandant_id;$f_kundennr"} = $f_belegnr;
	}
	$kunden_hash {"$mandant_id;$kundennr"} = $kunden_hash {"$mandant_id;$kundennr"} + $total_belege;

	seek $FH_KDN, 0, SEEK_SET;
	truncate $FH_KDN, 0;

	foreach my $entry (sort keys %kunden_hash) {
		print $FH_KDN "$entry;$kunden_hash{$entry}\n";
	}
	close $FH_KDN;
}

################################################################################


sub find_barcodes_on_file {
	my $OUT_FH = shift;
	my $filename=shift;
	my $denoise_cmd = shift;

	#print "\tzbarimg $filename\n";

	open my $old_stdout, ">&STDOUT";

	my $tmpfile="";
	my ($name, $path, $suffix) = fileparse($filename, '\.[^\.]*');
	my $fname="$path$name";

	$tmpfile = "$path/$name"."_den$suffix";

	my $qr_out = "qr_$$.out";
	open STDOUT, '>', $qr_out;
	select STDOUT;

	my @cmd = ("zbarimg", "-q", "$filename");

	system (@cmd);

	my @den_cmd = ($denoise_cmd, "--median", "3", "--thicken", "--vert", "0",  "--hor", "0", "--trash",  "3.0",  
		"$filename", "$tmpfile");
	0 == system (@den_cmd) or die "****** Fehler bei denoise $filename";

	@cmd = ("zbarimg", "-q", "$tmpfile");
	system (@cmd);

	open STDOUT, ">&", $old_stdout;

	open my $FH_ZBAR, '<', $qr_out;

	my $barcode="";
	while (<$FH_ZBAR>) {
		$barcode .= $_;
	}
	$barcode =~ s/\n/ /g;
	print $OUT_FH "$filename;$barcode\n" if $barcode;
	close $FH_ZBAR;
	unlink $qr_out;
	unlink $tmpfile;

	return $barcode;


}

sub find_barcodes {
	my $WORKDIR=shift;
	my $filemask=shift;
	my $denoise_cmd = shift;
	

	my @png_files = glob ($filemask);

	my $output_file="$WORKDIR/output_$$.txt";

	open (my $OUT_FH, ">$output_file");


	foreach my $png_file (@png_files) {
		my $pid;
		next if $pid = fork;    # Parent goes to next server.
		die "fork failed: $!" unless defined $pid;

		# From here on, we're in the child.  Do whatever the
		# child has to do...  The server we want to deal
		# with is in $server.
		#print "working on $png_file\n";

		find_barcodes_on_file ($OUT_FH, $png_file, $denoise_cmd);
		#print "... $png_file finished\n";

		exit;  # Ends the child process.
	}

	# The following waits until all child processes have
	# finished, before allowing the parent to die.

	1 while (wait() != -1);

	close $OUT_FH;

	open ($OUT_FH, "<$output_file");

	my %barcodes=();

	while (<$OUT_FH>) {
		chop;
		my ($fname, $barcode) = split /;/;
		$barcodes{$fname}=$barcode;
	}
	close $OUT_FH;
	unlink $output_file;

	return \%barcodes;
}





sub zbarimg {
	my $filename=shift;
	my $denoise_cmd = shift;

	debug 3, "\tzbarimg $filename";

	open my $old_stdout, ">&STDOUT";

	my $tmpfile="";
	my ($name, $path, $suffix) = fileparse($filename, '\.[^\.]*');
	my $fname="$path$name";

	$tmpfile = "$path/$name"."_den$suffix";

	my $qr_out = "qr_$$.out";
	open STDOUT, '>', $qr_out;
	select STDOUT;

	my @cmd = ("zbarimg", "-q", "$filename");
	if (system (@cmd)) {		# kein barcode gefunden
		# $tmpfile = "qr_$$.tif";
		my @den_cmd = ("python", "$denoise_cmd", "--median", "3", "--thicken", "--vert", "0",  "--hor", "0", "--trash",  "3.0",  
			"$filename", "$tmpfile");
		0 == system (@den_cmd) or die "****** Fehler bei denoise $filename";

		my @cmd = ("zbarimg", "-q", "$tmpfile");
		system (@cmd);
		debug 2, "\tzbarimg $filename 2nd try";
	}
	open STDOUT, ">&", $old_stdout;

	open my $FH_ZBAR, '<', $qr_out;

	my $barcode="";
	while (<$FH_ZBAR>) {
		$barcode .= $_;
	}
	debug 3, "barcode: $barcode";
	close $FH_ZBAR;
	unlink $qr_out;
	unlink $tmpfile;

	return $barcode;


}

################################################################################

sub generate_pdf_file {
	my $FH_DBG_in = shift;
	my $source_file_tiff = shift;
	my $source_file_pdf = shift;
	my $dest_file = shift;
	my $ocr_string = shift;
	my $coords = shift;
	my $pid = shift;
	my $highlight_cmd = shift;

	$FH_DBG = $FH_DBG_in;

	debug 3, "generate_pdf_file $source_file_tiff $source_file_pdf $dest_file";

	my ($fname, $path, $suffix) = fileparse($source_file_tiff, '\.[^\.]*');

	my $highlight_file="";
	my $textfile="";

	debug 1,  "\tErstelle Rechnungsfile: cp file from $source_file_tiff to $dest_file";

	if  ($coords) {
		debug 3, "generate_pdf: we have coords: $coords";

		$highlight_file = "high_$$";		# braucht nicht eindeutig sein!

		my $cmd = ("python  $highlight_cmd $source_file_tiff $highlight_file.tif $coords");
		0 == system ($cmd) or return 0;

		# convert to pdf

		my @cmd_tiff2pdf = ("tiff2pdf",  "-z",  "$highlight_file.tif", "-o", "$highlight_file.pdf");
		0 == system (@cmd_tiff2pdf) or return 0;

	}

	if ("$ocr_string" ) {	# existiert ein out-file?

		# find max line length

		my $max_line_length = 0;
		while ($ocr_string =~ /.*\n/g) {
			$max_line_length = length ($&) if length ($&) > $max_line_length;
		}

		$max_line_length += 2;	# zur sicherheit
			debug 3, "max_line_length: $max_line_length";

		$textfile="text_$$";

		open (my $fh, "|a2ps --stdin=$fname --delegate=no --quiet --header= --columns=1 --sides=1 --portrait --chars-per-line=$max_line_length -o -|ps2pdf - $textfile.pdf") or return 0;
		print $fh $ocr_string;
		close $fh;

	}

	# convert all rg to pdf

	my $pdf_file="";
	if ($source_file_pdf) {
		$pdf_file = $source_file_pdf;
		debug 1, "generate_pdf: pdf file $pdf_file exists";
	} else {
		# convert ist langsam, nur verwenden wenn compressed jpg
		$pdf_file = "$fname"."_ori2.pdf";
		my $tiffinfo = `tiffinfo $fname.tif`;
		my @cmd_tiff2pdf = ();
		if ($tiffinfo =~ /Compress.*JPEG/i) {
			debug 1, "Compressed JPEG --> use convert";
			@cmd_tiff2pdf = ("convert", "$fname.tif", $pdf_file);
		} else {
			@cmd_tiff2pdf = ("tiff2pdf",  "-z", "$fname.tif", "-o", $pdf_file);	# AR 2018-09-14 --> tiff2pdf geht nicht bei allen files/compressed jpg !!
		}
		0 == system (@cmd_tiff2pdf) or return 0;
	}

	# all files together: highlighted, text, orig
	my @cmd = ("pdftk");

	push @cmd, "$highlight_file.pdf" if $highlight_file;
	push @cmd, "$pdf_file";
	push @cmd, "$textfile.pdf" if $textfile;
	push @cmd, ("cat", "output", "$dest_file");

	0 == system (@cmd) or return 0;

	unlink "$highlight_file.pdf";
	unlink "$highlight_file.tif";
	#unlink "pdf_file";
	unlink "$textfile.pdf";

	return 1;

}

################################################################################

sub create_files_for_high_and_pdf {

	my $FH_DBG_in = shift;
	my $filelist_href = shift;
	my $pdf_filelist_href = shift;
	my $tiff_filelist_href = shift;
	my $WORKDIR = shift;
	my $pid = shift;

	$FH_DBG = $FH_DBG_in;
	my $is_tiff = 1;


	my $newfname;

	foreach my $source_file (keys %$filelist_href) {
		if ( "$source_file" =~/\.tif+$/i ) {
			$is_tiff=1;
		} elsif ( "$source_file" =~ /\.pdf$/i) {
			$is_tiff=0;
		} else {
			debug 1, "ERROR: invalid file format $source_file";
			return 0;
		}

		debug 2, "create_files_for_high: $source_file $is_tiff";

		foreach my $rg_nr (keys %{$filelist_href->{$source_file}}) {
			my @fl = ();	# filelist for tiff files
			my @pages = ();	# page list for pdf files

			foreach my $single_page (@{$filelist_href->{$source_file}->{$rg_nr}}) {
				my ($file,$page) = @{$single_page};
				push @fl, $file;
				push @pages, $page if (!$is_tiff);
			}
			# compose files now, tiff we need for all for highlight

			# TODO: error handling missing!

			$newfname = sprintf ("$WORKDIR/rg_%08d", $rg_nr);
			my $new_pdf_fname = "$newfname"."_orig.pdf";
			$tiff_filelist_href->{$rg_nr} = "$newfname.tif";
			$pdf_filelist_href->{$rg_nr} = $new_pdf_fname if !$is_tiff;

			my $pid;
			next if $pid = fork;    # Parent goes to next file.
			die "fork failed: $!" unless defined $pid;

			#### child now #####

			debug 1, "\tjoin files to rg: @fl to $newfname.tif";
			my @convert_cmd = ("tiffcp", @fl, "$newfname.tif");
			if (system (@convert_cmd)) {
				debug 1, "error on @convert_cmd";
				return 0;
			}

			if (!$is_tiff) {		# take out original pdf from 
				debug 3, "\tcreate pdf  file $source_file to $newfname.pdf";

				my @convert_cmd = ("pdftk", "$source_file", "cat", @pages, "output", $new_pdf_fname);
				debug 2, "create pdf file @convert_cmd";
				if (system (@convert_cmd)) {
					debug 1, "current wd: ", getcwd ();
					debug 1, "error on @convert_cmd";
					return 0;
				}
			}
			exit;
		}
	}
	1 while (wait() != -1);
	debug 3, "return 1";
	return 1;

}

################################################################################

sub create_result_pdf_files {

	my $FH_DBG_in = shift;
	my $conf = shift;

	my $filelist_href = shift;
	my $tiff_filelist_href = shift;
	my $pdf_filelist_href = shift;
	my $ocr_strings_href = shift;
	my $coords_href = shift;

	my $WORKDIR = shift;
	my $pid = shift;

	$FH_DBG = $FH_DBG_in;
	my $is_tiff = 1;

	my %result_pdf_files = ();


	my $newfname;

	foreach my $source_file (keys %$filelist_href) {

		foreach my $rg_nr (keys %{$filelist_href->{$source_file}}) {

			my $final_pdf_file = sprintf ("$conf->{WORKDIR}/rg_%08d.pdf", $rg_nr);
			$result_pdf_files{$rg_nr} = $final_pdf_file;

			my $pid;
			next if $pid = fork;    # Parent goes to next file.
			die "fork failed: $!" unless defined $pid;


			generate_pdf_file ($FH_DBG, $tiff_filelist_href->{$rg_nr},
					$pdf_filelist_href->{$rg_nr},
					$final_pdf_file, 
					$ocr_strings_href->{$rg_nr},
					$coords_href->{$rg_nr},
					0,		# not used any more
					$conf->{HIGH_CMD}) or die "generate_pdf $final_pdf_file";


			exit;
		}
	}
	1 while (wait() != -1);

	return \%result_pdf_files;

}
################################################################################

sub create_rg_files_from_csv {
	my $FH_DBG_in = shift;
	my $tmp_filelist_href = shift;
	my $tmp_barcode_href= shift;
	my $TRANSACTION_ID_FILE=shift;
	my $WORKDIR = shift;

	my %filelist = ();
	my %barcodes = ();

	my $pid = $$;
	my $infile_count =1;


	#$FH_DBG = $FH_DBG_in;

	debug 2,  "create_rg_files_from_csv\n";

	foreach my $source_file (keys %$tmp_filelist_href) {





		my ($name, $path, $suffix) = fileparse($source_file, '\.[^\.]*');
		my $fname="$path$name";
		my $is_tiff=1;

		return 0 if ! -f $source_file;

		if ( "$suffix" =~/\.tif+/i ) {
			$is_tiff=1;
		} elsif ( "$suffix" =~ /\.pdf/i) {
			$is_tiff=0;
		} else {
			return 0;
		}

		my $tmp_img_file="$WORKDIR/tmp$pid"."_$infile_count"."_";

		if ($is_tiff) {
			debug 1, "tiffsplit $name$suffix";
			my @tiff_cmd = ("tiffsplit", "$source_file", $tmp_img_file);
			if (system (@tiff_cmd)) {
				#debug 1, "ERROR: @tiff_cmd";
				return 0;
			}
		} else {
			debug 1, "pdfsplit $name$suffix";
			my @pdf_cmd = ("pdftocairo", "-r", "300", "-tiff", "-gray", "$source_file", $tmp_img_file);
			if (system (@pdf_cmd)) {
				#debug 1, "ERROR: @pdf_cmd";
				return 0;
			}
		}


		my @tmpfiles = glob ("$WORKDIR/tmp$pid"."_$infile_count*");	

		# rg_nr: from file, from 1 .. xx 
		# rg_seq: unique new id

		for my $rg_nr (sort {$a <=> $b} keys %{$tmp_filelist_href->{$source_file}}) {
			debug 2,  "source_file: $source_file $rg_nr\n";
			my $rg_seq = get_transaction_id ($TRANSACTION_ID_FILE);

			for my $page (sort {$a <=> $b} @{$tmp_filelist_href->{$source_file}->{$rg_nr}}) {
				debug 2,  "\tpage $page: ", $tmpfiles[$page-1], "\n";
				push @{$filelist{$source_file}{$rg_seq}}, [ $tmpfiles[$page-1], $page];
				$barcodes{$rg_seq} = $barcodes{$rg_nr} if $barcodes{$rg_nr};		# move to new id's
			}
		}
		$infile_count ++;
	}

	return (\%filelist, \%barcodes);


}
################################################################################

sub create_rg_files {
	my $FH_DBG_in = shift;
	my $TRANSACTION_ID_FILE=shift;
	my $WORKDIR = shift;
	my $source_file = shift;
	my $infile_count = shift;		# extension for file
	# my $rg_nr = shift;
	my $with_empty_pages = shift;
	my $single_invoice = shift;
	my $pid = shift;
	my $filelist_href = shift;
	my $barcodes_href = shift;
	my $denoise_cmd = shift;

	my $barcode_count=0;		# falls einzelrechnung: kein split bei jeder seite
	my $newfname;
	my $tsv_file = "";		# pdf file has text --> generate tsv file

	$FH_DBG = $FH_DBG_in;

	my ($name, $path, $suffix) = fileparse($source_file, '\.[^\.]*');
	my $fname="$path$name";
	my $is_tiff=1;

	return 0 if ! -f $source_file;

	if ( "$suffix" =~/\.tif+/i ) {
		$is_tiff=1;
	} elsif ( "$suffix" =~ /\.pdf/i) {
		$is_tiff=0;
	} else {
		return 0;
	}

	my $tmp_img_file="$WORKDIR/tmp$pid"."_$infile_count"."_";

	if ($is_tiff) {
		debug 1, "tiffsplit $name$suffix";
		my @tiff_cmd = ("tiffsplit", "$source_file", $tmp_img_file);
		if (system (@tiff_cmd)) {
			debug 1, "ERROR: @tiff_cmd";
			return 0;
		}
	} else {
		debug 1, "pdfsplit $name$suffix";
		# my @pdf_cmd = ("gs", "-q", "-dNOPAUSE", "-r300", "-sDEVICE=tiffg4", 	# AR 2018-09-16 tiffgray riesige files sometimes
		#my @pdf_cmd = ("gs", "-q", "-dNOPAUSE", "-r300", "-sDEVICE=tiffgray", 	# AR 2018-09-16 tiffgray riesige files sometimes
		#	"-sOutputFile=$output_file", "$source_file", "-c", "quit");
		#my @pdf_cmd = ("pdftocairo", "-r", "300", "-tiff", "-mono", "$source_file", $tmp_img_file);
		my @pdf_cmd = ("pdftocairo", "-r", "300", "-tiff", "-gray", "$source_file", $tmp_img_file);
		if (system (@pdf_cmd)) {
			debug 1, "ERROR: @pdf_cmd";
			return 0;
		}
	}

	# ab hier weiter nur bei multiple invoices

	my $rg_nr = get_transaction_id ($TRANSACTION_ID_FILE);

	debug 1, "\tErstelle Rechnungsfiles $source_file ($rg_nr) with_empty: $with_empty_pages single_invoice: $single_invoice";

	my @tmpfiles = glob ("$WORKDIR/tmp$pid"."_$infile_count*");	
	debug 3, "tmpfiles: @tmpfiles";
	my @rg_file_arr =();

	my $number_of_files = scalar @tmpfiles;
	my $page_counter = 1;

	my $tmp_barcodes_href = find_barcodes ($WORKDIR, "$WORKDIR/tmp$pid"."_$infile_count*", $denoise_cmd);
#	foreach my $file (keys %{$tmp_barcodes_href}) {
#		debug 2,  "barcodes: $file\t$tmp_barcodes_href->{$file}";
#	}


	foreach my $fname (@tmpfiles ) { 

		# leerseite --> nicht!!
		my $fsize = -s $fname;

		debug 3, "working on $fname/$fsize";

		# empty page detection

		if ($with_empty_pages) {

			my $is_empty=0;
			if ($fsize < 10000) {
				if ($fsize < 1000) {
					debug 1, "\t\t--> EMPTY $fname($page_counter) (size $fsize)";
					$is_empty = 1;;
				} else {
					my $is_empty_cmd = "convert $fname -shave 300x0 -virtual-pixel White -blur 0x15 -fuzz 15% -trim info:";
					open my $CMD,'-|', "$is_empty_cmd" or return 0;
					my $result = "";

					while (<$CMD>) {
						$result .= $_;
					}
					close $CMD;

					# ergebnis: something like tmp8690_0128.tif[128] TIFF 58x1070 72x1472+6+247 1-bit Gray 0.010u 0:00.010
					debug 3, "empty result: $result";
					if ($result =~ /TIFF\h(\d+)x(\d+)\h/) {
						debug 3, "s * y: $1/$2";
						if ($1 < 30 || $2 < 30) {
							debug 1, "\t\t--> EMPTY $fname($page_counter) (convert <30 ($1/$2))";
							$is_empty = 1;;
						} else {
							debug 1, "\t\†--> NOT EMPTY $fname($page_counter) (convert $1/$2)";
						}
					}
				}
			} else {
				debug 1, "\t\t--> NOT EMPTY $fname($page_counter) (size $fsize)";
			}

			if ($is_empty) {
				#write_status (STATUS_INIT, $page_counter, $number_of_files,  "Seitentrennung Datei $infile_count: $page_counter/$number_of_files (EMPTY)");
				$page_counter ++;
				next;
			}
		}
		#write_status (STATUS_INIT, $page_counter, $number_of_files,  "Seitentrennung Datei $infile_count: $page_counter/$number_of_files");

		#my $barcode = zbarimg ($fname, $denoise_cmd) if (!$single_invoice || $page_counter == 1);             # single invoices only page 1
		my $barcode = $tmp_barcodes_href->{$fname} if exists $tmp_barcodes_href->{$fname};
		debug 1, "BARCODE: <$barcode> $fname";

			$newfname = sprintf ("$WORKDIR/rg_%08d.tif", $rg_nr);

		if (!$single_invoice && $barcode =~ /CODE-128:Wikipedia|[12]LOGISTH\.?AI/) {		# seitensplit
			debug 1, "\tTrennbarcode $&  found $fname";

			# nur +1 wenn rg erstellt (letzte seite könnte leerbarcode sein)
			# nicht bei erster barcode seite!
			#$rg_nr ++ if $page_counter > 1 && $barcode_count &&  exists $filelist_href->{$source_file}->{$rg_nr}; 	
			$rg_nr = get_transaction_id ($TRANSACTION_ID_FILE) if $page_counter > 1 && $barcode_count &&  exists $filelist_href->{$source_file}->{$rg_nr}; 	

			$barcode_count++;

			if ($barcode !~ /2LOGISTH\.?AI/) {	# keine weitere bearbeitung wenn barcode auf einzelseite
				$page_counter ++;
				next;
			}
			# next if ($barcode !~ /2LOGISTH\.?AI/);	# keine weitere bearbeitung wenn barcode auf einzelseite

			push @{$filelist_href->{$source_file}->{$rg_nr}}, [ $fname, $page_counter] if ($barcode =~ /2LOGISTH\.?AI/);	# only when on page


		} 

		$barcodes_href->{$rg_nr} .= " $barcode" if $barcode;	# concat all barcodes of all pages

		push @{$filelist_href->{$source_file}->{$rg_nr}}, [ $fname, $page_counter];

		#$rg_nr ++ if (!$single_invoice && !$barcode_count);	# bis zum ersten barcode einzelseiten
		$rg_nr = get_transaction_id ($TRANSACTION_ID_FILE) if (!$single_invoice && !$barcode_count);	# bis zum ersten barcode einzelseiten

		$page_counter ++;
	}
	# build the rg-files

	# $rg_nr++ if exists $filelist_href->{$source_file}->{$rg_nr}; 	#  nur +1 wenn rg erstellt (letzte seite könnte leerbarcode sein 


}

################################################################################

sub get_transaction_id {
	my $transaction_file = shift;

	my $openmode="+<";
	$openmode="+>" if !-f $transaction_file;
	open (my $FH_TRANS, "$openmode", $transaction_file ) or return 1;
	flock $FH_TRANS, LOCK_EX;

	my $last_id = <$FH_TRANS>;
	$last_id ++;

	seek $FH_TRANS, 0, SEEK_SET;
	truncate $FH_TRANS, 0;

	print $FH_TRANS $last_id;

	close $FH_TRANS;
	return $last_id;
}


##################################################



sub write_transaction_log {
	my $FH_DBG = shift;
	my $mandant = shift;
	my $t_file = shift;
	my $rpc_server = shift;
	my $transaction_aref = shift;

	open (my $FH_TRANS_LOG, '>>', $t_file) or return 0;
	flock $FH_TRANS_LOG, LOCK_EX;
	foreach my $entry (@$transaction_aref) {
		printf $FH_TRANS_LOG "$entry\n";
	}
	close $FH_TRANS_LOG;

	rpc_write_transaction_log ($FH_DBG, $mandant, $rpc_server, $transaction_aref) if ($rpc_server);


	return 1;
}


1;
