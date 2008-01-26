#!/usr/bin/perl -w
use strict;
use Socket qw(inet_aton inet_ntoa);
use HTML::Entities;

# Put wherever you compiled WEC-HTTP here. Or drop it if you install the module
use lib "/home/ton/perl-modules/WEC-HTTP/blib/lib";
use WEC qw(api=1 loop HTTP::Client);

WEC->init;
my $client = WEC::HTTP::Client->new();

my $max_fetches = 256;
my (%www, %fetched);

@ARGV = ("slashdot.org") if !@ARGV;
for my $host (@ARGV) {
    defined(my $packed_ip = inet_aton($host)) || 
        die "Could not resolve '$host'\n";
    my $ip = inet_ntoa($packed_ip);
    my $www = "tcp://$ip:80";
    $www{$host} = $www;

    my $connection = $client->connect($www);
    $connection->GET(callback => \&got,
                     uri	=> "http://$host/");
    $fetched{"http://$host/"} = 1;
}
loop();

sub got {
    my ($request) = @_;
    my $base = $request->uri;
    print STDERR "Got <$base>\n";
    my $body = $request->response_body;
    # print STDERR "<$body>\n";
    # Put a real parser here...
    my @refs = $body =~ /<a\s+href=\"([^\"]+)+\"/ig;	# "
    for my $ref (@refs) {
        last if keys %fetched >= $max_fetches;
        decode_entities($ref);
        my $uri = URI->new_abs($ref, $base);
        $uri->fragment(undef);
        # print STDERR "$uri\n";
        next if $fetched{$uri} || $uri->scheme ne "http";
        my $www = $www{$uri->host} || next;
        $fetched{$uri} = 1;
        # Notice that the connect method is non-blocking
        my $connection = $client->connect($www);
        $connection->GET(callback => \&got, uri => $uri);
    }
}
