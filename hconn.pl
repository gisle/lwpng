use lib "./lib";

use HConn;

package LWP::Request;

require HTTP::Request;
use base qw(HTTP::Request);

package MGR;

sub new { bless {}, $_[0] }

sub get_request
{
    my($self, $conn) = @_;
    my $req = LWP::Request->new(GET => "http://furu/nph-slowdata.cgi2");
    $req->header("User-Agent" => "foo/0.01");
    $req;
}

sub pushback_request
{
    my($self, $req, $conn) = @_;
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

$c1 = HConn->new("127.0.0.1", 80, $mgr);
$c2 = HConn->new("furu", 80, $mgr);

use Data::Dumper;

print Dumper($c1, $c2);

#$LWP::EventLoop::DEBUG++;
while (!mainloop->empty) {
    #mainloop->dump;
    mainloop->one_event;
}
