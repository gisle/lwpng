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
	if (ref($arg)) {
	    # assume a normal callback, and the signature is close enough
	    # that we don't need an adaptor.
	    $req->{'data_cb'} = $arg;
	} else {
	    # Save content in file, set up closure that will open/create
	    # file and save the response data here
	    my $file;
	    $req->{'data_cb'} =
		sub {
		    unless ($file) {
			require IO::File;
			$file = IO::File->new($arg, "w") ||
			    die "Can't open file: $!";
			binmode($file);
		    }
		    $file->print($_[0]);
		};
	    $req->{'clear_data_cb'}++;  # will close the file when done
	}
    }
    # We always ignore the $size hint.  I don't think that is a problem

    # Set up a callback closure that will update our $res variable
    # when the request is done.
    my $res;
    $req->{'done_cb'} =
	sub {
	    my $req = shift;
	    delete $req->{'data_cb'} if delete $req->{'clear_data_cb'};
	    $res = shift;
	    #print "OUR DONE\n";
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
