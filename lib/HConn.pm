package HConn; # HTTP Connection

# A hack that should work on Linux until we require IO-1.18
unless (defined &IO::EINPROGRESS) {
    *IO::EINPROGRESS = sub () { 115; };
}

use strict;
use vars qw($DEBUG);
$DEBUG=1;

my $TCP_PROTO = (getprotobyname('tcp'))[2];


use IO::Socket qw(AF_INET SOCK_STREAM inet_aton pack_sockaddr_in);
use LWP::EventLoop qw(mainloop);

use base qw(IO::Socket::INET);

sub new
{
    my($class, $host, $port, $mgr) = @_;

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
	unless (socket($sock, AF_INET, SOCK_STREAM, $TCP_PROTO)) {
	    warn "Failed socket: $!\n";
	    undef($sock);
	    next;
	}

	# $sock->blocking(0);  # require IO-1.18
        $ {*$sock}{'lwp_mgr'} = $mgr;
	mainloop->timeout($sock, 8);
	if ($DEBUG) {
	    use Socket qw(unpack_sockaddr_in inet_ntoa);
	    my($port, $addr) = unpack_sockaddr_in($addr);
	    print STDERR "Connecting ", inet_ntoa($addr), ":$port...\n";
	}
	unless (connect($sock, $addr)) {
	    if ($! == &IO::EINPROGRESS) {
		bless $sock, "HConn::Connecting";
		mainloop->writable($sock);
		return $sock;
	    } else {
		mainloop->forget($sock);
		$sock->close;
		undef($sock);
	    }
	}
    }
    if ($sock) {
        bless $sock, "HConn::Idle";
	$ {*$sock}{'lwp_rbuf'} = "";
	mainloop->readable($sock);
	$sock->activate;
    }
    $sock;
}

sub activate
{
}

sub writable
{
    shift->_error("Writable connection");
}

sub readable
{
    shift->_error("Readable connection");
}

sub inactive
{
    shift->_error("Inactive connection");
}

sub _error
{
    my($self, $msg) = @_;
    print STDERR "$self: $msg\n";
    mainloop->forget($self);
    my $mgr = $ {*$self}{'lwp_mgr'};
    $self->close;
    $mgr->connection_closed($self);
}

package HConn::Connecting;
use base qw(HConn);
use LWP::EventLoop qw(mainloop);

sub writable
{
    my $self = shift;
    if (defined($self->peername)) {
	mainloop->writable($self, undef);
        bless $self, "HConn::Idle";
	$self->activate;
    } else {
	$self->_error("Can't connect: $!");
    }
}

sub inactive
{
    shift->_error("Connect timeout");
}

package HConn::Idle;
use base qw(HConn);

use LWP::EventLoop qw(mainloop);

sub activate
{
    my $self = shift;
    my $mgr = $ {*$self}{'lwp_mgr'};
    my $req = $mgr->get_request($self);
    if ($req) {
	print STDERR "$self: Processing request $req...\n";
	my @rlines;
	push(@rlines, $req->method . " " . $req->url->full_path . " HTTP/1.1");
	$req->header("Host" => $req->url->netloc);
	#$req->header("Connection" => "close");
	$req->scan(sub { push(@rlines, "$_[0]: $_[1]") });
	push(@rlines, "", "");
	push(@{ $ {*$self}{'lwp_req'} }, $req);
	$ {*$self}{'lwp_wbuf'} = join("\015\012", @rlines);
	bless $self, "HConn::Active";
	mainloop->writable($self);
    }
    $self;
}

package HConn::Active;
use base qw(HConn);

use LWP::EventLoop qw(mainloop);
require HTTP::Response;

sub writable
{
    my $self = shift;
    my $buf = \ $ {*$self}{'lwp_wbuf'};
    my $n = syswrite($self, $$buf, length($$buf));
    if (!defined($n) || $n == 0) {
	$self->_error("Bad write: $!");
    } else {
	if ($n < length($$buf)) {
	    substr($$buf, 0, $n) = "";  # get rid of this
	} else {
	    # request sent
	    delete $ {*$self}{'lwp_wbuf'};
	    mainloop->writable($self, undef);
	    # XXX: if we pipeline, we might at this place get another
	    # request from the mgr and start sending it.
	}
    }
}

sub readable
{
    my $self = shift;
    my $buf = \ $ {*$self}{'lwp_rbuf'};
    my $n = sysread($self, $$buf, 50, length($$buf));
    if (!defined($n)) {
	$self->_error("Bad read: $!");
    } elsif ($n == 0) {
	$self->_error("EOF");
    } else {
	if ($HConn::DEBUG) {
	    my $pbuf = $$buf;
	    $pbuf =~ s/([\0-\037\\])/sprintf("\\%03o", ord($1))/ge;
	    substr($pbuf, 50) = "..." if length($pbuf) > 50;
	    print "READ (", length($$buf), ") [$pbuf]\n";
	}
	my $res = $ {*$self}{'lwp_res'};
	if ($res) {
	    # XXX.... must be able to tell the end of the message
	    
	} else {
	    return unless length($$buf) >= 7;  # can't do anything before that
	    my($prot, $code);
	    if (!$$buf =~ m,^HTTP/1\.,) {
		($prot, $code) = ("HTTP/0.9", 200);
		$res = HTTP::Response->new($code => "OK");
		$res->protocol($prot);
	    } elsif ($$buf =~ /\015?\012\015?\012/) {
		# all of the header received, process it...
		$$buf =~ s/^(.*?)\015?\012\015?\012//s or die;
		my @head = split(/\015?\012/, $1);
		my $mess;
		($prot, $code, $mess) = split(" ", shift(@head), 3);
		$res = HTTP::Response->new($code, $mess);
		$res->protocol($prot);
		my($k, $v);
		for (@head) {
		    if (/^([^\s:]+)\s*:\s*(.*)/) {
			$res->push_header($k, $v) if $k;
			($k, $v) = ($1, $2);
		    } elsif (/^\s+(.*)/) {
			warn "Bad header" unless $k;
			$v .= " $1";
		    } else {
			warn "Bad header\n";
		    }
		}
		$res->push_header($k, $v) if $k;
	    } else {
		return;
	    }
	    $ {*$self}{'lwp_res'} = $res;
	    print $res->as_string;

	    # Determine how to determine end of message
	    my $req_method = "GET";  # XXX (should look at the request)
	    my $cont_len;
	    my $trans_enc;
	    my $boundary;
	    if ($req_method eq "HEAD" || $code =~ /^(?:1\d\d|[23]04)$/) {
		$cont_len = 0;
	    } elsif ( ($trans_enc = $res->header("Transfer-Encoding"))) {
		$self->_error("Unknown transfer encoding '$trans_enc'")
		  if $trans_enc ne "chunked";
	    } else {
		my $ct = $res->header("Content-Type") || "";
		if ($ct =~ /^multipart\//) {
		    if ($ct =~ /\bboundary\s*=\s*(.*)/) {
			$boundary = $1;
		    } else {
			$self->_error("Multipart without boundary");
		    }
		} else {
		    $cont_len = $res->header("Content-Length");
		}
	    }

	    # If neither $cont_len, $trans_enc nor $boundary is defined
	    # then we must read content until server closes the
	    # connection.

	    if ($HConn::DEBUG) {
		if (defined $cont_len) {
		    print "CONTENT IS $cont_len BYTES\n";
		} elsif ($trans_enc) {
		    print "CHUNKED\n";
		} elsif ($boundary) {
		    print "MULTIPART UNTIL --$boundary\n";
		} else {
		    print "CONTENT UNTIL EOF\n";
		}
	    }
	    
	}
    }
}

1;
