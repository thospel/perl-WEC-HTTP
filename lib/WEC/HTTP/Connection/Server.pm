package WEC::HTTP::Connection::Server;
use 5.006;
use strict;
use warnings;
use Carp;
use Email::Simple;

our $VERSION = '1.000';

use WEC::HTTP::Request;
use base qw(WEC::HTTP::Connection);

our @CARP_NOT = qw(WEC::FieldConnection);

my $CR	 = "\x0d";
my $LF	 = "\x0a";
my $CRLF = "$CR$LF";

# rfc 2068, 2.2
my $TOKEN = qr![^()<>\@,;:\\\"/\[\]?={} \t\x00-\x1f\x7f]+!; # "

sub init_server {
    my __PACKAGE__ $connection = shift;

    # No multiplexing in HTTP (not even with keep-alive)
    $connection->{host_mpx}	= 0;
    $connection->{peer_mpx}	= 0;

    $connection->{requests}	= [];
    $connection->{signature}	= "WEC::HTTP/$VERSION";
    $connection->{in_want}	= 1;
    $connection->{in_process}	= $connection->can("want_line") ||
        die "$connection has no want_line";
    $connection->{in_state}	= \&request_line;
}

sub new_request {
    my __PACKAGE__ $connection = shift;
    my $request = WEC::HTTP::Request->new($connection, @_);
    $request->{major} = -1;
    $request->{minor} = -1;
    $request->{http_version} = "";
    push @{$connection->{requests}}, $request;
    return $request;
}

sub request_line {
    (my __PACKAGE__ $connection, my $line, my $eol) = @_;
    # RFC2068, 4.1: servers SHOULD ignore any empty line(s) received where
    # a Request-Line is expected
    return if $line eq "";
    # RFC2068,, 5.1 Request-Line   = Method SP Request-URI SP HTTP-Version CRLF
    if (my ($method, $uri, $rest) =
	$line =~ /\A[ \t]*($TOKEN)[ \t]+([^ \t]+)[ \t]*(.*)\z/so) {
        my $request = $connection->new_request($method, $uri);
        $request->{raw_request_line} = $line . $eol;
        $request->{request_line} = $line;
	if ($rest eq "") {
	    if ($method eq "GET") {
		$connection->{in_want} = -1;
		$connection->request_body();
	    } else {
		$connection->{in_state}	= \&request_header;
		$request->{raw_headers}	= "";
	    }
	} else {
	    if (my ($major, $minor) = $rest =~ m!\AHTTP/(\d+)\.(\d+)\s*\z!i) {
		$request->{major} = $major+0;
		$request->{minor} = $minor+0;
	    } else {
		$request->error(400, "Can't parse HTTP version '$rest'");
		return;
	    }
	    $connection->{in_state}	= \&request_header;
	    $request->{raw_headers}	= "";
	    if ($request->{major} == 0) {
		if ($request->{minor} != 9 && $request->{minor} != 0) {
		    $request->error(400, "Don't know HTTP version $request->{major}/$request->{minor}");
		    return;
		}
	    } elsif ($request->{major} == 1) {
		if ($request->{minor} >= 2) {
		    $request->error(400, "Don't know HTTP version $request->{major}/$request->{minor}");
		    return;
		}
	    } else {
		$request->error(400, "Don't know HTTP version $request->{major}");
		return;
	    }
	    # Version is now 0.9, 1.0 or 1.1
	    $request->{http_version} =
		"HTTP/$request->{major}.$request->{minor}";
	}
    } else {
	# Can't parse request, fake a dummy one
        my $request = $connection->new_request;
	$request->error(400, "Can't parse Request-Line '$line'");
    }
}

sub request_header {
    (my __PACKAGE__ $connection, my $header, my $eol) = @_;
    my $request = $connection->{requests}[-1];

    $request->{raw_headers} .= $header;
    $request->{raw_headers} .= $eol;
    return if $header ne "";

    # rfc 2616, 4.3:
    # The presence of a message-body in a request is signaled by the
    # inclusion of a Content-Length or Transfer-Encoding header field in
    # the request's message-headers

    $request->{headers} = Email::Simple->new($request->{raw_headers});
    my $transfer_encoding = $request->{headers}->header("Transfer-Encoding");
    if (defined $transfer_encoding && $transfer_encoding ne "") {
        die "Transfer-Encoding not implemented";
        return;
    }
    my $length = $request->{headers}->header("Content-Length");
    if (defined($length) && $length ne "") {
        $length=~ /\A\s*\d+\s*\z/ ||
            croak "Could not parse length '$length'";
        $connection->{in_process} = \&request_body;
        $connection->{in_want} = $length+0;
        return;
    }
    $connection->{in_state}   = \&request_line;
    $request->method_start;
}

sub request_body {
    my __PACKAGE__ $connection = shift;
    my $request = $connection->{requests}[-1];
    $request->{raw_body} = substr($_, 0, $connection->{in_want}, "") if
	$connection->{in_want} >= 0;
    $connection->{in_state}   = \&request_line;
    $connection->{in_process} = $connection->can("want_line") ||
        die "$connection has no want_line";
    $connection->{in_want}  = 1;

    $request->method_start;
}

1;
