package LWP::Connection;

use strict;
require IO::Socket;

my $conn_no = 0;

sub new
{
    my($class, $server, %cnf) = @_;
    my $no = ++$conn_no;

    my $self = bless {
       'socket' => undef,
       state    => "ready",
       requests => [],
       server   => $server,
       conn_no  => $no,
    }, $class;
    $server->{num_connections}++;

    print "C$no: created\n";

    my $sock = IO::Socket::INET->new(PeerAddr => $server->host,
				     PeerPort => $server->port,
				     Proto    => "tcp",
				    );
    unless ($sock) {
	print "C$no: Can't connect\n";
	return;
    }
    $self->{'sock'} = $sock;
    $self->send_one_request;

    $self;
}

sub send_one_request
{
    my($self) = @_;
    my $sock = $self->{'sock'};
    my $server = $self->{'server'};
    my $no   = $self->{'conn_no'};

    my $req = $server->get_request;
    unless ($req) {
	print "C$no: no request to send\n";
	return;
    }
    push(@{$self->{requests}}, $req);

    my $url = $req->url;
    my $req_str = $req->method . " " . $url->full_path;
    print "C$no: $req_str\n";

    $req_str .= " HTTP/1.0\r\n";
    $req_str .= $req->headers_as_string("\r\n");
    $req_str .= "\r\n";


    $self->{'write_buf'} = $req_str;
    $self->writable;
}

sub writable
{
    my $self = shift;
    my $yes  = @_ ? shift : 1;
    my $sock = $self->{'sock'};
    if ($yes) {
	LWP::EventLoop::writable($sock, sub { $self->write });
    } else {
	LWP::EventLoop::cancel_writable($sock);
    }
}

sub readable
{
    my $self = shift;
    my $yes  = @_ ? shift : 1;
    my $sock = $self->{'sock'};
    if ($yes) {
	LWP::EventLoop::readable($sock, sub { $self->read });
    } else {
	LWP::EventLoop::cancel_readable($sock);
    }
}

sub write
{
    my $self = shift;
    my $sock = $self->{'sock'};
    my $no   = $self->{'conn_no'};
    my $write_buf = \$self->{'write_buf'};
    my $n = syswrite($sock, $$write_buf, 16);
    print "C$no: Wrote $n bytes\n";
    if (!defined($n) || !$n) {
	# could not write
	print "C$no: Bad write\n";
	$self->writeable(0);
	close($sock);
	return;
    }
    substr($$write_buf, 0, $n) = "";
    if (length($$write_buf) == 0) {
	print "C$no: Whole request sent\n";
	$self->writable(0);
	if ($self->pipeline) {
	    $self->send_one_request;
	}
	$self->readable;
	return;
    }
    # called again when we can write more
}

sub read
{
    my $self = shift;
    my $sock = $self->{'sock'};
    my $no   = $self->{'conn_no'};
    my $buf;
    my $n = sysread($sock, $buf, 128);
    my $response_finished;
    print "C$no: Read $n bytes\n";
    if (!$n) {
	$self->readable(0);
	my $req = pop(@{$self->{requests}});
	if (@{$self->{requests}}) {
	    # these failed on this connection
	    $self->{'server'}->add_request(@{$self->{requests}});
	}
	$self->close;
	return;
    } elsif ($response_finished) {
	$self->readable(0);
	if ($self->keepalive && !$self->pipeline) {
	    $self->send_one_request;  # a new on the same connection
	} else {
	    $self->close;
	}
    }
    $buf =~ s/\n/\\n/g; $buf =~ s/\r/\\r/g;  # nicer for printing
    print "C$no: [$buf]\n";
}

sub keepalive
{
    1;
}

sub pipeline
{
    0;
}

sub close
{
    my $self = shift;
    close($self->{'sock'});
    my $no = $self->{conn_no};
    print "C$no: close\n";

    my $serv = $self->{'server'};
    delete $self->{'server'};
    $serv->{num_connections}--;
    $serv->{'ua'}->reschedule;
}

sub DESTROY
{
    my $self = shift;
    my $server = $self->{server};
    $server->{num_connections}-- if $server;
    my $no = $self->{conn_no};
    print "C$no: destroyed\n";
}

package LWP::Connection::http;

use vars qw(@ISA);

@ISA=qw(LWP::Connection);

1;
