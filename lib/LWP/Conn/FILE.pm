package LWP::Conn::FILE;
use strict;
require HTTP::Response;

use HTTP::Date qw(time2str);
use LWP::MediaTypes qw(guess_media_type);

sub new
{
    my($class, %cnf) = @_;
    my $mgr = delete $cnf{ManagedBy} ||
      Carp::croak("'ManagedBy' is mandatory");
    # don't care about other configuration parameters

    # process all request in the queue
    while (my $req = $mgr->get_request(__PACKAGE__)) {
	my $url = $req->url;
	my $host = $url->host;
	if ($host && $host ne "localhost") {
	    # generate redirect to ftp serveer
	    my $loc = $url->as_string;
	    $loc =~ s/^\w+:/ftp:/;
	    $req->gen_response(301, "Use ftp instead", {Location => $loc});
	    next;
	}

	my $method = uc($req->method);
	my $path = $url->local_path;

	if ($method eq "HEAD" || $method eq "GET") {
	    get($req, $path, $method eq "GET");

	} elsif ($method eq "PUT") {
	    if ($req->header("Content-Range")) {
		$req->gen_response(506, "Don't handle partial content updates yet");
		next;
	    }
	    put($req, $path);

	} elsif ($method eq "DELETE") {
	    if (unlink($path)) {
		$req->gen_response(204, "OK");
	    } else {
		$req->gen_response(errno_status(), "$!");
	    }

	} elsif ($method eq "TRACE") {  # Just for fun!
	    my $res = HTTP::Response->new(200, "OK");
	    $res->date(time);
	    $res->server("libwww-perl");
	    $res->content_type("message/http");
	    $res->content($req->as_string);
	    $req->done($res);

	} else {
	    $req->gen_response(405, "Bad method '$method'");
	}
    }

    undef;  # not really a connection
}

sub get
{
    my($req, $path, $send_content) = @_;

    local(*DIR);
    if (opendir(DIR, $path)) {
	dir($req, $path, \*DIR, $send_content);
	closedir(DIR);
	return;
    }

    local(*FILE);
    if (sysopen(FILE, $path, 0)) {
	my $res = HTTP::Response->new(200, "OK");
	$res->date(time);
	$res->server("libwww-perl");

	my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$filesize,
	   $atime,$mtime,$ctime,$blksize,$blocks) = stat(FILE);

	my $uname = getpwuid($uid) || $uid;
	my $gname = getgrgid($gid) || $gid;

	# far more than you ever wanted to know
	$res->header("I-Node" => sprintf("[%04x]:%d", $dev, $ino)) if $ino;
	$res->header("Owner" => $uname);
	$res->header("Group" => $gname);
	$res->header("Content-Length" => $filesize);
	$res->header("Blocks-Allocated" => $blocks);
	$res->header("Last-Modified" => time2str($mtime));
	$res->header("Last-Accessed" => time2str($atime));
	$res->header("Status-Modified" => time2str($ctime));

	$res->header("Content-Location" => "file:$path");
	guess_media_type($path, $res);

	# XXX Might also implement support of headers like:
	#    Accept
	#    Etag
        #    If-XXX
	#    Range

	if ($send_content) {
	    my $buf;
	    while (my $n = sysread(FILE, $buf, 1024)) {
		$req->response_data($buf, $res);
	    }
	}
	close(FILE);
	$req->done($res)

    } else {
	$req->gen_response(errno_status(), "$!");
    }
}

sub dir
{
    my($req, $path, $dir, $send_content) = @_;
    $req->gen_response(501, "Directory reading", $path); #NYI
}

sub put
{
    my($req, $path) = @_;
    $req->gen_response(501, "File updating", $path); #NYI
}

sub errno_status
{
    if ($! =~ /No such file/) {
	return 404;
    } else {
	return 403;
    }
}

1;
