package LWP::UA;
require LWP::Hooks;
@ISA=qw(LWP::Hooks);

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
	       cookie_jar => undef,
	       servers => {},
	      }, $class;

    $ua->add_hook("spool_request", \&setup_default_headers);
    $ua->add_hook("spool_request", \&setup_date);
    $ua->add_hook("spool_request", \&setup_auth);
    $ua->add_hook("spool_request", \&setup_proxy);

    $ua->agent("libwww-perl/ng-alpha ($^O)");
    $ua;
}


sub agent
{
    my $self = shift;
    my $old = $self->{'agent'};
    if (@_) {
	my $agent = $self->{'agent'} = shift;
	for ("http", "https") {
	    $self->{'uattr'}->attr_update(SCHEME => "$_:")
		->{'default_headers'}{'User-Agent'} = $agent;
	}
	$self->{'uattr'}->attr_update(SCHEME => "mailto:")
	    ->{'default_headers'}{'X-Mailer'} = $agent;
	$self->{'uattr'}->attr_update(SCHEME => "news:")
	    ->{'default_headers'}{'X-Newsreader'} = $agent;
    }
    $old;
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
    $host = undef if $proto eq "file" || $proto eq "mailto";

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
	bless $req, "LWP::Request" if ref($req) eq "HTTP::Request"; #upgrade
	$req->managed_by($self);
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
	next if $self->run_hooks_until_success("spool_request", $req);

	my $proxy = $req->proxy;
	my $server = $self->find_server($proxy ? $proxy : $req->url);
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


sub setup_default_headers
{
    my($self, $req) = @_;
    for my $hash ($self->{'uattr'}->p_attr($req->url, "default_headers")) {
	for my $k (keys %$hash) {
	    next if defined($req->header($k));
	    $req->header($k => $hash->{$k});
	}
    }
    0; # continue
}

sub setup_date
{
    my($self, $req) = @_;
    # Clients SHOULD only send a Date header field in messages that
    # include an entity-body, as in the case of the PUT and POST
    # requests, and even then it is optional.
    $req->date(time) if length ${ $req->content_ref };
    0;
}


sub setup_auth
{
    my($self, $req) = @_;
    my $realm = $self->{'uattr'}->p_attr($req->url, "realm");
    return unless $realm;
    my $realms = $self->{'uattr'}->p_attr($req->url, "realms");
    # should we ensure that this is a SERVER attribute?
    unless ($realms) {
	warn "No REALMS registered for this server";
	return;
    }
    if (my $auth = $realms->{$realm}) {
	$auth->set_authorization($req);
    } else {
	warn "Don't know about the '$realm' realm";
    }
    0;
}

sub cookie_jar
{
    my $self = shift;
    my $old = $self->{'cookie_jar'};
    if (@_) {
	if ($self->{'cookie_jar'} = shift) {
	    $self->add_hook("spool_request", \&setup_cookie) unless $old;
	} else {
	    $self->remove_hook("spool_request", \&setup_cookie);
	}
    }
    $old;
}


sub setup_cookie
{
    my($self, $req) = @_;
    my $jar = $self->{'cookie_jar'} || return 1;
    $jar->add_cookie_header($req);
    $req->add_hook("response_done",
		   sub {
		       my($req, $res) = @_;
		       $jar->extract_cookies($res);
		       1;
		   });
    0;
}


sub setup_proxy
{
    my($self, $req) = @_;
    my $proxy = $req->proxy;
    unless ($proxy) {
	$proxy = $self->{'uattr'}->p_attr($req->url, "proxy");
	return unless $proxy;
	$req->proxy($proxy);
    }

    # Set up Proxy-Authorization perhaps
    my $realms = $self->{'uattr'}->p_attr($proxy, "proxy_realms");
    return unless $realms && %$realms;

    if (keys %$realms > 1) {
	# there is multiple realms to choose from.  Select the
	# right one, if there is such a thing.
	my $realm = $self->{'uattr'}->p_attr($req->url, "proxy_realm");
	if (my $auth = $realms->{$realm}) {
	    $auth->set_proxy_authorization($req);
	}
    } else {
	# there is only one realm defined for this proxy server,
	# so we might as well use it.
	my($auth) = values %$realms;
	$auth->set_proxy_authorization($req);
    }
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
	} elsif ($_ eq "uattr") {
	    my $s = $self->{uattr}->as_string;
	    $s =~  s/^/    /mg; # indent
	    $str = "\$uattr = {\n$s};\n";
	} else {
	    $str = Data::Dumper->Dump([$self->{$_}], [$_]);
	}
	$str =~ s/^/  /mg;  # indent
	push(@str, $str);
    }

    join("", @str, "");
}

1;
