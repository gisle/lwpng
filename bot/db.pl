
use Mysql;
use URI::URL;
use strict;

use vars qw($dbh);
$dbh = Mysql->connect("", "ngbot", "aas") or die;


sub new_link
{
    my($uri, $ref_id, $type) = @_;
    $uri = URI::URL->new($uri) unless ref($uri);
    my $scheme = $uri->scheme || die "Not absolute URI";
    my $host   = $uri->host;
    $scheme = $dbh->quote(lc($scheme));
    $host   = $dbh->quote(lc($host));
    my $port   = $uri->port || 0;
    my $abs_path = $dbh->quote($uri->full_path);

    my $server_id;
    my $sth = $dbh->query("select id from server where scheme = $scheme and host=$host and port = $port") or die $dbh->errmsg;
    if ($sth->numrows) {
	($server_id) = $sth->fetchrow;
    } else {
	$sth = $dbh->query("insert into server (scheme,host,port) values($scheme,$host,$port)") or die $dbh->errmsg;
	$server_id = $sth->insertid;
    }
    my($uri_id, $last_visit, $status_code);
    $sth = $dbh->query("select id, last_visit, status_code from uri
where server=$server_id and abs_path=$abs_path") or die $dbh->errmsg;
    if ($sth->numrows) {
	($uri_id, $last_visit, $status_code) = $sth->fetchrow;
    } else {
	$sth = $dbh->query("insert into uri(server,abs_path) values($server_id,$abs_path)") or die $dbh->errmsg;
	$uri_id = $sth->insertid;
    }
    if ($ref_id) {
	$type = $dbh->quote($type || "a");
	$sth = $dbh->query("insert into links(src,dest,type) values($ref_id,$uri_id,$type)") or die $dbh->errmsg;
    }
    $uri_id;
}


sub forget_links_from
{
    my($ref_id) = @_;
    my $sth = $dbh->query("delete from links where src=$ref_id") or die $dbh->errmsg;
    return $sth->affectedrows;
}


sub visit
{
    my($uri_id, $code, $mess, $ct, $last_mod, $etag, $fresh, $size, $md5) = @_;

    # Find the server_id (and validate uri_id)
    my $sth = $dbh->query("select server from uri where id=$uri_id") or die $dbh->errmsg;
    die "No uri identified by $uri_id" unless $sth->numrows;
    my($server_id) = $sth->fetchrow;
    #print "server_id=$server_id\n";

    # Obtains appropriate content_type id
    my $ct_id;
    if (defined $ct and length $ct) {
	$ct = $dbh->quote(lc($ct));
	$sth = $dbh->query("select id from media_types where name=$ct") or die $dbh->errmsg;
	if ($sth->numrows) {
	    ($ct_id) = $sth->fetchrow;
	} else {
	    $sth = $dbh->query("insert into media_types(name) values($ct)") or die $dbh->errmsg;
	    $ct_id = $sth->insertid;
	}
    } else {
	$ct_id = "NULL";
    }
    #print "ct_id=$ct_id\n";

    my $e_id;
    if ($md5 && $size) {
	$md5 = $dbh->quote($md5);
	$sth = $dbh->query("select id from entity where size=$size and md5=$md5") or die $dbh->errmsg;
	if ($sth->numrows) {
	    ($e_id) = $sth->fetchrow;
	} else {
	    $sth = $dbh->query("insert into entity(size,md5) values($size,$md5)") or die $dbh->errmsg;
	    $e_id = $sth->insertid;
	}
	
    } else {
	$e_id = "NULL";
    }
    #print "e_id=$e_id\n";
    
    for ($mess, $etag) {
	$_ = $dbh->quote($_);
    }

    for ($code, $last_mod, $fresh, $size) {
	$_ = "NULL" unless $_;
    }

    my $last_visit = time;

    # Now we are ready to start updating
    $sth = $dbh->query("update server set last_visit=$last_visit where id=$server_id") or die $dbh->errmsg;
    $sth = $dbh->query("update uri set last_visit=$last_visit, status_code=$code,message=$mess,last_mod=$last_mod,etag=$etag,fresh_until=$fresh,content_length=$size,entity=$e_id,content_type=$ct_id where id=$uri_id") or die $dbh->errmsg;
    return $sth->affectedrows;
}

1;
