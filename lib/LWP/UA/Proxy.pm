package LWP::UA;

# Setup methods that deal with proxies

sub setup_proxy
{
    my($self, $req) = @_;
    my $proxy = $req->proxy;
    unless ($proxy) {
	$proxy = $self->uri_attr_plain($req->url, "proxy");
	return unless $proxy;
	$req->proxy($proxy);
    }

    # Set up Proxy-Authorization perhaps
    my $realms = $self->uri_attr_plain($proxy, "proxy_realms");
    return unless $realms && %$realms;

    if (keys %$realms > 1) {
	# there is multiple realms to choose from.  Select the
	# right one, if there is such a thing.
	my $realm = $self->uri_attr_plain($req->url, "proxy_realm");
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
	my $h = $self->uri_attr_update("DOMAIN", "http://dummy.$_");
	$h->{"proxy"} = "";
    }
}

sub proxy
{
    my($self, $scheme, $url) = @_;
    my $h = $self->uri_attr_update("SCHEME", "$scheme:");
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

1;
