package LWP::Conn::HTTP; # HTTP Connection

# $Id$

# Copyright 1997 Gisle Aas.
#
# This library is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# A hack that should work at least on Linux
# XXX: When we require IO-1.18, then this hack can be removed.
unless (defined &IO::EINPROGRESS) {
    $! = 115;
    die "No EINPROGRESS found ($!)" unless $! eq "Operation now in progress";
    *IO::EINPROGRESS = sub () { 115; };
}

use strict;
use vars qw($DEBUG);

my $TCP_PROTO = (getprotobyname('tcp'))[2];
use Carp ();
use IO::Socket qw(AF_INET SOCK_STREAM inet_aton pack_sockaddr_in);
use LWP::MainLoop qw(mainloop);

use base qw(IO::Socket::INET);



sub new
{
    my($class, %cnf) = @_;

    my $mgr = delete $cnf{ManagedBy} ||
      Carp::croak("'ManagedBy' is mandatory");
    my $host =   delete $cnf{Host} || delete $cnf{PeerAddr} ||
      Carp::croak("'Host' is mandatory");
    my $port;
    $port = $1 if $host =~ s/:(\d+)//;
    $port = delete $cnf{Port} || delete $cnf{PeerPort} || $port || 80;

    my $timeout = delete $cnf{Timeout} || 3*60;
    my $idle_timeout = delete $cnf{IdleTimeout} || $timeout;
    my $req_limit = delete $cnf{ReqLimit} || 1;
    $req_limit = 1 if $req_limit < 1;
    my $req_pending = delete $cnf{ReqPending} || 1;
    $req_pending = 1 if $req_pending < 1;

    if (%cnf && $^W) {
	for (keys %cnf) {
	    warn "Unknown LWP::Conn::HTTP->new attribute '$_' ignored\n";
	}
    }

    # Resolve address, should really be non-blocking too
    my($addrtype, @addrs);
    if ($host =~ /^\d+(?:\.\d+){3}$/) {
	$addrtype = AF_INET;
	$addrs[0] = inet_aton($host);
    } else {
	(undef, undef, $addrtype, undef, @addrs) = gethostbyname($host);
	die "Bad address" if $addrtype != AF_INET;
    }
    @addrs = map pack_sockaddr_in($port, $_), @addrs;


    my $sock;
    while (@addrs) {
	my $addr = shift @addrs;
	$sock = IO::Socket::INET->new;
	unless ($sock) {
	    warn "Failed IO::Socket::INET ctor: $!\n";
	    next;
	}
	bless $sock, "LWP::Conn::HTTP";
	unless (socket($sock, AF_INET, SOCK_STREAM, $TCP_PROTO)) {
	    warn "Failed socket: $!\n";
	    undef($sock);
	    next;
	}

	eval { $sock->blocking(0) };  # require IO-1.18 or better
	mainloop->timeout($sock, $timeout);

        *$sock->{'lwp_mgr'}             = $mgr;
	*$sock->{'lwp_req_count'}       = 0;
	*$sock->{'lwp_req_limit'}       = $req_limit;
	*$sock->{'lwp_req_max_pending'} = $req_pending;
	*$sock->{'lwp_timeout'}         = $timeout;
	*$sock->{'lwp_idle_timeout'}    = $idle_timeout;

	if ($DEBUG) {
	    use Socket qw(unpack_sockaddr_in inet_ntoa);
	    my($port, $addr) = unpack_sockaddr_in($addr);
	    print STDERR "Connecting ", inet_ntoa($addr), ":$port...\n";
	}
	unless (connect($sock, $addr)) {
	    if ($! == &IO::EINPROGRESS) {
		$sock->state("Connecting");
		mainloop->writable($sock);
                mainloop->readable($sock);
		return $sock;
	    } else {
		mainloop->forget($sock);
		$sock->close;
		undef($sock);
	    }
	}
    }
    if ($sock) {
        $sock->state("Idle");
	*$sock->{'lwp_rbuf'} = "";
	mainloop->readable($sock);
	$sock->activate;
    }
    $sock;
}

sub state
{
    my $self = shift;
    my $old = ref($self);
    $old =~ s/^LWP::Conn::HTTP:*//;
    if (@_) {
	print STDERR "State trans: $old --> $_[0]\n" if $DEBUG;
	bless $self, "LWP::Conn::HTTP::$_[0]";
    }
    $old;
}


sub new_request
{
    my $self = shift;
    return if defined *$self->{'lwp_wbuf'};
    return if $self->last_request_sent;
    return if $self->pending_requests >= *$self->{'lwp_req_max_pending'};

    my $mgr = *$self->{'lwp_mgr'};
    my $req = $mgr->get_request($self);
    if ($req) {
	print STDERR "$self: New-Request $req\n" if $DEBUG;
	my @rlines;
	my $uri = $req->proxy ? $req->url->as_string : $req->url->full_path;
	push(@rlines, $req->method . " $uri HTTP/1.1");
	$req->header("Host" => $req->url->netloc);
	#$req->header("Connection" => "close");
	$req->scan(sub { push(@rlines, "$_[0]: $_[1]") });
	push(@rlines, "", $req->content);
	push(@{ *$self->{'lwp_req'} }, $req);
	*$self->{'lwp_wbuf'} = join("\015\012", @rlines);
	*$self->{'lwp_req_count'}++;  # XXX: should mark last request somehow
	mainloop->writable($self);
	return $req;
    }
    return undef;
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
sub writable { shift->_error("Writable connection"); }
sub readable { shift->_error("Readable connection"); }
sub inactive { shift->_error("Inactive connection"); }

sub _error
{
    my($self, $msg) = @_;
    print STDERR "Conn::HTTP-Error: $msg\n" if $DEBUG;
    mainloop->forget($self);
    $self->close;
    
    my $mgr = delete *$self->{'lwp_mgr'};
    my $req = *$self->{'lwp_req'};
    if ($req && @$req > 1) {
	my $cur_req = shift @$req;  # currect request never retried
	$mgr->pushback_request($self, @$req);
	my $res = *$self->{'lwp_res'};
	if ($res) {
	    # partial result
	    $res->header("Client-Orig-Status" => $res->status_line);
	    $res->code(600); # XXX
	    $res->message($msg);
	    $cur_req->done($res);
	} else {
	    $cur_req->done(HTTP::Response->new(601, "No response"));
	}
    }
    $mgr->connection_closed($self);
}




package LWP::Conn::HTTP::Connecting;
use base qw(LWP::Conn::HTTP);

use LWP::MainLoop qw(mainloop);


sub writable
{
    my $self = shift;
    if (defined($self->peername)) {
	mainloop->writable($self, undef);
        $self->state("Idle");
	$self->activate;
    } else {
	$self->_error("Can't connect: $!");
    }
}


sub inactive
{
    shift->_error("Connect timeout");
}




package LWP::Conn::HTTP::Idle;
use base qw(LWP::Conn::HTTP);
use LWP::MainLoop qw(mainloop);

sub activate
{
    my $self = shift;
    if ($self->new_request) {
	$self->state("Active");
	mainloop->timeout($self, *$self->{'lwp_timeout'});
    }
}




package LWP::Conn::HTTP::Active;
use base qw(LWP::Conn::HTTP);

use LWP::MainLoop qw(mainloop);
require HTTP::Response;


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
	    # request sent
	    delete *$self->{'lwp_wbuf'};
	    # try to start a new one?
	    mainloop->writable($self, undef) unless $self->new_request;
	}
    }
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

    if ($code == 100) {
	print STDERR "100 Continue\n" if $LWP::Conn::HTTP::DEBUG;
	# XXX: should we store $res anywhere or just forget about it?
	$self->check_rbuf;
	return;
    }

    *$self->{'lwp_res'} = $res;
    my $req = $self->current_request;
    $res->request($req);
    #print $res->as_string if $LWP::Conn::HTTP::DEBUG;

    # Determine how to find the end of message
    my $trans_enc;
    if ($req->method eq "HEAD" || $code =~ /^(?:1\d\d|[23]04)$/) {
	$self->state("ContLen");
	*$self->{'lwp_cont_len'} = 0;
	$self->end_of_response;
	return;
    } elsif ( ($trans_enc = $res->header("Transfer-Encoding"))) {
	if ($trans_enc ne "chunked") {
	    $self->_error("Unknown transfer encoding '$trans_enc'");
	    return;
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
    $req->done(*$self->{'lwp_res'});
    *$self->{'lwp_res'} = undef;
    if ($self->last_request_sent && !$self->current_request) {
	mainloop->forget($self);
	$self->close;
	(delete *$self->{'lwp_mgr'})->connection_closed($self);
	return;
    }
    $self->state("Active");
    $self->new_request;
    if ($self->current_request) {
	$self->check_rbuf;
    } else {
	*$self->{'lwp_mgr'}->connection_idle($self);
	$self->state("Idle");
	mainloop->timeout($self, *$self->{'lwp_idle_timeout'});
    }
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
    $res->request->response_data($data, $res);
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
	    $res->request->response_data($data, $res);

	} elsif ($chunked == -1) {
	    # read a new chunk header
	    if ($$buf =~ s/^([^\012]*)\015?\012//) {
		my $chunk_size = $1;
		unless ($chunk_size =~ /^([0-9A-Fa-f]+)\s*(;|$)/) {
		    $self->_error("Bad chunk size line '$chunk_size'");
		    return;
		}
		if (length($1) > 7) {
		    $self->_error("Chunk too big '$chunk_size'");
		    return;
		}
		$chunked = hex($1) + 2;  # XXX + 2 (CRLF)
		$chunked = -2 if $chunked == 2;
	    }
	} elsif ($chunked == -2) {
	    # read footer
	    return unless $$buf =~ /^\015?\012/m;
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
	    $res->request->response_data($data, $res) if length($data);
	} else {
	    $res->request->response_data($$buf, $res);
	    $$buf = '';
	}
	return;
    }
    # boundary is found in data
    my $data = substr($$buf, 0, $i + length($boundary));
    substr($$buf, 0, length($data)) = '';
    $res->request->response_data($data, $res);
    $self->end_of_response;
}





package LWP::Conn::HTTP::UntilEOF;
use base qw(LWP::Conn::HTTP::Active);

sub check_rbuf
{
    my $self = shift;
    my $buf      = \ *$self->{'lwp_rbuf'};
    my $res      =   *$self->{'lwp_res'};
    $res->request->response_data($$buf, $res);
    $$buf = '';
}

sub server_closed_connection
{
    shift->end_of_response;
}

sub last_request_sent { 1; }

1;
