# Some experiments in implementing the old LWP::UserAgent interface on
# top of the new LWP::UA.

package LWP::UA_old;
use strict;

use LWP::MainLoop qw(mainloop);
require LWP::Request;
require LWP::UA;

sub new
{
    my $class = shift;
    bless
	{
	 'ua' => LWP::UA->new,
	}, $class;
}

sub DESTROY
{
    my $self = shift;
    $self->{'ua'}->delete;
}

sub request
{
    my($self, $req, $arg, $size) = @_;
    $req->{'auto_redirect'}++;
    $req->{'auto_auth'}++;
    $self->simple_request($req, $arg, $size);
}

sub simple_request
{
    my($self, $req, $arg, $size) = @_;

    bless $req, "LWP::Request" if ref($req) eq "HTTP::Request";
    if ($arg) {
	# XXX should generate file writing closure unless ref($arg)
	$req->{'data_cb'} = $arg;
    }
    # We always ignore the $size hint.  I don't think that is a problem

    # Set up a callback closure that will update our $res variable
    # when the request is done.
    my $res;
    $req->{'done_cb'} =
	sub {
	    my $req = shift;
	    $res = shift;
	    print "OUR DONE\n";
	    1;
	};

    $self->{'ua'}->spool($req);

    # Run eventloop until we have a response available
    while (!$res && !mainloop->empty) {
	mainloop->one_event;
    }

    return $res;
}

1;
