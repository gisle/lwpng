package LWP::Request;

use strict;
use vars qw(@ISA);

require HTTP::Request;
@ISA=qw(HTTP::Request);

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
#
# Flags are:
#
#    want_progress_report
#    auto_redirect
#


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

    if ($self->{want_progress_report}) {
	$self->{received_bytes} += length($_[0]);
	my $percentage;
	if (my $cl = $res->header('Content-Length')) {
	    $percentage = sprintf "%.0f%%", 100 * $self->{received_bytes} / $cl;
	}
	$self->progress($percentage, $self->{received_bytes});
    }
}

sub progress
{
    my($self, $percentage, $bytes) = @_;
    print "$percentage\n" if $percentage;
}

sub clone
{
    my $self = shift;
    my $clone = $self->SUPER::clone;
    for (qw(priority proxy mgr data_cb done_cb)) {
	next unless exists $self->{$_};
	$clone->{$_} = $self->{$_};
    }
    $clone;
}

sub done
{
    my($self, $res) = @_;

    if (my $prev = $self->previous) {
	$res->previous($prev);
	$self->previous(undef);  # not stricly necessary
    }

    $res->request($self);

    if ($self->{done_cb}) {
	my $status = $self->{done_cb}->($res);
	# the idea was that $status would indicate if we are going to
	# continue with redirects etc.  Must think some more about this...
	return if $status;
    }

    if ($self->{auto_redirect} && $res->is_redirect) {
        my $referral = $self->clone;

        # And then we update the URL based on the Location:-header.
        # Some servers erroneously return a relative URL for redirects,
        # so make it absolute if it not already is.
        my $referral_uri = (URI::URL->new($res->header('Location'),
                                          $res->base))->abs();
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
	}
	
    } elsif ($self->{auth_cb}) {

    } else {
	$self->{'mgr'}->response_received($res);
    }
    
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
