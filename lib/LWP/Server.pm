package LWP::Server;
use strict;

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

	    req_queue   => [],
	    pending_req => 0,

            conn_param => {},
	    conns => [],
	    idle_conns => 0,
	  }, $class;
}

# General parameters

sub proto   {  $_[0]->{'proto'};  }
sub host    {  $_[0]->{'host'};   }
sub port    {  $_[0]->{'port'};   }

sub id
{
    my $self = shift;
    "$self->{'proto'}://$self->{'host'}:$self->{'port'}";     # URL like
}

# Managing the request queue

sub add_request
{
    my($self, $req, $pri) = @_;
    if ($pri && $pri < 50) {
	push(@{$self->{req_queue}}, $req);
    } else {
	unshift(@{$self->{req_queue}}, $req);
    }
}

sub stop
{
    # stop all connections
    # terminate all requests (generate fake response)
    # both 'req_queue' and 'conns' should be empty when we finish
}

# Connection management


sub conn_param
{
    my $self = shift;
    # Let the UA params be overridden by per server params
    my %param = ($self->{'ua'}->conn_param,
		 %{$self->{'conn_param'}},
		);

    $param{ManagedBy} = $self;
    $param{Host} = $self->{'host'};
    $param{Port} = $self->{'port'};

    %param;
}


sub create_connection
{
    my $self = shift;
    my $conn_class = "LWP::Conn::\U$self->{'proto'}";
    no strict 'refs';
    unless (defined %{"$conn_class\::"}) {
	eval "require $conn_class";
	die if $@;
    }
    my $conn = $conn_class->new($self->conn_param);
    push(@{$self->{conns}}, $conn) if $conn;
}

# Connection protocol

sub get_request
{
    my($self, $conn) = @_;
    shift(@{$self->{req_queue}});
}

sub pushback_request
{
    my $self = shift;
    my $conn = shift;
    unshift(@{$self->{req_queue}}, @_);
}

sub done_request
{
}

sub connection_idle
{
}

sub connection_closed
{
    my($self, $conn) = @_;
    #XXX remove conn from $self->{conns}
}

sub as_string
{
    my $self = shift;
    my @str;
    push(@str, "$self\n");
    require Data::Dumper;
    for (sort keys %$self) {
	my $str;
	if ($_ eq "req_queue") {
	    my @q;
	    for (@{$self->{req_queue}}) {
		my $id = sprintf "0x%08x", int($_);
		my $method = $_->method || "<no method>";
		my $url = $_->url || "<no url>";
		push(@q, "$method $url ($id)");
	    }
	    $str = "\$req_queue = " . join("\n             ", @q) . "\n";
	} elsif ($_ eq "ua") {
	    $str = "\$ua = $self->{ua}\n";
	} else {
	    $str = Data::Dumper->Dump([$self->{$_}], [$_]);
	}
	$str =~ s/^/  /mg;  # indent
	push(@str, $str);
    }
    join("", @str, "");

}


1;
