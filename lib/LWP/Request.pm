package LWP::Request;

use strict;
use vars qw(@ISA);

require HTTP::Request;
require LWP::Hooks;
@ISA=qw(HTTP::Request LWP::Hooks);

require URI::URL;

# HTTP::Request attributes:
#
#    method
#    url
#    header
#    content
#
# Added stuff are:
#
#    hooks
#    priority
#    proxy
#    data_cb
#    done_cb
#    mgr
#   (previous)
#

sub new2
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->add_hook("response_handler", \&auto_redirect);
    $self->add_hook("response_handler", \&auto_auth);
    $self;
}


sub clone
{
    my $self = shift;
    my $clone = $self->SUPER::clone;
    for (qw(priority proxy mgr data_cb done_cb)) {
	next unless exists $self->{$_};
	$clone->{$_} = $self->{$_};
    }
    $clone->copy_hooks_from($self, "response_handler");
    $clone;
}


sub response_data
{
    my $self = shift;
    # don't want to copy data in $_[0] unnecessary
    my $res = $_[1];
    $self->run_hooks("response_data", $_[0], $res);
    if ($self->{data_cb} && $res->is_success) {
	$self->{data_cb}->($_[0], $res, $self);
    } else {
	$res->add_content($_[0]);
    }
}


sub response_done
{
    my($self, $res) = @_;

    if (my $prev = $self->{'previous'}) {
	$res->previous($prev);
	delete $self->{'previous'};  # not strictly necessary
    }
    $res->request($self);#or should we depend on the connection to set this up?

    $self->run_hooks("response_done", $res);
    return if $self->run_hooks_until_success("response_handler", $res);

    if ($self->{done_cb}) {
	$self->{done_cb}->($res, $self);
    } else {
	$self->{'mgr'}->response_received($res);
    }
}


sub gen_response
{
    my($self, $code, $message, $more) = @_;
    require HTTP::Response;
    my $res = HTTP::Response->new($code, $message);
    $res->date(time);
    $res->server("libwww-perl/ng");
    if ($more) {
	if (ref($more)) {
	    while (my($k,$v) = each %$more) {
		$res->header($k => $v);
	    }
	} else {
	    $res->content_type(($more =~ /^\s*</) ? "text/html" : "text/plain");
	    $res->content($more);
	}
    } elsif (0 && $message) {
	$res->content_type("text/html");
	$res->content("<title>$message</title>\n<h1>$code $message</h1>\n");
	$res->add_content("Error generated internally by the client.\n")
	    if $res->is_error;
    }
    
    $self->response_done($res);
}

sub auto_redirect
{
    my($self, $res) = @_;
    my $code = $res->code;
    return unless $code =~ /^30[012357]$/;
    my $new = $self->clone;
    my $method = $new->method;
    if ($code == 303 && $method ne "HEAD") {
	$method = "GET";
	$new->method($method);
    }
    return if $method ne "GET" &&
	      $method ne "HEAD" &&
	      !$self->redirect_ok($res);
    my $loc = $res->header('Location') || return;
    $loc = (URI::URL->new($loc, $res->base))->abs(undef,1);

    if ($code == 305) {  # RC_USE_PROXY
	$new->proxy($loc);
	my $ustr = $new->url->as_string;
	my $pstr = $loc->as_string;
	# check for loops
	for (my $r = $res; $r; $r = $r->previous) {
	    my $req = $r->request;
	    my $pxy = $req->proxy || "";
	    if ($req->url->as_string eq $ustr && $pxy eq $pstr) {
		$res->push_header("Client-Warning" =>
				  "Proxy redirect loop detected");
		return;
	    }
	}
    } else {
	$new->url($loc);
	my $ustr = $loc->as_string;
	# check for loops
	for (my $r = $res; $r; $r = $r->previous) {
	    if ($r->request->url->as_string eq $ustr) {
		$res->push_header("Client-Warning" =>
				  "Redirect loop detected");
		return;
	    }
	}
    }

    # New request is OK, spool it
    $new->{'previous'} = $res;
    $new->priority(10) if $new->priority > 10;
    $self->{'mgr'}->spool($new);
    1;  # consider this request handled
}

sub redirect_ok
{
    0;
}

sub auto_auth
{
    my($self, $res) = @_;
    my $code = $res->code;
    return unless $code =~ /^40[17]$/;
    my $proxy = ($code == 407);

    my $ch_header = $proxy ?  "Proxy-Authenticate" : "WWW-Authenticate";
    my @challenge = $res->header($ch_header);
    unless (@challenge) {
	$res->header("Client-Warning" => 
		     "Missing $ch_header header");
	return;
    }

    require HTTP::Headers::Util;
    for my $challenge (@challenge) {
	$challenge =~ tr/,/;/;  # "," is used to separate auth-params!!
	($challenge) = HTTP::Headers::Util::split_header_words($challenge);
	my $orig_scheme = shift(@$challenge);
	shift(@$challenge); # no value
	my $scheme = uc($orig_scheme);
	$challenge = { @$challenge };  # make rest into a hash

	unless ($scheme =~ /^([A-Z]+(?:-[A-Z]+)*)$/) {
	    $res->header("Client-Warning" => 
			 "Bad authentication scheme name '$orig_scheme'");
	    next;
	}
	$scheme = $1;  # untainted now
	my $class = "LWP::Authen::$scheme";
	$class =~ s/-/_/g;
	
	no strict 'refs';
	unless (defined %{"$class\::"}) {
	    # try to load it
	    eval "require $class";
	    if ($@) {
		if ($@ =~ /^Can\'t locate/) {
		    $res->push_header("Client-Warning" =>
			   "Unsupport authentication scheme '$orig_scheme'");
		} else {
		    $res->push_header("Client-Warning" => $@);
		}
		next;
	    }
	}
	my $done = $class->authenticate($self, $res, $proxy, $challenge);
	return $done if $done;
    }
    $res->push_header("Client-Warning" => "Kilroy was here");
    0;
}

sub get_upw
{
    ("gisle", "hemmelig");
}


# Accessor functions for some simple attributes

sub managed_by
{
    my $self = shift;
    my $old = $self->{'mgr'};
    if (@_) {
	$self->{'mgr'} = shift;
    }
    $old;
}

sub priority
{
    my $self = shift;
    my $old = $self->{'priority'} || 99;
    if (@_) {
	$self->{'priority'} = shift;
    }
    $old;
}

sub proxy
{
    my $self = shift;
    my $old = $self->{'proxy'};
    if (@_) {
	$self->{'proxy'} = shift;
    }
    $old;
}

1;
