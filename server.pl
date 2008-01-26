#!/usr/bin/perl -w
use strict;

my $port = 1234;

use lib "/home/tonh/perl-modules/WEC-HTTP/blib/lib";
use WEC qw(api=1 loop HTTP::Server);
use WEC::Socket qw(inet);

WEC->init;
my $n;
my $socket = inet(LocalPort => $port,
		  ReuseAddr => 1);
my $server = WEC::HTTP::Server->new(Handle => $socket,
				    GET	 => \&get,
				    POST => \&post);
loop();

use Data::Dumper;

sub get {
    my $request = shift;
    $request->respond(body => "<HTML><HEAD><TITLE>Foo</TITLE></HEAD><BODY>Waf</BODY></HTML>");
}

sub post {
    my $request = shift;
    $request->respond(body => "<HTML><HEAD><TITLE>Bar</TITLE></HEAD><BODY>Zoem</BODY></HTML>");
}
