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
#    priority
#    proxy
#    data_cb
#    done_cb
#    mgr
#   (previous)
#
# Added flags are:
#
#    want_progress_report
#    auto_redirect
#    auto_auth
#


sub clone
{
    my $self = shift;
    my $clone = $self->SUPER::clone;
    for (qw(priority proxy mgr data_cb done_cb
            want_progress_report auto_redirect auto_auth)) {
	next unless exists $self->{$_};
	$clone->{$_} = $self->{$_};
    }
    $clone;
}

sub response_data
{
    my $self = shift;
    # don't want to copy data in $_[0] unnecessary
    my $res = $_[1];
    if ($self->{data_cb} && $res->is_success) {
	$self->{data_cb}->($_[0], $res, $self);
    } else {
	$res->add_content($_[0]);
    }
    $self->run_hooks("response_data", $_[0], $res);

=com
    if ($self->{want_progress_report}) {
	$self->{received_bytes} += length($_[0]);
	my $percentage;
	if (my $cl = $res->header('Content-Length')) {
	    $percentage = sprintf "%.0f%%", 100 * $self->{received_bytes} / $cl;
	}
	# XXX also calculate average throughput...
	$self->progress($percentage, $self->{received_bytes});
    }
=cut
}

sub progress
{
    my($self, $percentage, $bytes) = @_;
    if ($percentage) {
	print "$percentage\n";
    } else {
	print "$bytes bytes received\n";
    }
}

sub response_done
{
    my($self, $res) = @_;

    if (my $prev = $self->previous) {
	$res->previous($prev);
	$self->previous(undef);  # not stricly necessary
    }
    $res->request($self);#or should we depend on the connection to set this up?

=com
    
    my $code = $res->code;
    if ($self->{auto_redirect} &&
	($code == 301 ||  # MOVED_PERMANENTLY
	 $code == 302 ||  # FOUND
	 $code == 305 ||  # USE_PROXY
	 $code == 307)    # TEMPORARY REDIRECT
       ) {
        my $referral = $self->clone;

        # And then we update the URL based on the Location:-header.
        # Some servers erroneously return a relative URL for redirects,
        # so make it absolute if it not already is.
        my $referral_uri = (URI::URL->new($res->header('Location'),
                                          $res->base))->abs;
        $referral->url($referral_uri);

        # Check for loop in the redirects
      LOOP_CHECK: {
	    my $r = $res;
	    while ($r) {
		if ($r->request->url->as_string eq $referral_uri->as_string) {
		    $res->header("Client-Warning" =>
				 "Redirect loop detected");
		    last LOOP_CHECK;
		}
		$r = $r->previous;
	    }

	    # Respool new request with fairly high priority
	    $referral->previous($res);
	    $referral->priority(10) if $referral->priority > 10;
	    $self->{'mgr'}->spool($referral);
	    return;
	}
	
    } elsif (0 && $self->{auto_auth} &&
	     ($res->code == &HTTP::Status::RC_UNAUTHORIZED ||
	      $res->code == &HTTP::Status::RC_PROXY_AUTHENTICATION_REQUIRED))
    {
	#XXX NYI

    }

=cut

    $self->run_hooks_until_failure("response_done", $res) && return;

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

# Accessor functions for some simple attributes

sub previous
{
    my $self = shift;
    my $old = $self->{'previous'};
    if (@_) {
	$self->{'previous'} = shift;
    }
    $old;
}

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
