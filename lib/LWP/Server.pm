package LWP::Server;
use strict;

require LWP::Connection;

sub new
{
    my($class, $ua, $proto, $host, $port) = @_;
    bless { ua  => $ua,

	    proto  => $proto,
	    proto_ver => undef,

	    host => $host,
	    port => $port,

	    created => time(),
	    last_active => undef,

	    num_req => 0,
	    num_connections => 0,
	    pending_req => [],
	  }, $class;
}

sub proto
{
    $_[0]->{'proto'};
}

sub host
{
    $_[0]->{'host'};
}

sub port
{
     $_[0]->{'port'};
}

sub add_request
{
    my($self,$req) = @_;
    push(@{$self->{pending_req}}, $req);
}

sub get_request
{
    my($self) = shift;
    shift(@{$self->{pending_req}});
}

sub num_pending_requests
{
    my($self) = shift;
    int(@{$self->{pending_req}});
}

sub num_connections
{
    $_[0]->{'num_connections'};
}

sub max_connections
{
    my $self = shift;
    $self->{'max_connections'} || $self->{'ua'}->max_server_connections;
}

sub new_connection
{
    my($self) = @_;
    my $conn_class = "LWP::Connection::$self->{'proto'}";
    no strict 'refs';
    eval "require $conn_class" unless defined %{"conn_class\::"};
    $conn_class->new($self);
}

1;
