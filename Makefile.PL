require 5.004_04;
use ExtUtils::MakeMaker;

WriteMakefile(
   NAME         => "LWPng-alpha",
   VERSION_FROM => "lib/LWP/Version.pm",
   PREREQ_PM    => { LWP => '5.32', },
   dist         => { COMPRESS => 'gzip -9f', SUFFIX => 'gz'},
);
