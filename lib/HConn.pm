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
	mainloop->timeout($sock, 5);
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
	$sock->activate;
    }
    $sock;
}

sub activate
{
}

sub writable
{
}

sub readable
{
}

sub inactive
{
    my $self = shift;
    $self->_error("Inactive connection");
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

sub writable
{
    my $self = shift;
    die "NYI";
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
	print STDERR "Got request $req...\n";
	#print STDERR $req->as_string;

	my @rlines;
	push(@rlines, $req->method . " " . $req->url->full_path . " HTTP/1.1");
	$req->header("Host" => $req->url->netloc);
	#$req->header("Connection" => "close");
	$req->scan(sub { push(@rlines, "$_[0]: $_[1]") });
	push(@rlines, "", "");
	push(@{ $ {*$self}{'lwp_req'} }, $req);
	$ {*$self}{'lwp_wbuf'} = join("\015\012", @rlines);
	bless $self, "HConn::Active";
	mainloop->readable($self);
	mainloop->writable($self);
    }
    $self;
}

package HConn::Active;
use base qw(HConn);

use LWP::EventLoop qw(mainloop);

sub writable
{
    my $self = shift;
    my $buf = \ $ {*$self}{'lwp_wbuf'};
    my $n = syswrite($self, $$buf, 100);
    if (!defined($n) || $n == 0) {
	$self->_error("Bad write: $!");
    } else {
	if ($n < length($$buf)) {
	    substr($$buf, 0, $n) = "";  # get rid of this
	} else {
	    # no longer writeable
	    delete $ {*$self}{'lwp_wbuf'};
	    mainloop->writable($self, undef);
	}
    }
}

sub readable
{
    my $self = shift;
    my $buf;
    my $n = sysread($self, $buf, 1000);
    if (!defined($n)) {
	$self->_error("Bad read: $!");
    } elsif ($n == 0) {
	# eof
	print "EOF $self\n";
	mainloop->forget($self);
	$self->close;
    } else {
	my $pbuf = $buf;
	$pbuf =~ s/([\0-\037\\])/sprintf("\\%03o", ord($1))/ge;
	#substr($pbuf, 50) = "..." if length($pbuf) > 50;
	print "READ (", length($buf), ") [$pbuf]\n";
    }
}

1;
