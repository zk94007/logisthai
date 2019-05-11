package Logi::rpc::Data;

use strict;
use warnings;

our @EXPORT_OK = qw(new set_function get_function add_data get_files);

# init product with serial, name and price
sub new {
	my ( $class ) = @_;
	my $self = bless {
		files  => [],
		function => '',
	}, $class;
}

sub add_file {
	 my($self, $file) = @_;
	 
	 push @{$self->{'files'}}, $file;
}

sub set_files {
	 my($self, $files) = @_;
	 
	 $self->{'files'} = $files;
}

sub set_function {
	 my($self, $function) = @_;
	 
	 $self->{'function'} = $function;
}

sub get_function {
	 my($self) = @_;
	 
	 return $self->{'function'};
}


sub add_data {
	 my($self, $name, $value) = @_;
	 $self->{'data'}->{$name} = $value;
}

sub get_files {
	my($self) = @_;
	
	return $self->{'files'};
}

sub get_data {
	my($self) = @_;
	
	return $self->{'data'};
} 

sub TO_JSON { return { %{ shift() } }; }
1;
