package WEC::HTTP::Connection;
use 5.006;
use strict;
use warnings;
use Carp;

use base qw(WEC::Connection);
our @CARP_NOT = qw(WEC::FieldConnection);

my $CR	 = "\x0d";
my $LF	 = "\x0a";
my $CRLF = "$CR$LF";

sub want_line {
    # Probably should check for line getting too long here
    my __PACKAGE__ $connection = shift;
    my $pos = index $_, $LF, $connection->{in_want}-1;
    if ($pos < 0) {
	$connection->{in_want} = 1+length;
	return;
    }
    my $line = substr($_, 0, $pos+1, "");
    $connection->{in_want} = 1;
    $line =~ s/($CR?$LF)\z//o or croak "Incomplete line";
    my $eol = $1;
    $connection->{in_state}->($connection, $line, $eol);
}

sub _drop_request {
    my __PACKAGE__ $connection = shift;
    my $request = shift;
    @{$connection->{requests}} || croak "No request, so can't drop any";
    $connection->{requests}[0] == $request ||
	croak "Trying to drop request $request, but I start with $connection->{requests}[0]";
    shift @{$connection->{requests}};
    # avoid accidental keepalive because shift returns the value
    return;
}

1;
