package LWP::UA;

require LWP::Server;
use strict;
use vars qw($DEBUG);

sub new
{
    my($class) = shift;
    bless {
#	   default_headers => { "User-Agent" => "lwp/ng",
#				"From" => "aas\@sn.no",
#			      },

	   conn_param => {},
	   max_conn => 5,
	   max_conn_per_server => 2,

           servers => {},
	   
	  }, $class;
}

sub conn_param
{
    my $self = shift;
    return %{ $self->{conn_param} } unless @_;
    return $self->{conn_param}{$_[0]} if @_ == 1;
    while (@_) {
	my $k = shift;
	my $v = shift;
	$self->{conn_param}{$k} = $v;
    }
}

sub server
{
    my($self, $url) = @_;
    $url = URI::URL->new($url) unless ref($url);
    my $proto = $url->scheme || die "Missing scheme";
    $proto = "nntp" if $proto eq "news";  # hack
    my $host = $url->host || die "Missing host";
    my $port = $url->port || die "No port";
    my $netloc = "$proto://$host:$port";

    my $server = $self->{servers}{$netloc};
    unless ($server) {
	$server = $self->{servers}{$netloc} =
	  LWP::Server->new($self, $proto, $host, $port);
    }
}

sub spool
{
    my $self = shift;
    eval {
	for my $req (@_) {
	    my $proxy = $req->proxy;
	    my $server = $self->server($proxy ? $proxy : $req->url);
	    $req->managed_by($self);
	    $server->add_request($req);
	    if ($DEBUG) {
		my $id = $server->id;
		print "$req spooled to $id\n";
	    }
	}
	$self->reschedule;
    };
    if ($@) {
	print $@;
	return;
    }
}

sub response_received
{
    my($self, $res) = @_;
    print "RESPONSE\n";
    print $res->as_string;
}

sub stop
{
    my $self = shift;
    foreach (values %{$self->{servers}}) {
	$_->stop;
    }
}


sub reschedule
{
    my $self = shift;
    my $sched = $self->{'scheduler'};
    unless ($sched) {
	require LWP::StdSched;
	$sched = $self->{'scheduler'} = LWP::StdSched->new($self);
    }
    $sched->reschedule($self);
}

sub delete
{
    # must break circular references
    my $self = shift;
    delete $self->{'servers'};
}


sub as_string
{
    my $self = shift;
    my @str;
    push(@str, "$self\n");
    require Data::Dumper;
    for (sort keys %$self) {
	my $str;
	if ($_ eq "servers") {
	    my @s;
	    for (sort keys %{$self->{servers}}) {
		push(@s, "  $_ =>\n");
		my $s = $self->{servers}{$_}->as_string;
		$s =~ s/^/    /mg; # indent
		push(@s, $s);
	    }
	    $str = join("", "\$servers = {\n", @s, "};\n");
	} else {
	    $str = Data::Dumper->Dump([$self->{$_}], [$_]);
	}
	$str =~ s/^/  /mg;  # indent
	push(@str, $str);
    }


    join("", @str, "");
}

1;
