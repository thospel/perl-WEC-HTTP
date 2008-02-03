package WEC::HTTP::Request;
use 5.006;
use strict;
use warnings;
use Carp;
use URI;
use Email::Date;

our $VERSION = '1.000';

use base qw(WEC::Object);

my $CR	 = "\x0d";
my $LF	 = "\x0a";
my $CRLF = "$CR$LF";

sub new {
    my ($class, $connection, $method, $uri) = @_;
    my __PACKAGE__ $request = $class->SUPER::new($connection);
    $request->{method}	= $method;
    $request->{uri}	= ref($uri) ? $uri : URI->new($uri);
    my $scheme = $request->{uri}->scheme();
    Carp::confess "Cannot handle scheme $scheme" if
        defined $scheme && $scheme ne "http";
    return $request;
}

sub headers {
    return shift->{headers};
}

sub response_headers {
    return shift->{response_headers};
}

sub connection {
    return shift->{parent};
}

sub raw_headers {
    return shift->{raw_headers};
}

sub raw_response_headers {
    return shift->{raw_headers};
}

sub raw_body {
    return shift->{raw_body};
}

sub raw_response_body {
    return shift->{raw_response_body};
}

sub response_body {
    return shift->{raw_response_body};
}

sub method {
    return shift->{method};
}

sub uri {
    return shift->{uri};
}

sub body {
    # Apply transfer-encoding here.... --Ton
    return shift->{raw_body};
}

my %methods = map {$_ => 1} qw(GET POST);
sub method_start {
    my __PACKAGE__ $request = shift;
    my $method = $request->method;
    if ($methods{$method}) {
	my $connection = $request->{parent};
	if (my $fun = $connection->{options}{$method}) {
	    $fun->($request, $request->{headers}, $request->body);
	    return;
	}
    }
    $request->error(501, "Method '$method' not implemented");
}

sub submit {
    my __PACKAGE__ $request = shift;
    my $connection = $request->{parent};

    # Create headers
    my $headers = defined($request->{headers}) ? $request->{headers} : "";
    $headers = Email::Simple->new($headers) unless ref $headers;
    $request->{headers} = $headers;

    $headers->header_set("Date", Email::Date::format_date);
    $headers->header_set("User-Agent", "WEC::HTTP $VERSION");
    # Next is not the same as host_port
    # (->host unescapes %hex, ->host_port does not)
    my $uri = $request->uri;
    $headers->header_set("Host", $uri->host() . ":" . $uri->port);
    $headers->header_set("Connection", "close");
    if (defined $request->{body}) {
        my $length = length $request->{body};
        $headers->header_set("Content-Length", $length);
        if (defined $request->{content_type}) {
            $headers->header_set("Content-Type", $request->{content_type});
        } else {
            my $ct = $headers->header("Content-Type");
            defined($ct) && $ct ne "" ||
                croak "No content-type defined for $request->{method} $uri";
        }
    }

    # Create request
    $uri->as_string() =~ m,^(?:[^:/?\#]+:)?(?://[^/?\#]*)?(.*)$,s or die;
    my $string =
        "$request->{method} " . ($1 eq "" ? "/" : $1) .
        " $request->{http_version}\n" .
        $headers->as_string;
    $string =~ s/\n/$CRLF/g;

    # Actual submit
    $connection->send($string);
    $connection->send($request->{body}) if defined $request->{body};
}

sub responded {
    my __PACKAGE__ $request = shift;
    my $connection = $request->{parent};
    $connection->_drop_request($request);
    $request->{callback}->($request);
}

my %html_escape =
    ("\"" => "&quote;",
     "&"  => "&amp;",
     "<"  => "&lt;",
     ">"  => "&gt;");

sub html_escape {
    my $str = shift;
    $str =~ s/([\"<>&])/$html_escape{$1}/g;	# "
    return $str;
}

my %code_to_public =
    (200 => "OK",
     400 => "Bad Request",
     501 => "Method Not Implemented",
     );

sub respond {
    (my __PACKAGE__ $request, my %options) = @_;
    my $code	= delete $options{code} || 200;
    my $public	= delete $options{public};
    # possibly demand body for the submit types that should have one
    my $body	= delete $options{body};
    my $headers	= delete $options{headers};
    my $type	= delete $options{content_type} if defined $body;

    croak "Unknown option ", join(", ", keys %options) if %options;

    my $sent;
    my $connection = $request->{parent};
    if ($request->{http_version}) {
	$headers = ref($headers) ? $headers : 
	    Email::Simple->new(defined $headers ? $headers : "");
	$headers->header_set("Date", Email::Date::format_date);
	if ($connection->{signature}) {
	    $headers->header_set("Server", $connection->{signature});
	}
	if (defined($body)) {
	    my $length = length($body);
	    $headers->header_set("Content-Length", $length);
	    if ($type) {
		$headers->header_set("Content-Type", $type);
	    } else {
		my $ct = $headers->header("Content-Type");
		if (!defined $ct || $ct eq "") {
		    $headers->header_set("Content-Type", 
					 "text/html; charset=iso-8859-1");
		}
	    }
	}
	$headers->header_set("Connection", "close");

	$public = $code_to_public{$code} if !defined $public;
	defined $public || croak "Unknown code $code";
	$code = sprintf("%03d", $code);
	$headers = 
	    "$request->{http_version} $code $public\n" . $headers->as_string;

	$headers =~ s/\r?\n/$CRLF/g;
	$connection->send($headers);
	$sent .= $headers if defined wantarray;
    }
    if (defined($body)) {
	$connection->send($body);
	$sent .= $body if defined wantarray;
    }
    $connection->send_close();
    $connection->_drop_request($request);
    return $sent;
}

sub error {
    (my __PACKAGE__ $request, my $code, my $private, my $public) = @_;
    my $connection = $request->{parent};
    print STDERR "Error: $private\n";
    $public = $code_to_public{$code} if !defined $public;
    defined $public || croak "Unknown code $code";
    $code = sprintf("%03d", $code);
    my $escaped_public = html_escape($public);
    my $signature = $connection->{signature};
    if (defined($signature)) {
	$signature = "<HR>\n" . html_escape($signature) . "\n";
    } else {
	$signature = "";
    }
    my $message = <<"EOF";
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html><head>
<title>$code $escaped_public</title>
</head><body>
<h1>$escaped_public</h1>
<p>Your browser sent a request that this server could not understand.<br />
</p>
$signature</body></html>
EOF
;
    $request->respond(code   => $code,
		      public => $public,
		      body   => $message);
}

1;
