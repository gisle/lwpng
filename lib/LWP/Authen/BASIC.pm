package LWP::Authen::BASIC;
use strict;

require MIME::Base64;

sub authenticate
{
    my($class, $req, $res, $proxy, $auth_param) = @_;

    my($user, $pass) = $req->get_upw($auth_param->{realm},
				     $req->url, $proxy);
    unless (defined $user and defined $pass) {
	$res->push_header("Client-Warning", "No username or password given");
	return;
    }

    my $auth_header = $proxy ? "Proxy-Authorization" : "Authorization";
    my $auth_value = "Basic " . MIME::Base64::encode("$user:$pass", "");

    # Need to check this isn't a repeated fail!
    for (my $r = $res; $r; $r = $r->previous) {
        my $auth = $r->request->header($auth_header);
        if ($auth && $auth eq $auth_value) {
            # here we know this failed before
            $res->push_header("Client-Warning" =>
			      "Basic credentials for '$user' failed before");
            return;
        }
    }

    my $new = $req->clone;
    $new->{'previous'} = $res;
    $new->priority(10) if $new->priority > 10;
    $new->header($auth_header => $auth_value);
    $req->{'mgr'}->spool($new);
    1;
}

1;
