#!/usr/bin/perl -w
use strict;

my $port = 1234;
# my $host = "tcp://dellc640:$port";
my $host = "tcp://www.xs4all.nl:80";

use lib "/home/ton/perl-modules/WEC-HTTP/blib/lib";
use WEC qw(api=1 loop HTTP::Client);

WEC->init;
my $client = WEC::HTTP::Client->new();
my $connection = $client->connect($host);
$connection->GET(callback => \&got, 
                 uri	=> "http://www.xs4all.nl/");

my $body = "hdwd=bar&listword=bar&book=Dictionary&jump=bar%5B1%2Cnoun%5D&list=bar%5B1%2Cnoun%5D%3D76925%3Bbar%5B2%2Ctransitive+verb%5D%3D76942%3Bbar%5B3%2Cpreposition%5D%3D76968%3Bbar%5B4%2Cnoun%5D%3D76990%3Bbar%3D1376971%3BBar%3D1376983%3BBAr%3D1376995%3BBAR%3D1377006%3Banti-roll+bar%3D43063%3Bbar-%3D77005";

$connection = $client->connect("tcp://www.m-w.com:80");
$connection->POST(callback => \&posted, 
                  uri	=> "http://www.m-w.com/cgi-bin/dictionary", 
                  content_type => "application/x-www-form-urlencoded",
                  body	=> $body);

loop();

use Data::Dumper;

sub got {
    my $request = shift;
    print STDERR $request->raw_response_headers, "----\n";
}

sub posted {
    my $request = shift;
    print STDERR $request->raw_response_headers, "----\n";
    print STDERR $request->response_body, "----\n";
}
