package LWP::Server;
use strict;

use vars qw($DEBUG);

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
            ua            => $ua,

	    proto         => $proto,
	    conn_class    => $conn_class,

	    created       => time(),
	    request_count => 0,

	    req_queue     => [],
	    conns         => [],
	    idle_conns    => [],
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
    # XXX should really keep sorted by 'pri' field.  Wouldn't it be nice
    # if Perl had a library similar to Python's bisect.py
    # (perhaps it already has?)
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
    $self->{stopping}++;
    for (@conns) {
	$_->stop;
    }
    $self->kill_queued_requests;
    delete $self->{stopping};
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
    $self->{'ua'}->uri_attr_plain($self->id, 'max_conn_per_server') || 2;
}

sub conn_param
{
    my $self = shift;
    my %param;
    for my $hash ($self->{'ua'}->uri_attr_plain($self->id, "conn_param")) {
	while (my($k,$v) = each %$hash) {
	    next if exists $param{$k};
	    $param{$k} = $v;
	}
    }
    # these are always overridden
    $param{ManagedBy} = $self;
    $param{Host} = $self->{'host'};
    $param{Port} = $self->{'port'};

    if (@_) {
	return @param{@_};
    }
    wantarray ? %param : \%param;
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
	print STDERR $@ if $DEBUG;
	chomp($@);
	$self->kill_queued_requests(590, $@);
	$self->done;
	return;
    }
    if ($conn) {
	push(@{$self->{conns}}, $conn);
    } else {
	if (@{$self->{req_queue}}) {
	    my $msg = "Can't connect to " . $self->id;
	    $self->kill_queued_requests(590, $msg, $!);
	}
	$self->done;
    }
}

# Connection protocol

sub get_request
{
    my($self, $conn) = @_;
    my $req = shift(@{$self->{req_queue}});
    if ($req) {
	my $time = time;
	$self->{'last_request_time'} = time;
	$req->sending_start($time);
    }
    $req;
}

sub pushback_request
{
    my $self = shift;
    my $conn = shift;
    unshift(@{$self->{req_queue}}, @_);
    $self->activate_idles;
}

sub activate_connections
{
    my $self = shift;
    my @iconns = @{$self->{idle_conns}};
    my @conns = @{$self->{conns}};
    my %seen;
    # activate idle connections first
    foreach (@iconns) {
	$_->activate;
	$seen{$_}++;
    }
    foreach (@conns) {
	next if $seen{$_};
	$_->activate;
    }
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
    print STDERR "ACTIVE $conn\n" if $DEBUG;
    $self->remove_from_refarray($self->{idle_conns}, $conn);
}


sub connection_idle
{
    my($self, $conn) = @_;
    print STDERR "IDLE $conn\n" if $DEBUG;
    if ($self->remove_from_refarray($self->{idle_conns}, $conn)) {
	warn "$conn was already in idle_conns";
    }
    push(@{$self->{idle_conns}}, $conn);
}

sub connection_closed
{
    my($self, $conn) = @_;
    print STDERR "CLOSED $conn\n" if $DEBUG;
    $self->remove_from_refarray($self->{idle_conns}, $conn);
    $self->remove_from_refarray($self->{conns}, $conn) or
	warn "$conn was not registered";

    unless (@{$self->{conns}}) {
	# This was the last connection
	if (@{$self->{req_queue}} && !$self->{stoppping}) {
	    $self->create_connection
	} else {
	    $self->done;
	}
    }
}

sub done  # this really just deallocates this LWP::Server entry
{
    my $self = shift;
    my $ua = delete $self->{'ua'};
    $ua->forget_server($self->id);
}

1;
