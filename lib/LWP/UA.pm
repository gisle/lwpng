package LWP::UA;
require LWP::Hooks;
@ISA=qw(LWP::Hooks);

use strict;
use vars qw($DEBUG $VERSION);
$VERSION = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);

use LWP::MainLoop qw(mainloop);

require LWP::Server;
require URI::Attr;

sub new_plain
{
    my $class = shift;
    my $ua =
	bless {
	       ua_uattr    => URI::Attr->new,
	       ua_max_conn => 5,
	       ua_servers  => {},
	      }, $class;
    $ua;
}

sub new
{
    my $class = shift;
    my $ua = $class->new_plain;
    $ua->setup_default_handlers;
    $ua->agent("libwww-perl/ng-alpha ($^O)");
    $ua;
}

sub setup_default_handlers
{
    my $self = shift;
    $self->add_hook("spool_request", \&_setup_default_headers);

    eval { require HTML::HeadParser; };
    unless ($@) {
	$self->add_hook("spool_request", \&_setup_head_parser);
    }

    require LWP::UA::Proxy;
    $self->add_hook("spool_request", \&LWP::UA::Proxy::spool_handler);

    require LWP::Authen;
    $self->add_hook("spool_request", \&LWP::Authen::spool_handler);
}

sub uri_attr
{
    my $self = shift;
    @_ ? $self->{'ua_uattr'}->attr(@_) : $self->{'ua_uattr'};
}

sub uri_attr_plain
{
    my $self = shift;
    $self->{'ua_uattr'}->attr_plain(@_);
}

sub uri_attr_update
{
    my $self = shift;
    $self->{'ua_uattr'}->attr_update(@_);
}

sub agent
{
    my $self = shift;
    my $old = $self->{'ua_agent'};
    if (@_) {
	my $agent = $self->{'ua_agent'} = shift;
	for ("http", "https") {
	    $self->uri_attr_update(SCHEME => "$_:")
		->{'default_headers'}{'User-Agent'} = $agent;
	}
	$self->uri_attr_update(SCHEME => "mailto:")
	    ->{'default_headers'}{'X-Mailer'} = $agent;
	$self->uri_attr_update(SCHEME => "news:")
	    ->{'default_headers'}{'X-Newsreader'} = $agent;
    }
    $old;
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

    my $server = $self->{ua_servers}{$netloc};
    unless ($server) {
	$server = $self->{ua_servers}{$netloc} =
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

	# Some initial tests.  These could be made optional by putting
	# them in a spool_request hook too.
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

sub request
{
    my($self, $req) = @_;
    my $res;
    my $old_cb = $req->{done_cb};
    $req->{done_cb} = sub { $res = $_[0]; &$old_cb(@_) if $old_cb };
    $self->spool($req);
    mainloop->one_event until $res || mainloop->empty();
    $res;
}


sub response_received
{
    my($self, $res) = @_;
    push(@{$self->{'ua_responses'}}, $res);
}


sub stop
{
    my $self = shift;
    foreach (values %{$self->{ua_servers}}) {
	$_->stop;
    }
}


sub reschedule
{
    my $self = shift;
    my $sched = $self->{'ua_scheduler'};
    unless ($sched) {
	require LWP::StdSched;
	$sched = $self->{'ua_scheduler'} = LWP::StdSched->new($self);
    }
    $sched->reschedule($self);
}

sub max_conn
{
    my $self = shift;
    my $old = $self->{'ua_max_conn'};
    if (@_) {
	$self->{'ua_max_conn'} = shift;
    }
    $old;
}


sub delete
{
    # must break circular references
    my $self = shift;
    delete $self->{'ua_servers'};
}


sub _setup_default_headers
{
    my($self, $req) = @_;
    for my $hash ($self->uri_attr_plain($req->url, "default_headers")) {
	for my $k (keys %$hash) {
	    next if defined($req->header($k));
	    $req->header($k => $hash->{$k});
	}
    }
    0; # continue
}


sub _response_data_hp
{
    my($req,$data,$res) = @_;
    my $hp = $req->{head_parser};
    unless ($hp) {
	if ($res->content_type eq "text/html") {	
	    $req->{head_parser} = $hp = HTML::HeadParser->new($res);
	} else {
	    $req->remove_hook("response_data", \&_response_data_hp);
	    return;
	}
    }
    unless ($hp->parse($data)) {
	# done
	delete $req->{head_parser};
	$req->remove_hook("response_data", \&_response_data_hp);
    }
}

sub _setup_head_parser
{
    my($self,$req) = @_;
    $req->add_hook("response_data", \&_response_data_hp);
    0;
}

1;
