package LWP::Server;
use strict;

sub new
{
    my($class, $ua, $proto, $host, $port) = @_;
    bless { ua  => $ua,

	    proto  => $proto,
#	    proto_ver => undef,

	    host => $host,
	    port => $port,

#	    created => time(),
#	    last_active => time(),

	    req_queue   => [],

            conn_param => {},
	    conns => [],
	    idle_conns => [],
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

sub status
{
    my $self = shift;
    (scalar(@{$self->{req_queue}}),
     scalar(@{$self->{conns}}),
     scalar(@{$self->{idle_conns}}),
     $self->max_conn,
    );
}

# Managing the request queue

sub add_request
{
    my($self, $req) = @_;
    my $pri = $req->priority;
    if ($pri && $pri > 50) {
	push(@{$self->{req_queue}}, $req);
    } else {
	unshift(@{$self->{req_queue}}, $req);
    }
    $self->activate_idles;
}

sub stop
{
    my $self = shift;
    # stop all connections
    my @conns = @{$self->{conns}};  # iterate over a copy
    for (@conns) {
	$_->stop;
    }
    # terminate all requests (generate fake response)
    require HTTP::Response;
    while (@{$self->{req_queue}}) {
	my $req = shift @{$self->{req_queue}};
	$req->done(HTTP::Response->new(601, "No response"));
    }
}

sub stop_idle
{
    my $self = shift;
    my @idle = @{$self->{idle_conns}};  # iterate over a copy
    for (@idle) {
	$_->stop;
    }
}

# Connection management

sub max_conn
{
    my $self = shift;
    my $old = $self->{max_conn};
    $old = $self->{'ua'}{'max_conn_per_server'} unless defined $old;
    if (@_) {
	$self->{max_conn} = shift;
    }
    $old;
}

sub conn_param
{
    my $self = shift;
    return $self->{conn_param}{$_[0]} if @_ == 1;
    unless (@_) {
	# Let the UA params be overridden by per server params
	my %param = ($self->{'ua'}->conn_param,
		     %{$self->{'conn_param'}},
		    );
	$param{ManagedBy} = $self;
	$param{Host} = $self->{'host'};
	$param{Port} = $self->{'port'};
	return %param;
    }
    # set new value(s)
    while (@_) {
	my $k = shift;
	my $v = shift;
	$self->{conn_param}{$k} = $v;
    }
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
    print "GET_REQUEST $conn\n";
    shift(@{$self->{req_queue}});
}

sub pushback_request
{
    my $self = shift;
    my $conn = shift;
    print "PUSHBACK $conn @_\n";
    unshift(@{$self->{req_queue}}, @_);
    $self->activate_idles;
}

sub activate_idles
{
    my $self = shift;
    my @iconns = @{$self->{idle_conns}};
    foreach (@iconns) {
	$_->activate;
    }
}

sub remove_from_refarray
{
    my($self, $arr, $ref) = @_;
    for my $i (0 .. @$arr - 1) {
	if (int($arr->[$i]) == int($ref)) {
	    splice(@$arr, $i, 1);
	    return 1;
	}
    }
    return 0;
}

sub connection_active
{
    my($self, $conn) = @_;
    print "ACTIVE $conn\n";
    $self->remove_from_refarray($self->{idle_conns}, $conn);
}


sub connection_idle
{
    my($self, $conn) = @_;
    print "IDLE $conn\n";
    if ($self->remove_from_refarray($self->{idle_conns}, $conn)) {
	warn "$conn was already in idle_conns";
    }
    push(@{$self->{idle_conns}}, $conn);
}

sub connection_closed
{
    my($self, $conn) = @_;
    print "CLOSED $conn\n";
    $self->remove_from_refarray($self->{idle_conns}, $conn);
    $self->remove_from_refarray($self->{conns}, $conn) or
	warn "$conn was not registered";
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
