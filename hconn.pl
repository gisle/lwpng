use lib "./lib";

use LWP::HConn;

package LWP::Request;

require HTTP::Request;
use base qw(HTTP::Request);

sub response_data
{
    my($self, $data, $res) = @_;
    # do something
    print "DATA CALLBACK: [$data]\n";
}

sub done
{
    print "DONE ";
    #print $_[1]->as_string;
    print "\n";
}

#sub progress
#{
#    my($self, $msg, $req_bytes, $req_of, $res_bytes, $res_of) = @_;
#    # Something that might update the progress bar or display the message
#}


package MGR;

@req = qw(/xxx /); # /nph-slowdata.cgi / /nph-slowdata.cgi  /not-found);

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
    print STDERR "CONN IDLE\n";
    #$conn->stop;
}

sub connection_closed
{
    my($self, $conn) = @_;
    print STDERR "CONN CLOSED\n";
}



package main;

$mgr = new MGR;

#$LWP::HConn::DEBUG++;
#$LWP::EventLoop::DEBUG++;

LWP::HConn->new(ManagedBy => $mgr,
		PeerAddr => "127.0.0.1",
		ReqPending => 3,
		ReqLimit   => 10,
		Timeout    => 8,
	       );

#$c2 = LWP::HConn->new("furu", 80, $mgr);

#use Data::Dumper; print Dumper($c1, $c2);

use LWP::MainLoop qw(empty one_event);

while (!empty) {
    one_event();
}
