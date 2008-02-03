package WEC::HTTP::Server;
use 5.006;
use strict;
use warnings;
use Carp;

use WEC::HTTP::Connection::Server;
use WEC::HTTP::Constants qw(PORT);

our $VERSION = '1.000';
our @CARP_NOT	= qw(WEC::FieldServer);

use base qw(WEC::Server);

my $default_options = {
    %{__PACKAGE__->SUPER::server_options},
    GET	=> undef,
    POST => undef,
};

sub default_options {
    return $default_options;
}

sub default_port {
    return PORT;
}

sub connection_class {
    return "WEC::HTTP::Connection::Server";
}

1;
