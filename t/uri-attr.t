print "1..2\n";

require URI::Attr;

$db = URI::Attr->new;

$url = "http://www.g.aas.no/foo/bar?foo=bar";

$db->attr_update("GLOBAL")->{"foo"} = 1;
$db->attr_update(SERVER => $url)->{"foo"} = 2;
$db->attr_update(DOMAIN => $url)->{"foo"} = 3;
$db->attr_update(DOMAIN => $url)->{"bar"} = 3;

$db->attr_update(PATH => "file:/gisle/aas")->{"a"} = 1;
$db->attr_update(DIR  => "file:/gisle/aas")->{"a"} = 2;

sub attr_str
{
   join(",", map {"$_->[0]-$_->[1]"} @_);
}


@a = $db->attr("file:/gisle/aas", "a");
$a = $db->attr("file:/gisle/aas", "a");

print "not " unless attr_str(@a) eq "PATH-1,DIR-2";
print "ok 1\n";

print "not " unless attr_str($a) eq "PATH-1";
print "ok 2\n";

