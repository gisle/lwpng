package LWP::Request;

use strict;
use vars qw(@ISA);

require HTTP::Request;
require LWP::Hooks;
@ISA=qw(HTTP::Request LWP::Hooks);

require URI::URL;

sub new2  # alternative ctor that sets up some handlers
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    require LWP::Redirect;
    $self->add_hook("response_handler", \&LWP::Redirect::response_handler);
    require LWP::Authen;
    $self->add_hook("response_handler", \&LWP::Authen::response_handler);
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


sub sending_start
{
    my $self = shift;
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
    my $done = $self->run_hooks_until_success("response_handler", $res);
    return if $done && $done ne "ABORT";

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

sub redirect_ok
{
    0;
}

sub login
{
    return;
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
