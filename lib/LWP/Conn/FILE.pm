package LWP::Conn::FILE;
use strict;
require HTTP::Response;
require LWP::Version;

# Ideally, we should make this implementation shareable with
# HTTP::Daemon.

use HTTP::Date qw(time2str str2time);
use LWP::MediaTypes qw(guess_media_type);

sub new
{
    my($class, %cnf) = @_;
    my $mgr = delete $cnf{ManagedBy} ||
      Carp::croak("'ManagedBy' is mandatory");
    # don't care about other configuration parameters yet

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
	    # XXX must really handle If-XXX headers
	    if (unlink($path)) {
		$req->gen_response(204, "OK");
	    } else {
		$req->gen_response(errno_status(), "$!");
	    }

	} elsif ($method eq "TRACE") {  # Just for fun!
	    my $res = HTTP::Response->new(200, "OK");
	    $res->date(time);
	    $res->server($LWP::Version::PRODUCT_TOKEN);
	    $res->content_type("message/http");
	    $res->content($req->as_string);
	    $req->response_done($res);

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
	my $now = time;

	$res->date($now);
	$res->server($LWP::Version::PRODUCT_TOKEN);

	my($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$filesize,
	   $atime,$mtime,$ctime,$blksize,$blocks) = stat(FILE);

	my $uname = getpwuid($uid) || $uid;
	my $gname = getgrgid($gid) || $gid;

	# far more than you ever wanted to know
	$res->header("INode" => sprintf("[%04x]:%d", $dev, $ino)) if $ino;
	$res->header("Owner" => $uname);
	$res->header("Group" => $gname);
	$res->header("Content-Length" => $filesize);
	$res->header("Blocks-Allocated" => $blocks);
	$res->header("Last-Modified" => time2str($mtime));
	$res->header("Last-Accessed" => time2str($atime));
	$res->header("Status-Modified" => time2str($ctime));

	$res->header("Content-Location" => "file:$path"); # XXX absolutize
	guess_media_type($path, $res);

	# We use the same algoritm as Apache to generate an etag.
	my $etag = sprintf qq("%x-%x-%x"), $ino, $filesize, $mtime;
	$etag = "W/$etag" if $now - $mtime < 2;
	$res->header("ETag" => $etag);

	# Check various If-XXX headers
	if (my $ius = $req->header("If-Unmodified-Since")) {
	    $ius = str2time($ius);
	    if ($ius && $mtime > $ius) {
		$res->code(412); # PRECONDITION_FAILED
		$res->message("Resouce modified");
		close(FILE);
		$req->response_done($res);
		return;
	    }
	}

	if (my @im = $req->header("If-Match")) {
	    my $im = join(", ", @im);
	    my $orig_im = $im;
	    if ($im ne "*") {
		my $match = 0;
		while (length($im)) {
		    if ($im =~ s|^\s*(W/)?(\"[^\"]*\")\s*,?\s*||) {
			next if $1;  # must use strong comparison
			if ($2 eq $etag) {
			    $match++;
			    last;
			}
		    } else {
			last;  # illegal value
		    }
		}
		#$res->header("X-Unprocessed-If-Match", $im) if $im;
		unless ($match) {
		    $res->code(412); # PRECONDITION_FAILED
		    $res->message("No match for ETag $orig_im");
		    close(FILE);
		    $req->response_done($res);
		    return;
		}
	    }
	}

	my $skip_if_modified;
	if (my @inm = $req->header("If-None-Match")) {
	    my $inm = join(", ", @inm);
	    my $match;
	    my $etag2 = $etag;
	    $etag2 =~ s,^W/,,;
	    $match = "*" if $inm eq "*";
	    while (!$match && length($inm)) {
		if ($inm =~ s|^\s*(W/?(\"[^\"]*\"))\s*,?\s*||) {
		    $match = $1 if $2 eq $etag;
		} else {
		    last;  # illegal value
		}
	    }
	    if ($match) {
		#$res->code(412); # PRECONDITION_FAILED
		$res->code(304); # NOT_MODIFIED
		$res->message("ETag match for $match");
		close(FILE);
		$req->response_done($res);
		return;
	    }
	    $skip_if_modified++;
	}
	
	if (!$skip_if_modified &&
	    (my $ims = $req->header("If-Modified-Since"))) {
	    $ims = str2time($ims);
	    if ($ims && $mtime <= $ims) {
		$res->code(304);
		$res->message("Not modified");
		close(FILE);
		$req->response_done($res);
		return;
	    }
	}

	# XXX Implement the Range header???

	if ($send_content) {
	    my $buf;
	    while (my $n = sysread(FILE, $buf, 1024)) {
		eval {
		    $req->response_data($buf, $res);
		};
		if ($@) {
		    chomp($@);
		    $res->header('X-Died' => $@);
		    last;
		}
	    }
	}
	close(FILE);
	$req->response_done($res)

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
