use ExtUtils::MakeMaker;
WriteMakefile(
              NAME => "LWPng-alpha",
              VERSION => '0.11',
	      PREREQ_PM => { LWP => '5.22', },
              'dist' => {COMPRESS=>'gzip -9f', SUFFIX => 'gz'}
             );
