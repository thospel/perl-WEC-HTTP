package WEC::HTTP::Connection::Client;
use 5.006;
use strict;
use warnings;
use Carp;

use WEC::HTTP::Request;

our $VERSION = '1.000';

use base qw(WEC::HTTP::Connection);

our @CARP_NOT	= qw(WEC::FieldConnection);

sub init_client {
    my __PACKAGE__ $connection = shift;

    # No multiplexing in HTTP
    $connection->{host_mpx}	= 0;
    $connection->{peer_mpx}	= 0;
    $connection->{requests}	= [];
    $connection->{in_want}	= 1;
    $connection->{in_process}	= \&silence;
}

sub silence {
    my __PACKAGE__ $connection = shift;
    die "Unexpected bytes from server: $_";
}

sub submit {
    my __PACKAGE__ $connection = shift;
    my $request = $connection->{requests}[0] ||
        croak "There was no request to submit";
    $request->submit;
    $connection->{in_want}	= 1;
    $connection->{in_process}	= $connection->can("want_line") ||
        die "$connection has no want_line";
    $connection->{in_state}	= \&response_status;
}

sub response_status {
    (my __PACKAGE__ $connection, my $line, my $eol) = @_;
    my $request = $connection->{requests}[0] ||
        croak "Response without request";
    $request->{raw_status_line} = $line . $eol;
    $request->{status_line} = $line;

    # rfc 2616, 6.1:
    #  Status-Line = HTTP-Version SP Status-Code SP Reason-Phrase CRLF
    my ($major, $minor, $code, $message) = $line =~ m!\A\s*HTTP/(\d+)\.(\d+)\s+(\d+)(?:\s+(.*\S))?\s*\z!is or
        croak "Could not parse status line '$line'";
    $request->{response_major}	= $major+0;
    $request->{response_minor}	= $minor+0;
    $request->{status_code}	= sprintf("%03d", $code);
    $request->{status_message}	= $message;
    $connection->{in_state}	= \&response_header;
}

sub response_header {
    (my __PACKAGE__ $connection, my $header, my $eol) = @_;
    my $request = $connection->{requests}[0] || die "No request for response";

    $request->{raw_headers} .= $header;
    $request->{raw_headers} .= $eol;
    return if $header ne "";

    # rfc 2616, 4.3:
    # The presence of a message-body in a request is signaled by the
    # inclusion of a Content-Length or Transfer-Encoding header field in
    # the request's message-headers

    $request->{raw_response_body} = "";
    $request->{response_headers} = Email::Simple->new($request->{raw_headers});
    my $transfer_encoding =
        $request->{response_headers}->header("Transfer-Encoding");
    if (defined $transfer_encoding && $transfer_encoding ne "") {
        $transfer_encoding =~ /\A\s*chunked\s*\z/i ||
            croak "Transfer-encoding '$transfer_encoding' not implemented";
        $connection->{in_state}	= \&chunk_header;
        return;
    }
    my $length = $request->{response_headers}->header("Content-Length");
    if (defined($length) && $length ne "") {
        $length=~ /\A\s*\d+\s*\z/ ||
            croak "Could not parse length '$length'";
        $connection->{in_process} = \&response_body;
        $connection->{in_want} = $length+0;
        return;
    }
    # $connection->{in_want}	= 1;
    # $connection->{in_process}	= \&silence;
    $connection->expect_eof;
    $connection->close;
    $request->responded;
}

sub response_body {
    my __PACKAGE__ $connection = shift;
    my $request = $connection->{requests}[0] || die "No request for response";
    $request->{raw_response_body} = substr($_, 0, $connection->{in_want}, "");

    # $connection->{in_process} = \&silence;
    # $connection->{in_want}  = 1;
    $connection->expect_eof;
    $connection->close;
    $request->responded;
}

sub chunk_header {
    (my __PACKAGE__ $connection, my $line, my $eol) = @_;
    $line =~ /\A\s*([0-9a-fA-F]+)\s*(?:;|\z)/ ||
        croak "Cannot parse chunk header '$line'";
    my $length = hex($1);
    if ($length) {
        $connection->{in_want}	  = $length;
        $connection->{in_process} = \&chunk_body;
        return;
    }
    $connection->{in_want}	= 1;
    $connection->{in_process}	= $connection->can("want_line") ||
        die "$connection has no want_line";

    my $request = $connection->{requests}[0] || die "No request for response";
    $request->{raw_headers} =~ s/^(.*\n)\z/X-Chunk-Trailers: $1/m;
    $connection->{in_state}	= \&chunk_trailers;
}

sub chunk_body {
    my __PACKAGE__ $connection = shift;
    my $request = $connection->{requests}[0] || die "No request for response";
    $request->{raw_response_body} .= substr($_, 0, $connection->{in_want}, "");
    $connection->{in_want}	= 1;
    $connection->{in_process}	= $connection->can("want_line") ||
        die "$connection has no want_line";
    $connection->{in_state} = \&chunk_end;
}

sub chunk_end {
    (my __PACKAGE__ $connection, my $line) = @_;
    $line eq "" || die "Unexpected data '$line' at chunk end";
    $connection->{in_state} = \&chunk_header;
}

sub chunk_trailers {
    (my __PACKAGE__ $connection, my $header, my $eol) = @_;
    my $request = $connection->{requests}[0] || die "No request for response";

    $request->{raw_headers} .= $header;
    $request->{raw_headers} .= $eol;
    return if $header ne "";

    # $connection->{in_want} = 1;
    # $connection->{in_process} = \&silence;
    $connection->close;
    $connection->expect_eof;
    $request->{response_headers} = Email::Simple->new($request->{raw_headers});
    $request->responded;
}

sub new_request {
    my __PACKAGE__ $connection = shift;
    my $request = WEC::HTTP::Request->new($connection, @_);
    $request->{major} = 1;
    $request->{minor} = 1;
    $request->{http_version} = "HTTP/1.1";
    push @{$connection->{requests}}, $request;
    return $request;
}

sub GET {
    (my __PACKAGE__ $connection, my %options) = @_;
    defined(my $uri = delete $options{uri}) ||
        croak "No uri specified";
    my $request = $connection->new_request("GET", $uri);
    defined($request->{callback} = delete $options{callback}) ||
        croak "No callback specified";
    $request->{content_type} = delete $options{content_type};

    croak "Unknown option ", join(", ", keys %options) if %options;

    $connection->submit() if @{$connection->{requests}} == 1;
    return $request;
}

sub POST {
    (my __PACKAGE__ $connection, my %options) = @_;
    defined(my $uri = delete $options{uri}) ||
        croak "No uri specified";
    my $request = $connection->new_request("POST", $uri);
    defined($request->{callback} = delete $options{callback}) ||
        croak "No callback specified";
    $request->{body}	= delete $options{body};
    $request->{headers}	= delete $options{headers};
    $request->{content_type} = delete $options{content_type};

    croak "Unknown option ", join(", ", keys %options) if %options;

    $connection->submit() if @{$connection->{requests}} == 1;
    return $request;
}

1;
