use lib "./lib";

use LWP::HConn;

package LWP::Request;

require HTTP::Request;
use base qw(HTTP::Request);

sub receive_data
{
    # do something
}


package MGR;

@req = qw(/ / / /not-found); #/slowdata.cgi /not-found /); # /nph-slowdata.cgi / /nph-slowdata.cgi  /not-found);

sub new { bless {}, $_[0] }

sub get_request
{
    my($self, $conn) = @_;
    my $path = shift(@req) || return;
    my $req = LWP::Request->new(GET => "http://furu$path");
    $req->header("User-Agent" => "foo/0.01");
    $req;
}

sub pushback_request
{
    my($self, $conn, @req) = @_;
    print STDERR "PUSHBACK\n";
}

sub connection_idle
{
    my($self, $conn) = @_;
}

sub connection_closed
{
    my($self, $conn) = @_;
}



package main;

use LWP::EventLoop qw(mainloop);

$mgr = new MGR;

$c1 = LWP::HConn->new("127.0.0.1", 80, $mgr);
#$c2 = LWP::HConn->new("furu", 80, $mgr);

use Data::Dumper;

print Dumper($c1, $c2);

#$LWP::EventLoop::DEBUG++;
while (!mainloop->empty) {
    #mainloop->dump;
    mainloop->one_event;
}
