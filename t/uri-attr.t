print "1..6\n";

require URI::Attr;

$db = URI::Attr->new;

$url = "http://www.g.aas.no/foo/bar?foo=bar";

$db->attr_update("GLOBAL")->{"foo"} = 1;
$db->attr_update(SERVER => $url)->{"foo"} = 2;
$db->attr_update(DOMAIN => $url)->{"foo"} = 3;
$db->attr_update(DOMAIN => $url)->{"bar"} = 3;

$db->attr_update(PATH => "http://www.g.aas.no")->{"path"} = 1;
$db->attr_update(DIR  => "http://www.g.aas.no")->{"dir"}  = 1;
$db->attr_update(PATH => "http://www.g.aas.no/foo/")->{"path"} = 2;
$db->attr_update(DIR  => "http://www.g.aas.no/foo/")->{"dir"}  = 2;

$db->attr_update(PATH => "file:/gisle/aas")->{"a"} = 1;
$db->attr_update(DIR  => "file:/gisle/aas")->{"a"} = 2;

sub attr_str { join(",", map {"$_->[0]-$_->[1]"} @_); }

@a = $db->attr("file:/gisle/aas", "a");
$a = $db->attr("file:/gisle/aas", "a");

print "not " unless attr_str(@a) eq "PATH-1,DIR-2";
print "ok 1\n";

print "not " unless attr_str($a) eq "PATH-1";
print "ok 2\n";

print "not " unless $db->p_attr("file:/gisle/aas", "a") eq "1";
print "ok 3\n";

print "not " unless join(",", $db->p_attr("file:/gisle/aas", "a")) eq "1,2";
print "ok 4\n";

print "not " unless $db->p_attr("file:/gisle/", "a") eq "2";
print "ok 5\n";

print "not " if defined($db->p_attr("file:/gisle", "a"));
print "ok 6\n";

#-----------------------------------------------------------------
