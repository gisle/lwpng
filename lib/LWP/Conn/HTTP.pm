package LWP::Conn::HTTP; # An HTTP Connection class

# $Id$

# Copyright 1997-1998 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;
use vars qw($DEBUG);
use vars qw(@TE);
@TE = qw(deflate base64 rot13);

use Carp ();
use LWP::MainLoop qw(mainloop);
use LWP::Conn::_Connect ();

use base qw(IO::Socket::INET);

sub new
{
    my($class, %cnf) = @_;

    my $mgr = delete $cnf{ManagedBy} ||
      Carp::croak("'ManagedBy' is mandatory");
    my $host =   delete $cnf{Host} || delete $cnf{PeerAddr} ||
      Carp::croak("'Host' is mandatory for HTTP");
    my $port;
    $port = $1 if $host =~ s/:(\d+)//;
    $port = delete $cnf{Port} || delete $cnf{PeerPort} || $port || 80;

    my $timeout = delete $cnf{Timeout} || 3*60;
    my $idle_timeout = delete $cnf{IdleTimeout} || $timeout;
    my $conn_timeout = delete $cnf{ConnTimeout} || $timeout;
    my $req_limit = delete $cnf{ReqLimit} || 1;
    $req_limit = 1 if $req_limit < 1;
    my $req_pending = delete $cnf{ReqPending} || 1;
    $req_pending = 1 if $req_pending < 1;

    if (%cnf && $^W) {
	for (keys %cnf) {
	    warn "Unknown LWP::Conn::HTTP->new attribute '$_' ignored\n";
	}
    }

    return LWP::Conn::_Connect->new($host, $port, $conn_timeout,
		 "LWP::Conn::HTTP::Idle",
		 [$mgr, $req_limit, $req_pending, $timeout, $idle_timeout]
                );
}

sub state
{
    my $self = shift;
    my $old = ref($self);
    $old =~ s/^LWP::Conn::HTTP:://;
    if (@_) {
	print STDERR "State trans: $old --> $_[0]\n" if $DEBUG;
	bless $self, "LWP::Conn::HTTP::$_[0]";
    }
    $old;
}


sub new_request
{
    my $self = shift;
    return if defined *$self->{'lwp_wbuf'}; # XXX not really necessary?
    return if $self->last_request_sent;
    return if $self->pending_requests >= *$self->{'lwp_req_max_pending'};

    my $mgr = *$self->{'lwp_mgr'};
    my $req = $mgr->get_request($self);
    if ($req) {
	print STDERR "$self: New-Request $req\n" if $DEBUG;
	my @rlines;
	my $method = $req->method || "GET";
	my $uri = $req->proxy ? $req->url->as_string : $req->url->full_path;
	my $proto = $req->protocol || "HTTP/1.1";
	push(@rlines, "$method $uri $proto");
	$req->header("Host" => $req->url->netloc);  # always override

	my @conn_header;
	*$self->{'lwp_req_count'}++;
	if ($proto eq "HTTP/1.0") {
	    # can't send any more request, server will close connection
	    *$self->{'lwp_req_limit'} = 1;
	} else {
	    if (my $conn = $req->header("Connection")) {
		if (grep lc($_) eq "close", split(/\s*,\s*/, $conn)) {
		    *$self->{'lwp_req_limit'} = 1;
		}
	    }
	    push(@conn_header, "close")
		if *$self->{'lwp_req_count'} >= *$self->{'lwp_req_limit'};
	    if (@TE) {
		push(@conn_header, "TE");
		$req->header(TE => join(",", @TE));
	    }
	}
	if (@conn_header) {
	    $req->header("Connection" => join(",", @conn_header));
	} else {
	    $req->remove_header("Connection");
	}

	my $cont_ref = $req->content_ref;
	$cont_ref = $$cont_ref if ref($$cont_ref);
	if (ref($cont_ref) eq "CODE") {
	    if (my $len = $req->header("Content-Length")) {
		*$self->{'lwp_wlen'} = $len + 0;
	    } else {
		# must use chunked encoding for the request content
		$req->push_header("Transfer-Encoding", "chunked");
		*$self->{'lwp_wlen'}  = 0;
	    }
	    *$self->{'lwp_wdyn'} = $cont_ref;  # dynamic content
	    $cont_ref = \"";   #"; make sure a complete header is sent first.
	} else {
	    my $len = length($$cont_ref);
	    $req->header("Content-Length" => $len) if $len;
	}

	$req->scan(sub { push(@rlines, "$_[0]: $_[1]") });
	push(@rlines, "", $$cont_ref);
	push(@{ *$self->{'lwp_req'} }, $req);
	*$self->{'lwp_wbuf'} = join("\015\012", @rlines);
	mainloop->writable($self);
	return $req;
    }
    return;
}


sub last_request_sent
{
    my $self = shift;
    *$self->{'lwp_req_count'} >= *$self->{'lwp_req_limit'};
}


sub current_request
{
    my $self = shift;
    my $req = *$self->{'lwp_req'};
    return if !$req || !@$req;
    $req->[0];
}


sub pending_requests
{
   my $self = shift;
   my $req = *$self->{'lwp_req'};
   return 0 if !$req;
   @$req;
}


sub activate
{
}

sub stop
{
    my $self = shift;
    $self->_error("STOP");
}

# EventLoop callbacks
sub readable { shift->_error("Readable connection"); }
sub inactive { shift->_error("Inactive connection"); }

sub writable
{
    my $self = shift;
    my $buf = \ *$self->{'lwp_wbuf'};
    my $n = syswrite($self, $$buf, length($$buf));
    if (!defined($n) || $n == 0) {
	$self->_error("Bad write: $!");
    } else {
	print STDERR "WROTE $n bytes\n" if $LWP::Conn::HTTP::DEBUG;
	if ($n < length($$buf)) {
	    substr($$buf, 0, $n) = "";  # get rid of this
	} else {
	    # Check if we are generating dynamic content
	    if (my $dyn = *$self->{'lwp_wdyn'}) {
		my $chunk = &$dyn();
		my $clen  = length($chunk);

		if (my $len = *$self->{'lwp_wlen'}) {
		    # we are generating content with the specified length
		    if ($clen > $len) {
			# chunk to large, truncate it
			substr($chunk, $len) = '';
			$clen = $len;
		    } elsif ($clen == 0) {
			$self->_error("Short dynamic request content ($len bytes missing)");
			# Other possibilities is to fill request
			# content with some random padding or to
			# just continue to call the callback routine
			# until we have enough.
			return;
		    }
		    *$self->{'lwp_wbuf'} = $chunk;
		    $len -= $clen;
		    *$self->{'lwp_wlen'} = $len;
		    delete *$self->{'lwp_wdyn'} unless $len;
		} else {
		    # we are using chunked transfer encoding for this request
		    *$self->{'lwp_wbuf'} = join("\015\012",
						sprintf("%x", $clen),
						$chunk, "");
		    delete *$self->{'lwp_wdyn'} if $clen == 0;
		}
		return;
	    }
	    # request sent
	    delete *$self->{'lwp_wbuf'};
	    # try to start a new one?
	    $self->new_request or mainloop->writable($self, undef);
	}
    }
}


sub _error
{
    my($self, $msg) = @_;
    print STDERR "Conn::HTTP-Error: $msg\n" if $DEBUG;
    mainloop->forget($self);
    $self->close;
    $self->state("Closed");

    delete *$self->{'lwp_te'};
    my $mgr = delete *$self->{'lwp_mgr'};
    my $req = *$self->{'lwp_req'};
    if ($req && @$req) {
	my $cur_req = shift @$req;
	$mgr->pushback_request($self, @$req) if @$req;
	my $res = *$self->{'lwp_res'};
	if ($res) {
	    $mgr->connection_closed($self);
	    # partial result already available
	    $res->header("Client-Orig-Status" => $res->status_line);
	    $res->code(591); # XXX
	    $res->message($msg);
	    # This must be the last thing we do, because it might not
	    # return immediately.
	    $cur_req->response_done($res);
	} else {
	    my $count = *$self->{'lwp_req_count'} - @$req;
	    if ($msg eq "EOF" && $count > 1) {
		# The server closed the connection before sending any
		# response to this request even if it had send response
		# to some previous request.  This means that this request
		# should be retried.
		$mgr->pushback_request($self, $cur_req);
		$mgr->connection_closed($self);
	    } else {
		$mgr->connection_closed($self);
		$cur_req->gen_response(590, "No response", $msg);
	    }
	}
    } else {
	$mgr->connection_closed($self);
    }
}


sub response_data
{
    my $self = shift;
    my $req  = shift;
    # my($data, $res) = @_;
    eval {
	if (my $te = *$self->{'lwp_te'}) {
	    $te->put($_[0]);
	} else {
	    $req->response_data(@_);
	}
    };
    if ($@) {
	chomp($@);
	$self->_error($@);
	return;
    }
    return 1;
}





package LWP::Conn::HTTP::Idle;
use base qw(LWP::Conn::HTTP);
use LWP::MainLoop qw(mainloop);

sub connected
{
    my($self, $param) = @_;
    @{*$self}{'lwp_mgr', 'lwp_req_limit', 'lwp_req_max_pending',
	      'lwp_timeout', 'lwp_idle_timeout'} = @$param;
    *$self->{'lwp_req_count'} = 0;
    *$self->{'lwp_rbuf'} = "";
    mainloop->readable($self);
    mainloop->timeout($self, *$self->{'lwp_idle_timeout'});
    $self->activate;
}

sub connect_failed
{
    my($self, $msg, $param) = @_;
    my $mgr = shift @$param;
    while (my $req = $mgr->get_request($self)) {
	$req->gen_response(590, $msg);
    }
    $self->state("Closed");
    $mgr->connection_closed($self);
}


sub activate
{
    my $self = shift;
    if ($self->new_request) {
	$self->state("Active");
	mainloop->timeout($self, *$self->{'lwp_timeout'});
	*$self->{'lwp_mgr'}->connection_active($self);
    }
}




package LWP::Conn::HTTP::Active;
use base qw(LWP::Conn::HTTP);

use LWP::MainLoop qw(mainloop);
require HTTP::Response;

sub activate
{
    my $self = shift;
    $self->new_request;  # try to pipeline another request
}


sub readable
{
    my $self = shift;
    my $buf = \ *$self->{'lwp_rbuf'};
    my $n = sysread($self, $$buf, 512, length($$buf));
    if (!defined($n)) {
	$self->_error("Bad read: $!");
    } elsif ($n == 0) {
	$self->server_closed_connection;
    } else {
	if ($LWP::Conn::HTTP::DEBUG) {
	    my $pbuf = $$buf;
	    $pbuf =~ s/([\0-\037\\])/sprintf("\\%03o", ord($1))/ge;
	    substr($pbuf, 50) = "..." if length($pbuf) > 50;
	    print STDERR "READ (", length($$buf), ") [$pbuf]\n";
	}
	$self->check_rbuf;
    }
}


sub server_closed_connection
{
    shift->_error("EOF");
}


sub check_rbuf
{
    my $self = shift;
    my $buf = \ *$self->{'lwp_rbuf'};

    my($res, $prot, $code);
    my $magic       = substr("HTTP/1.", 0, length($$buf));
    my $first_bytes = substr($$buf, 0, length($magic));

    if ($first_bytes ne $magic) {
	($prot, $code) = ("HTTP/0.9", 200);
	$res = HTTP::Response->new($code => "OK");
	$res->protocol($prot);

    } elsif ($$buf =~ /\015?\012\015?\012/) {
	# all of the headers received, process it...
	$$buf =~ s/^((.*?)\015?\012\015?\012)//s or die;
	my $head = $1;
	my @head = split(/\015?\012/, $2);
	my $mess;
	($prot, $code, $mess) = split(" ", shift(@head), 3);
	$res = HTTP::Response->new($code, $mess);
	$res->protocol($prot);
	my $err;
	$code = "" unless defined($code);
	$err = "Bad status code '$code'" unless $code =~ /^\d+$/;
	my($k, $v);
	for (@head) {
	    last if $err;
	    if (/^([^\s:]+)\s*:\s*(.*)/) {
		$res->push_header($k, $v) if $k;
		($k, $v) = ($1, $2);
	    } elsif (/^\s+(.*)/) {
		$err = "Bad header (continuation)" unless $k;
		$v .= " $1";
	    } else {
		$err = "Bad header line '$_'";
	    }
	}
	$res->push_header($k, $v) if $k;

	if ($err) {
	    # something bad in the headers, fallback on HTTP/0.9
	    ($prot, $code) = ("HTTP/0.9", 200);
	    $res = HTTP::Response->new($code => "OK");
	    $res->protocol($prot);
	    $res->header("Client-Warning" => $err);
	    $$buf = "$head$$buf";
	}

    } else {
	return;
    }

    my $req = $self->current_request;

    if ($code == 101) {  # SWITCHING PROTOCOL
	# XXX Should check for pipelining
	mainloop->forget($self);
	(delete *$self->{'lwp_mgr'})->connection_closed($self); # a white lie
	bless $self, "IO::Socket::INET";  # downgrade
	$res->{'101_socket'} = $self;     # a header would be more visible
	$res->content($$buf);             # if we read too much
	$req->response_done($res);
	return;
    }

    if ($code >= 100 && $code <= 199) {
	print STDERR "Info response ($code)\n" if $LWP::Conn::HTTP::DEBUG;
	# XXX: should we store $res anywhere or just forget about it?
	$self->check_rbuf;
	return;
    }

    *$self->{'lwp_res'} = $res;
    $res->request($req);
    return unless $self->response_data($req, "", $res);
    #print $res->as_string if $LWP::Conn::HTTP::DEBUG;

    if ($code >= 400 && $code <= 599 &&  # we got an error response and
	*$self->{'lwp_wdyn'} &&          # we are still sending dynamic content
	@{ *$self->{'lwp_req'} } == 1    # for request with this error response
       ) {
	# make sure it gets terminated on next opportunity.
	*$self->{'lwp_wdyn'} = sub { "" };
    }

    if (my $conn = $res->header("Connection")) {
	if (grep lc($_) eq "close", split(/\s*,\s*/, $conn)) {
	    # The server intends to close this connection once this response
	    # is done.  No requests in the pipeline will work.
	    my $req = *$self->{'lwp_req'};
	    if (@$req > 1) {
		*$self->{'lwp_mgr'}->pushback_request($self, splice(@$req, 1));
	    }
	    *$self->{'lwp_req_limit'} = 1;  # no more requests on this conn
	}
    }

    # Determine how to find the end of message
    if ($req->method eq "HEAD" || $code =~ /^(?:1\d\d|[23]04)$/) {
	$self->state("ContLen");
	*$self->{'lwp_cont_len'} = 0;
	$self->end_of_response;
	return;
    } elsif (my(@trans_enc) = $res->header("Transfer-Encoding")) {
	require HTTP::Headers::Util;
	@trans_enc = HTTP::Headers::Util::split_header_words(@trans_enc);
	my $last_enc = pop(@trans_enc);
	if (lc($last_enc->[0]) ne "chunked") {
	    $self->_error("Last Transfer-Encoding was not chunked");
	    return;
	}
	if (@trans_enc) {
	    if (@trans_enc > 10) {
		# protect against servers trying to use all our resources
		$self->_error("Too long TE chain");
		return;
	    }
	    # must set up stream of LWP::Sink objects that will decode
	    # the transfer encodings applied by the server.
	    eval {
		require LWP::Sink::identity;
		require LWP::Sink::Monitor if $LWP::Conn::HTTP::DEBUG;
		my $te;
		$te = LWP::Sink::Monitor->new("chunked")
		    if $LWP::Conn::HTTP::DEBUG;
		for (reverse @trans_enc) {
		    my $enc = lc(shift @$_);
		    $enc =~ /^([a-z][a-z0-9]*)$/ or die "Bad TE '$enc'";
		    $enc = $1; # untaint
		    next if $enc eq "identity";
		    my $filter = "LWP::Sink::$enc";
		    no strict 'refs';
		    unless (defined %{"$filter\::"}) {
			eval "require $filter";
			die "No filter for TE '$enc': $@" if $@;
		    }
		    $filter = "$filter\::decode"->new(@$_);
		    $te = $te ? $te->push($filter) : $filter;
		    $te->push(LWP::Sink::Monitor->new($enc))
			if $LWP::Conn::HTTP::DEBUG;
		}
		if ($te) {
		    # Just terminate the stream with a callback closure
		    # that feeds the data to $req->response_data
		    $te->push(LWP::Sink::identity->new);
		    $te->push( sub { $req->response_data($_[0], $res); } );
		    *$self->{'lwp_te'} = $te;
		}
	    };
	    if ($@) {
		$self->_error($@);
		return;
	    }
	}
	$res->remove_header("Transfer-Encoding");  # XXX or perhaps not?
	$self->state("Chunked");
	*$self->{'lwp_chunked'} = -1; # expect chunk size next
    } else {
	my $cont_len = $res->header("Content-Length");
	if (defined $cont_len) {
	    $self->state("ContLen");
	    *$self->{'lwp_cont_len'} = $cont_len;
	    unless ($cont_len) {
		$self->end_of_response;
		return;
	    }
	} else {
	    my $ct = $res->header("Content-Type") || "";
	    if ($ct =~ /^multipart\//) {
		if ($ct =~ /\bboundary\s*=\s*(.*)/) {
		    my $boundary = $1;
		    if ($boundary =~ /^\"([^\"]*)\"/) {  # quoted
			$boundary = $1;
		    } else {
			$boundary =~ s/[\s;].*//;
		    }
		    $self->state("Multipart");
		    print STDERR "Read until <CR><LF>--$boundary--<CR><LF>\n"
		      if $LWP::Conn::HTTP::DEBUG;
		    *$self->{'lwp_boundary'} = "\015\012--$boundary--\015\012"
		} else {
		    return $self->_error("Multipart without boundary");
		}
	    } else {
		$self->state("UntilEOF");
		# If we have pending requests, then we know we will never
		# get a reply, so let's return them to the mgr...
		my $req = *$self->{'lwp_req'};
		if (@$req > 1) {
		    my $mgr = *$self->{'lwp_mgr'};
		    $mgr->pushback_request($self, splice(@$req, 1));
		}
	    }
	}
    }
    $self->check_rbuf if length $$buf;
}


sub end_of_response
{
    my $self = shift;
    print STDERR "$self: End-Of-Response\n" if $LWP::Conn::HTTP::DEBUG;
    my $req = shift @{*$self->{'lwp_req'}};  # get rid of current request
    if (my $te = delete *$self->{'lwp_te'}) {
	$te->close;
    }
    my $res = delete *$self->{'lwp_res'};

    if ($self->last_request_sent && !$self->current_request) {
	mainloop->forget($self);
	$self->close;
	$self->state("Closed");
	(delete *$self->{'lwp_mgr'})->connection_closed($self);
    } else {
	$self->state("Active");
	$self->new_request;
	if ($self->current_request) {
	    $self->check_rbuf;
	} else {
	    $self->state("Idle");
	    mainloop->timeout($self, *$self->{'lwp_idle_timeout'});
	    *$self->{'lwp_mgr'}->connection_idle($self);
	}
    }
    # This must be the last thing we do, because it might not
    # return immediately.
    $req->response_done($res);
}




package LWP::Conn::HTTP::ContLen;
use base qw(LWP::Conn::HTTP::Active);

sub check_rbuf
{
    my $self = shift;
    my $buf      = \ *$self->{'lwp_rbuf'};
    my $res      =   *$self->{'lwp_res'};
    my $cont_len =   *$self->{'lwp_cont_len'};

    my $data = substr($$buf, 0, $cont_len);
    substr($$buf, 0, $cont_len) = '';
    $cont_len -= length($data);
    return unless $self->response_data($res->request, $data, $res);
    if ($cont_len > 0) {
	*$self->{'lwp_cont_len'} = $cont_len;
    } else {
	$self->end_of_response;
    }
}




package LWP::Conn::HTTP::Chunked;
use base qw(LWP::Conn::HTTP::Active);

sub check_rbuf
{
    my $self = shift;
    my $buf      = \ *$self->{'lwp_rbuf'};
    my $res      =   *$self->{'lwp_res'};
    my $chunked  =   *$self->{'lwp_chunked'};

    # -1: must get chunk header (number of bytes) first
    # >0: read this number of bytes before returning back to -1
    # -2: read footers (after 0 header)
    while (length ($$buf)) {
	if ($chunked > 0) {
	    # read $chunked bytes of data (throw away 2 last bytes "CRLF")
	    my $data = substr($$buf, 0, $chunked);
	    substr($$buf, 0, $chunked) = '';
	    $chunked -= length($data);
	    if ($chunked < 2) {
		substr($data, -2+$chunked, 2-$chunked) = '';
		$chunked = -1 if $chunked == 0;
	    }
	    return unless $self->response_data($res->request, $data, $res);

	} elsif ($chunked == -1) {
	    # read a new chunk header
	    last unless $$buf =~ s/^([^\012]*)\015?\012//;
	    my $chunk_size = $1;
	    unless ($chunk_size =~ /^0*([0-9A-Fa-f]+)\s*(;|$)/) {
		$self->_error("Bad chunk size line '$chunk_size'");
		return;
	    }
	    if (length($1) > 7) {
		$self->_error("Chunk too big '$chunk_size'");
		return;
	    }
	    $chunked = hex($1) + 2;  # XXX + 2 (CRLF)
	    $chunked = -2 if $chunked == 2;

	} elsif ($chunked == -2) {
	    # read footer
	    last unless $$buf =~ /^\015?\012/m;
	    # must have a blank line somewhere before we begin

	    local($_);
	    my($k, $v);
	    while ($$buf =~ s/^([^\012]*)\012//) {
		$_ = $1;
		s/\015$//;
		if (length($_) == 0) {
		    $res->push_header($k, $v) if $k;
		    $self->end_of_response;
		    return;
		} elsif (/^([^\s:]+)\s*:\s*(.*)/) {
		    $res->push_header($k, $v) if $k;
		    ($k, $v) = ($1, $2);
		} elsif (/^\s+(.*)/) {
		    unless ($k) {
			$self->_error("Bad chunked trailer (cont)");
			return;
		    }
		    $v .= " $1";
		} else {
		    $self->_error("Bad chunked trailer '$_'");
		    return;
		}
	    }
	} else {
	    die "This should never happen (\$chunked=$chunked)";
	}
	*$self->{'lwp_chunked'} = $chunked;   # remember to next time

	if ($LWP::Conn::HTTP::DEBUG) {
	    print STDERR "Chunked state: ";
	    if ($chunked == -1) {
		print STDERR "Expect chunk header line\n";
	    } elsif ($chunked == -2) {
		print STDERR "Expect trailers\n";
	    } elsif ($chunked > 0) {
		print STDERR "Expect $chunked data bytes\n";
	    } else {
		print STDERR "??? ($chunked)\n";
	    }
	}
    }
}




package LWP::Conn::HTTP::Multipart;
use base qw(LWP::Conn::HTTP::Active);

sub check_rbuf
{
    my $self = shift;
    my $buf      = \ *$self->{'lwp_rbuf'};
    my $res      =   *$self->{'lwp_res'};
    my $boundary =   *$self->{'lwp_boundary'};

    my $i = index($$buf, $boundary);
    if ($i < 0) {
	# boundary string not found, can it start somewhere at the
	# end of the $$buf?
	my $buflen = length($$buf);
	while (length $boundary) {
	    chop($boundary);
	    my $blen = length($boundary);
	    last if substr($$buf, $buflen-$blen, $blen) eq $boundary;
	}
	if (length $boundary) {
	    if ($LWP::Conn::HTTP::DEBUG) {
		my $tmp = $boundary;
		$tmp =~ s/\r/<CR>/g;
		$tmp =~ s/\n/<LF>/g;
		print STDERR "Boundary prefix '$tmp' match end of buffer\n"
	    }
	    my $data = substr($$buf, 0, $buflen - length($boundary));
	    substr($$buf, 0, length($data)) = '';
	    $self->response_data($res->request, $data, $res) if length($data);
	} else {
	    $self->response_data($res->request, $$buf, $res);
	    $$buf = '';
	}
	return;
    }
    # boundary is found in data
    my $data = substr($$buf, 0, $i + length($boundary));
    substr($$buf, 0, length($data)) = '';
    return unless $self->response_data($res->request, $data, $res);
    $self->end_of_response;
}





package LWP::Conn::HTTP::UntilEOF;
use base qw(LWP::Conn::HTTP::Active);

sub check_rbuf
{
    my $self = shift;
    my $buf      = \ *$self->{'lwp_rbuf'};
    my $res      =   *$self->{'lwp_res'};
    $self->response_data($res->request, $$buf, $res);
    $$buf = '';
}

sub server_closed_connection
{
    shift->end_of_response;
}

sub last_request_sent { 1; }

package LWP::Conn::HTTP::Closed; # no operations allowed
#use base qw(LWP::Conn::HTTP);

1;
