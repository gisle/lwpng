package LWP::UA;

use strict;
use vars qw($DEBUG);

require LWP::Server;
require URI::Attr;


sub new
{
    my($class) = shift;
    my $ua =
	bless {
	       conn_param => {},
	       max_conn => 5,
	       max_conn_per_server => 2,

	       uattr   => URI::Attr->new,
	       servers => {},
	      }, $class;

    $ua->add_hook("request", \&default_headers);
    $ua->add_hook("request", \&need_proxy);
    #$ua->agent("libwww-perl/ng");

    $ua;
}


sub agent
{
    my $self = shift;
    my $old = $self->{'agent'};
    if (@_) {
	my $agent = $self->{'agent'} = shift;
	$self->{'uattr'}->attr_update(SCHEME => "http:")
	    ->{'default_headers'}{'User-Agent'} = $agent;
	$self->{'uattr'}->attr_update(SCHEME => "mailto:")
	    ->{'default_headers'}{'X-Mailer'} = $agent;
	$self->{'uattr'}->attr_update(SCHEME => "news:")
	    ->{'default_headers'}{'X-Newsreader'} = $agent;
    }
    $old;
}


sub add_hook
{
    my $self = shift;
    my $type = shift;
    push(@{$self->{"${type}_hooks"}}, @_);
}


sub run_hooks
{
    my $self = shift;
    my $type = shift;
    for my $hook (@{$self->{"${type}_hooks"}}) {
	&$hook($self, @_);
    }
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


sub find_server
{
    my($self, $url) = @_;
    $url = URI::URL->new($url) unless ref $url;
    return undef unless $url;

    my $proto = $url->scheme || return undef;
    my $host = $url->host;
    my($port, $netloc);

    # Handle some special cases where $host can't be trusted
    if ($proto eq "file") {
	$host = undef if $host && $host eq "localhost";
    } elsif ($proto eq "mailto") {
	$host = undef;
    }

    if ($host) {
	$port = $url->port;
	$netloc = $port ? "$proto://$host:$port" : "$proto://host";
    } else {
	$netloc = "$proto:";
    }

    my $server = $self->{servers}{$netloc};
    unless ($server) {
	$server = $self->{servers}{$netloc} =
	  LWP::Server->new($self, $proto, $host, $port);
    }
}


sub spool
{
    my $self = shift;
    my $spooled = 0;
    for my $req (@_) {
	unless ($req->method) {
	    $req->gen_response(400, "Missing METHOD in request");
	    next;
	}
	my $url = $req->url;
	unless ($url) {
	    $req->gen_response(400, "Missing URL in request");
	    next;
	}
	unless ($url->scheme) {
	    $req->gen_response(400, "Request URL must be absolute");
	    next;
	}

	$self->run_hooks("request", $req);
	my $proxy = $req->proxy;
	my $server = $self->find_server($proxy ? $proxy : $req->url);
	$req->managed_by($self);
	$server->add_request($req);
	$spooled++;
	if ($DEBUG) {
	    my $id = $server->id;
	    print "$req spooled to $id\n";
	}
    }

    $self->reschedule if $spooled;
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


sub default_headers
{
    my($self, $req) = @_;
    for my $hash ($self->{'uattr'}->p_attr($req->url, "default_headers")) {
	for my $k (keys %$hash) {
	    next if defined($req->header($k));
	    $req->header($k => $hash->{$k});
	}
    }
}

sub need_proxy
{
    my($self, $req) = @_;
    return if $req->proxy;
    my $proxy = $self->{'uattr'}->p_attr($req->url, "proxy");
    $req->proxy($proxy);
}


sub no_proxy
{
    my($self, @no) = @_;
    for (@no) {
	$_ = ".$_" unless /^\./;
	my $h = $self->{'uattr'}->attr_update("DOMAIN", "http://dummy.$_");
	$h->{"proxy"} = "";
    }
}


sub proxy
{
    my($self, $scheme, $url) = @_;
    my $h = $self->{'uattr'}->attr_update("SCHEME", "$scheme:");
    $h->{"proxy"} = $url;
}


sub env_proxy {
    my ($self) = @_;
    my($k,$v);
    while(($k, $v) = each %ENV) {
	$k = lc($k);
	next unless $k =~ /^(.*)_proxy$/;
	$k = $1;
	if ($k eq 'no') {
	    $self->no_proxy(split(/\s*,\s*/, $v));
	}
	else {
	    $self->proxy($k, $v);
	}
    }
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
=com
	} elsif ($_ eq "uattr") {
	    $str = "\$uattr = ...\n";
=cut
	} else {
	    $str = Data::Dumper->Dump([$self->{$_}], [$_]);
	}
	$str =~ s/^/  /mg;  # indent
	push(@str, $str);
    }

    join("", @str, "");
}

1;
