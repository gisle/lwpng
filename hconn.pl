use lib "./lib";

my $no=0;

use LWP::Conn::HTTP;

package LWP::Request;

require HTTP::Request;
use base qw(HTTP::Request);

sub response_data
{
    my($self, $data, $res) = @_;
    # do something
    #print "DATA CALLBACK: [$data]\n";
    $res->add_content($data);
}

sub done
{
    my($self, $res) = @_;
    $no++;
    print "DONE $no\n";
    print $res->as_string;
}

sub proxy
{
    0;
}

#sub progress
#{
#    my($self, $msg, $req_bytes, $req_of, $res_bytes, $res_of) = @_;
#    # Something that might update the progress bar or display the message
#}


package MGR;

@req = qw(/); # /nph-slowdata.cgi / /nph-slowdata.cgi  /not-found);

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
    my($self, $conn, @r) = @_;
    my $no = int @r;
    print STDERR "PUSHBACK $no requests\n";
    unshift(@req, @r);
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

#$LWP::Conn::HTTP::DEBUG++;
#$LWP::EventLoop::DEBUG++;

for (1..1) {

    LWP::Conn::HTTP->new(
			 ManagedBy   => $mgr,
			 PeerAddr    => "127.0.0.1:12467",
			 ReqPending  => 2,
			 ReqLimit    => 100,
			 Timeout     => 20,
			 IdleTimeout => 200,
			);

}

use LWP::MainLoop qw(empty one_event);
while (!empty) {
    one_event();
}
