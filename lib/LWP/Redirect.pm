package LWP::Redirect;

use strict;

sub response_handler
{
    my($req, $res) = @_;
    my $code = $res->code;
    return unless $code =~ /^30[012357]$/;
    my $new = $req->clone;
    my $method = $new->method;
    if ($code == 303 && $method ne "HEAD") {
	$method = "GET";
	$new->method($method);
    }
    return if $method ne "GET" &&
	      $method ne "HEAD" &&
	      !$req->redirect_ok($res);
    my $loc = $res->header('Location') || return;
    $loc = (URI::URL->new($loc, $res->base))->abs(undef,1);

    if ($code == 305) {  # RC_USE_PROXY
	$new->proxy($loc);
	my $ustr = $new->url->as_string;
	my $pstr = $loc->as_string;
	# check for loops
	for (my $r = $res; $r; $r = $r->previous) {
	    my $req = $r->request;
	    my $pxy = $req->proxy || "";
	    if ($req->url->as_string eq $ustr && $pxy eq $pstr) {
		$res->push_header("Client-Warning" =>
				  "Proxy redirect loop detected");
		return;
	    }
	}
    } else {
	$new->url($loc);
	my $ustr = $loc->as_string;
	# check for loops
	for (my $r = $res; $r; $r = $r->previous) {
	    if ($r->request->url->as_string eq $ustr) {
		$res->push_header("Client-Warning" =>
				  "Redirect loop detected");
		return;
	    }
	}
    }

    # New request is OK, spool it
    $new->{'previous'} = $res;
    $new->priority(10) if $new->priority > 10;
    $req->{'mgr'}->spool($new);
    1;  # consider this request handled
}

1;
