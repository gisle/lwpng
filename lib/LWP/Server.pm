package LWP::Server;
use strict;

sub new
{
    my($class, $ua, $proto, $host, $port) = @_;

    die "Bad proto" unless $proto =~ /^([a-zA-Z0-9\+\-\.]+)$/;
    my $conn_class = uc($1);  # untaint as well
    $conn_class =~ s/\+/_PLUS_/g;
    $conn_class =~ s/\./_DOT_/g;
    $conn_class =~ s/\-/_MINUS_/g;
    $conn_class = "LWP::Conn::$conn_class";

    my $self = bless
          {
            ua  => $ua,

	    proto  => $proto,
#	    proto_ver => undef,
	    conn_class => $conn_class,

	    created => time(),
	    request_count => 0,

	    req_queue   => [],

            conn_param => {},
	    conns => [],
	    idle_conns => [],
	  }, $class;

    if ($host) {
	$self->{'host'} = $host;
	$self->{'port'} = $port;
    }

    $self;
}

# General parameters

sub proto   {  $_[0]->{'proto'};  }
sub host    {  $_[0]->{'host'};   }
sub port    {  $_[0]->{'port'};   }

sub id
{
    my $self = shift;
    if (my $host = $self->{'host'}) {
	if (my $port = $self->{'port'}) {
	    return "$self->{'proto'}://$host:$port";
	}
	return "$self->{'proto'}://$host";
    }
    return "$self->{'proto'}:";
}

sub c_status
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
    # should really keep sorted by 'pri' field
    if ($pri && $pri > 50) {
	push(@{$self->{req_queue}}, $req);
    } else {
	unshift(@{$self->{req_queue}}, $req);
    }
    $self->{'request_count'}++;
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
    $self->kill_queued_requests;
}

sub stop_idle
{
    my $self = shift;
    my @idle = @{$self->{idle_conns}};  # iterate over a copy
    for (@idle) {
	$_->stop;
    }
}

sub kill_queued_requests
{
    my($self, $code, $message, $more) = @_;
    if (!$code) {
	$code = 590;
	$message = "No response";
    }
    while (@{$self->{req_queue}}) {
	my $req = shift @{$self->{req_queue}};
	$req->gen_response($code, $message, $more);
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
    my $conn_class = $self->{'conn_class'};
    no strict 'refs';
    unless (defined %{"$conn_class\::"}) {
	eval "require $conn_class";
	if ($@) {
	    $self->kill_queued_requests(590, "No handler for '$self->{'proto'}' scheme", $@);
	    return;
	}
    }
    
    my $conn;
    eval {
	$conn = $conn_class->new($self->conn_param);
    };
    if ($@) {
	chomp($@);
	$self->kill_queued_requests(590, $@);
	return;
    }
    if ($conn) {
	push(@{$self->{conns}}, $conn);
    } elsif (@{$self->{req_queue}}) {
	my $msg = "Can't connect to " . $self->id;
	$self->kill_queued_requests(590, $msg, $!);
    }
}

# Connection protocol

sub get_request
{
    my($self, $conn) = @_;
    my $req = shift(@{$self->{req_queue}});
    $self->{'last_request_time'} = time if $req;
    $req;
}

sub pushback_request
{
    my $self = shift;
    my $conn = shift;
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
