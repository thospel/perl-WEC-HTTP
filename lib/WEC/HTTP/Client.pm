package WEC::HTTP::Client;
use 5.006;
use strict;
use warnings;
use Carp;

use WEC::HTTP::Connection::Client;
use WEC::HTTP::Constants qw(PORT);

our $VERSION = '1.000';

our @CARP_NOT	= qw(WEC::FieldClient);

use base qw(WEC::Client);

my $default_options = {
    %{__PACKAGE__->SUPER::client_options},
};

sub default_options {
    return $default_options;
}

sub connection_class {
    return "WEC::HTTP::Connection::Client";
}

1;
