package LWP::UA;

require LWP::Server;
use strict;

sub new
{
    my($class) = shift;
    bless {
#	   default_headers => { "User-Agent" => "lwp/ng",
#				"From" => "aas\@sn.no",
#			      },
	   conn_param => {},
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
	    my $server = $self->server($req->url);
	    $req->managed_by($self);
	    $server->add_request($req);
	    print "$req spooled\n";
	}
	#$self->reschedule;
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



#----------------------------------------

sub reschedule
{
    my($self) = @_;

    # This is where all the logic goes
    my($netloc,$server);
    while (($netloc,$server) = each %{$self->{servers}}) {
	my $num_preq = $server->num_pending_requests;
	next unless $num_preq;
	my $num_con = $server->num_connections;
	print "There are $num_preq pending requests and $num_con connections for $netloc\n";

	my $max_conn = $server->max_connections;
	my $conn_to_start = min($num_preq, $max_conn) - $num_con;

	print "  ...starting $conn_to_start new connections\n"
	  if $conn_to_start > 0;
	while ($conn_to_start--) {
	    $server->new_connection;
	}
    }
}

# Just some utility functions

sub min
{
    my $min = shift;
    for (@_) {
	$min = $_ if $_ < $min;
    }
    $min;
}

sub max
{
    my $max = shift;
    for (@_) {
	$max = $_ if $_ < $max;
    }
    $max;
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
